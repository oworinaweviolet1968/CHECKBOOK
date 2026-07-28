package com.meto.inventory.powersync;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;

import java.sql.Connection;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;

public class PowerSyncEngine {
    private static PowerSyncEngine instance;
    private final ScheduledExecutorService scheduler = Executors.newSingleThreadScheduledExecutor(r -> {
        Thread t = new Thread(r, "PowerSyncThread");
        t.setDaemon(true);
        return t;
    });
    private final AtomicBoolean isProcessing = new AtomicBoolean(false);

    private PowerSyncEngine() {}

    public static synchronized PowerSyncEngine getInstance() {
        if (instance == null) {
            instance = new PowerSyncEngine();
        }
        return instance;
    }

    public void start() {
        scheduler.scheduleWithFixedDelay(this::processWriteQueue, 2, 5, TimeUnit.SECONDS);
    }

    public void stop() {
        scheduler.shutdown();
    }

    public void processWriteQueue() {
        if (!isProcessing.compareAndSet(false, true)) {
            return;
        }

        try {
            Connection conn = com.meto.inventory.DataManager.getInstance().getDbHelper().getConnection();
            if (conn == null) return;

            // Bounded Queue Chunking: 50 items per batch
            List<Map<String, String>> batch = WriteQueueManager.fetchPendingBatch(conn, 50);
            if (batch.isEmpty()) {
                return;
            }

            JsonArray opsArray = new JsonArray();
            List<String> mutationIds = new ArrayList<>();

            for (Map<String, String> item : batch) {
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
            // Call Supabase Service batch RPC
            boolean success = com.meto.inventory.services.SupabaseService.getInstance()
                    .processPowerSyncBatchRPC(deviceId, opsArray);

            if (success) {
                WriteQueueManager.markBatchCompleted(conn, mutationIds);
                ReactiveQueryEngine.notifyTableChanged("sync_status");
            } else {
                // Apply backoff retry
                for (String mutId : mutationIds) {
                    WriteQueueManager.markOperationFailed(conn, mutId, "Batch upload failed");
                }
            }

        } catch (Exception e) {
            System.err.println("PowerSyncEngine processing error: " + e.getMessage());
        } finally {
            isProcessing.set(false);
        }
    }
}
