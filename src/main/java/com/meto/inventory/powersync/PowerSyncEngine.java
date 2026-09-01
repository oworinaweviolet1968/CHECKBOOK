package com.meto.inventory.powersync;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.meto.inventory.services.SupabaseService;

import java.sql.Connection;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Auth-aware write queue processor with adaptive scheduling.
 *
 * Key behaviors:
 * - On 401: triggers TokenManager refresh, retries batch once, doesn't count as operation failure
 * - On 5xx/429: uses RetryPolicy backoff, increments operation retry_count
 * - On 4xx: marks operations for dead-letter after MAX_RETRIES
 * - On network error: applies backoff, doesn't increment retry (transient)
 * - Adapts poll interval based on success/failure (5s normal, backoff on errors)
 */
public class PowerSyncEngine {
    private static PowerSyncEngine instance;

    private static final int MAX_RETRIES = 10;
    private static final long BASE_POLL_MS = 5000;
    private static final long MAX_POLL_MS = 60000;

    private final ScheduledExecutorService scheduler = Executors.newSingleThreadScheduledExecutor(r -> {
        Thread t = new Thread(r, "PowerSyncThread");
        t.setDaemon(true);
        return t;
    });
    private final AtomicBoolean isProcessing = new AtomicBoolean(false);
    private final AtomicInteger consecutiveErrors = new AtomicInteger(0);
    private volatile ScheduledFuture<?> currentTask;
    private volatile boolean running = false;

    private PowerSyncEngine() {}

    public static synchronized PowerSyncEngine getInstance() {
        if (instance == null) {
            instance = new PowerSyncEngine();
        }
        return instance;
    }

    public void start() {
        if (running) return;
        running = true;
        scheduleNext(2000); // Initial 2s delay
    }

    public void stop() {
        running = false;
        if (currentTask != null) {
            currentTask.cancel(false);
        }
        scheduler.shutdown();
    }

    /**
     * Schedule the next queue processing with adaptive delay.
     */
    private void scheduleNext(long delayMs) {
        if (!running) return;
        try {
            currentTask = scheduler.schedule(this::processWriteQueue, delayMs, TimeUnit.MILLISECONDS);
        } catch (java.util.concurrent.RejectedExecutionException ignored) {
            // Scheduler was shut down
        }
    }

    public void processWriteQueue() {
        if (!isProcessing.compareAndSet(false, true)) {
            scheduleNext(BASE_POLL_MS);
            return;
        }

        long nextDelay = BASE_POLL_MS;

        try {
            Connection conn = com.meto.inventory.DataManager.getInstance().getDbHelper().getConnection();
            if (conn == null) return;

            // Bounded Queue Chunking: 50 items per batch, excluding dead-letter items
            List<Map<String, String>> batch = WriteQueueManager.fetchPendingBatch(conn, 50);
            if (batch.isEmpty()) {
                consecutiveErrors.set(0);
                return;
            }

            // Filter out operations that have exceeded MAX_RETRIES
            List<Map<String, String>> processable = new ArrayList<>();
            for (Map<String, String> item : batch) {
                int retryCount = 0;
                try {
                    retryCount = Integer.parseInt(item.getOrDefault("retry_count", "0"));
                } catch (NumberFormatException ignored) {}

                if (retryCount >= MAX_RETRIES) {
                    // Move to dead-letter
                    WriteQueueManager.markDeadLetter(conn, item.get("mutation_id"),
                            "Exceeded max retries (" + MAX_RETRIES + ")");
                    System.err.println("PowerSyncEngine: Operation " + item.get("mutation_id") +
                            " moved to dead-letter after " + retryCount + " retries");

                    // Notify UI about dead-letter operation
                    notifyDeadLetter(item);
                } else {
                    processable.add(item);
                }
            }

            if (processable.isEmpty()) {
                consecutiveErrors.set(0);
                return;
            }

            JsonArray opsArray = new JsonArray();
            List<String> mutationIds = new ArrayList<>();

            for (Map<String, String> item : processable) {
                JsonObject op = new JsonObject();
                op.addProperty("mutation_id", item.get("mutation_id"));
                op.addProperty("op_type", item.get("op_type"));
                op.addProperty("sync_id", item.get("sync_id"));
                op.addProperty("table_name", item.get("table_name"));

                String payloadStr = item.get("payload");
                if (payloadStr != null && payloadStr.contains("delta")) {
                    try {
                        com.google.gson.JsonObject pObj = com.google.gson.JsonParser.parseString(payloadStr).getAsJsonObject();
                        if (pObj.has("delta")) {
                            op.addProperty("delta", pObj.get("delta").getAsInt());
                        }
                    } catch (Exception ignored) {}
                }

                opsArray.add(op);
                mutationIds.add(item.get("mutation_id"));
            }

            String deviceId = DeviceIdentity.getDeviceId();

            // Pre-emptive token freshness check
            TokenManager tokenMgr = TokenManager.getInstance();
            tokenMgr.ensureTokenFresh();

            // Call Supabase Service batch RPC with structured result
            SupabaseService.SyncResult result = SupabaseService.getInstance()
                    .processPowerSyncBatchRPC(deviceId, opsArray);

            switch (result) {
                case SUCCESS:
                    WriteQueueManager.markBatchCompleted(conn, mutationIds);
                    ReactiveQueryEngine.notifyTableChanged("sync_status");
                    consecutiveErrors.set(0);
                    nextDelay = BASE_POLL_MS;
                    break;

                case AUTH_EXPIRED:
                    // Don't increment operation retry counts — this is a session issue, not an op issue
                    System.out.println("PowerSyncEngine: Auth expired, requesting token refresh...");
                    boolean refreshed = tokenMgr.tryRefreshToken();
                    if (refreshed) {
                        // Retry the batch immediately with the new token
                        SupabaseService.SyncResult retryResult = SupabaseService.getInstance()
                                .processPowerSyncBatchRPC(deviceId, opsArray);
                        if (retryResult == SupabaseService.SyncResult.SUCCESS) {
                            WriteQueueManager.markBatchCompleted(conn, mutationIds);
                            ReactiveQueryEngine.notifyTableChanged("sync_status");
                            consecutiveErrors.set(0);
                            nextDelay = BASE_POLL_MS;
                        } else {
                            // Retry failed too — backoff but don't count as operation failure
                            int errors = consecutiveErrors.incrementAndGet();
                            nextDelay = RetryPolicy.calculateBackoffMs(errors);
                            System.err.println("PowerSyncEngine: Retry after refresh failed: " + retryResult);
                        }
                    } else {
                        // Circuit breaker open or refresh failed — back off significantly
                        int errors = consecutiveErrors.incrementAndGet();
                        nextDelay = Math.min(RetryPolicy.calculateBackoffMs(errors), MAX_POLL_MS);
                        System.err.println("PowerSyncEngine: Token refresh failed, backing off " + nextDelay + "ms");
                    }
                    break;

                case NOT_AUTHENTICATED:
                    // No tokens at all — don't retry, wait for user login
                    System.out.println("PowerSyncEngine: Not authenticated, pausing queue processing.");
                    nextDelay = MAX_POLL_MS;
                    break;

                case SERVER_ERROR:
                case NETWORK_ERROR:
                    // Retryable errors — increment operation retry counts and apply backoff
                    for (String mutId : mutationIds) {
                        WriteQueueManager.markOperationFailed(conn, mutId,
                                "Batch " + result.name() + " (retryable)");
                    }
                    int errors = consecutiveErrors.incrementAndGet();
                    nextDelay = RetryPolicy.calculateBackoffMs(errors);
                    System.err.println("PowerSyncEngine: " + result + ", backing off " + nextDelay + "ms");
                    break;

                case CLIENT_ERROR:
                    // Non-retryable (4xx) — increment retries which will eventually dead-letter
                    for (String mutId : mutationIds) {
                        WriteQueueManager.markOperationFailed(conn, mutId,
                                "Client error (non-retryable 4xx)");
                    }
                    consecutiveErrors.set(0); // Don't back off the engine — just the operations
                    nextDelay = BASE_POLL_MS;
                    break;
            }

        } catch (Exception e) {
            System.err.println("PowerSyncEngine processing error: " + e.getMessage());
            int errors = consecutiveErrors.incrementAndGet();
            nextDelay = RetryPolicy.calculateBackoffMs(errors);
        } finally {
            isProcessing.set(false);
            scheduleNext(nextDelay);
        }
    }

    /**
     * Notify the UI and show ConflictResolutionDialog when an operation is moved to dead-letter queue.
     */
    private void notifyDeadLetter(Map<String, String> item) {
        String tableName = item.getOrDefault("table_name", "unknown");
        String opType = item.getOrDefault("op_type", "unknown");
        String syncId = item.getOrDefault("sync_id", "");
        String payload = item.getOrDefault("payload", "");
        String mutationId = item.getOrDefault("mutation_id", "");

        javafx.application.Platform.runLater(() -> {
            try {
                com.meto.inventory.utils.ToastService.showWarning(
                        "Sync Conflict Alert",
                        "Operation on " + tableName + " failed after " + MAX_RETRIES + " retries. Opening conflict resolution..."
                );

                ConflictResolutionDialog.showConflictDialog(
                        tableName + " [" + syncId + "]",
                        opType,
                        "Server State (Current Cloud)",
                        "Local (" + payload + ")",
                        choice -> {
                            if (choice == ConflictResolutionDialog.ResolutionChoice.KEEP_LOCAL) {
                                try {
                                    Connection conn = com.meto.inventory.DataManager.getInstance().getDbHelper().getConnection();
                                    if (conn != null) {
                                        WriteQueueManager.retryDeadLetter(conn, mutationId);
                                        System.out.println("PowerSyncEngine: User chose KEEP_LOCAL for dead-letter mutation: " + mutationId);
                                        com.meto.inventory.utils.ToastService.showInfo("Sync Retrying", "Re-queued local change for synchronization.");
                                    }
                                } catch (Exception e) {
                                    e.printStackTrace();
                                }
                            }
                        }
                );
            } catch (Exception ignored) {}
        });
    }
}
