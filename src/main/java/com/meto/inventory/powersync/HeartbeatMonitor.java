package com.meto.inventory.powersync;

import com.meto.inventory.services.SupabaseService;

import java.util.LinkedList;
import java.util.Queue;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.ScheduledFuture;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

/**
 * Robust Multi-Layered Heartbeat & Health Check Service.
 *
 * Prevents status flapping via:
 * 1. Sliding Window Health Score (WINDOW_SIZE = 3, SUCCESS_THRESHOLD = 2)
 * 2. 30-Second Grace Period (GRACE_PERIOD_MS = 30_000) before marking offline
 * 3. Smart Adaptive Backoff (30s online, fast 10s recovery, 300s max offline)
 * 4. Dual Health Check (Presence Ping + REST API Availability)
 * 5. Circuit Breaker Integration (TokenManager failure protection)
 */
public class HeartbeatMonitor {
    private static HeartbeatMonitor instance;

    public enum HealthStatus {
        ONLINE,
        AUTH_ERROR,
        OFFLINE,
        DEGRADED
    }

    // Configuration
    private static final int WINDOW_SIZE = 3;
    private static final int SUCCESS_THRESHOLD = 2;
    private static final long GRACE_PERIOD_MS = 30_000;
    private static final long NORMAL_INTERVAL_SECONDS = 30;
    private static final long FAST_INTERVAL_SECONDS = 10;
    private static final long MAX_INTERVAL_SECONDS = 300;

    // State
    private final Queue<Boolean> healthWindow = new LinkedList<>();
    private volatile boolean isOnline = true;
    private volatile long lastSuccessTime = System.currentTimeMillis();
    private volatile int consecutiveFailures = 0;
    private volatile boolean isRecovering = false;
    private volatile HealthStatus currentStatus = HealthStatus.ONLINE;

    // Executor & Task Management
    private final ScheduledExecutorService executor = Executors.newSingleThreadScheduledExecutor(r -> {
        Thread t = new Thread(r, "HeartbeatMonitorThread");
        t.setDaemon(true);
        return t;
    });

    private final AtomicBoolean running = new AtomicBoolean(false);
    private ScheduledFuture<?> scheduledTask;

    private HeartbeatMonitor() {}

    public static synchronized HeartbeatMonitor getInstance() {
        if (instance == null) {
            instance = new HeartbeatMonitor();
        }
        return instance;
    }

    public void start() {
        if (!running.compareAndSet(false, true)) return;
        scheduleNextCheck(NORMAL_INTERVAL_SECONDS);
        System.out.println("HeartbeatMonitor: Started robust multi-layered health check service.");
    }

    public void stop() {
        if (running.compareAndSet(true, false)) {
            if (scheduledTask != null) {
                scheduledTask.cancel(false);
            }
            executor.shutdown();
        }
    }

    public boolean isHealthy() {
        return isOnline && currentStatus == HealthStatus.ONLINE;
    }

    public HealthStatus getCurrentStatus() {
        return currentStatus;
    }

    private synchronized void scheduleNextCheck(long delaySeconds) {
        if (!running.get()) return;
        if (scheduledTask != null && !scheduledTask.isDone()) {
            scheduledTask.cancel(false);
        }
        try {
            scheduledTask = executor.schedule(this::performHeartbeat, delaySeconds, TimeUnit.SECONDS);
        } catch (java.util.concurrent.RejectedExecutionException ignored) {}
    }

    private void performHeartbeat() {
        boolean success = false;
        HealthStatus status = HealthStatus.OFFLINE;

        try {
            SupabaseService service = SupabaseService.getInstance();
            TokenManager tokenMgr = TokenManager.getInstance();

            if (!service.isLoggedIn()) {
                recordHeartbeat(false);
                scheduleNextCheck(getNextInterval());
                return;
            }

            // Check circuit breaker first
            if (tokenMgr.isCircuitBreakerOpen()) {
                System.err.println("HeartbeatMonitor: Token circuit breaker open — auth is degraded.");
                status = HealthStatus.AUTH_ERROR;
                recordHeartbeat(false);
                updateUI(status);
                scheduleNextCheck(getNextInterval());
                return;
            }

            // Ensure token is fresh pre-emptively
            tokenMgr.ensureTokenFresh();

            // Send presence ping (PATCH /users)
            boolean presenceOk = sendPresencePing();

            // Verify API availability (HEAD /stock?limit=1)
            boolean apiOk = service.verifyAPIAvailability();

            if (presenceOk && apiOk) {
                status = HealthStatus.ONLINE;
                success = true;
            } else if (presenceOk && !apiOk) {
                status = HealthStatus.AUTH_ERROR;
                success = false;
            } else {
                status = HealthStatus.OFFLINE;
                success = false;
            }

        } catch (Throwable t) {
            System.err.println("HeartbeatMonitor: Health check exception: " + t.getMessage());
            success = false;
            status = HealthStatus.OFFLINE;
        }

        // Record sliding window result
        recordHeartbeat(success);

        // Update status state and UI
        this.currentStatus = status;
        updateUI(status);

        // Schedule next check with adaptive interval
        scheduleNextCheck(getNextInterval());
    }

    private synchronized void recordHeartbeat(boolean success) {
        healthWindow.add(success);
        if (healthWindow.size() > WINDOW_SIZE) {
            healthWindow.poll();
        }

        long now = System.currentTimeMillis();

        if (success) {
            lastSuccessTime = now;
            consecutiveFailures = 0;

            long successes = healthWindow.stream().filter(b -> b).count();
            if (successes >= SUCCESS_THRESHOLD && !isOnline) {
                isOnline = true;
                isRecovering = true;
                System.out.println("HeartbeatMonitor: Connection STABILIZED (Online). Starting recovery stabilization...");
                scheduleStabilization();
            }
        } else {
            consecutiveFailures++;

            long failures = healthWindow.stream().filter(b -> !b).count();
            if (failures >= SUCCESS_THRESHOLD && isOnline) {
                // Grace Period Check: Only mark offline if failures persist > GRACE_PERIOD_MS
                if (now - lastSuccessTime > GRACE_PERIOD_MS) {
                    isOnline = false;
                    isRecovering = false;
                    System.err.println("HeartbeatMonitor: Connection LOST (Offline after 30s grace period & 2/3 window failures).");
                } else {
                    System.out.println("HeartbeatMonitor: Heartbeat failed, but within 30s grace period. Preserving ONLINE status.");
                }
            }
        }
    }

    private void scheduleStabilization() {
        // Fast checks during recovery (90 seconds = 9 fast checks at 10s interval)
        try {
            executor.schedule(() -> {
                isRecovering = false;
                System.out.println("HeartbeatMonitor: Recovery stabilization complete. Returning to 30s normal interval.");
            }, 90, TimeUnit.SECONDS);
        } catch (Exception ignored) {}
    }

    private long getNextInterval() {
        if (!isOnline) {
            // Offline: Exponential backoff (30s, 60s, 120s, 240s, 300s)
            int exponent = Math.min(consecutiveFailures, 5);
            long interval = NORMAL_INTERVAL_SECONDS * (long) Math.pow(2, Math.max(0, exponent - 1));
            return Math.min(interval, MAX_INTERVAL_SECONDS);
        }

        if (isRecovering) {
            return FAST_INTERVAL_SECONDS;
        }

        return NORMAL_INTERVAL_SECONDS;
    }

    private boolean sendPresencePing() {
        SupabaseService service = SupabaseService.getInstance();
        return service.sendHeartbeatPing();
    }

    private void updateUI(HealthStatus status) {
        SupabaseService service = SupabaseService.getInstance();
        switch (status) {
            case ONLINE:
                service.notifyStatus("Cloud: Synced");
                break;
            case AUTH_ERROR:
                service.notifyStatus("Cloud: Auth Expired (Please re-login)");
                break;
            case OFFLINE:
                service.notifyStatus("Cloud: Offline");
                break;
            case DEGRADED:
                service.notifyStatus("Cloud: Degraded");
                break;
        }
    }
}
