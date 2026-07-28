package com.meto.inventory.powersync;

import com.google.gson.JsonObject;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.SQLException;

public class DeltaStockManager {

    public static boolean applyLocalStockDelta(Connection conn, String userId, String syncId, int delta) throws SQLException {
        boolean autoCommit = conn.getAutoCommit();
        try {
            conn.setAutoCommit(false);

            // 1. Local SQLite Delta Update (Commutative Local Application)
            String sqlUpdate = "UPDATE stock SET quantity = quantity + ?, updated_at = ? WHERE sync_id = ?";
            try (PreparedStatement stmt = conn.prepareStatement(sqlUpdate)) {
                stmt.setInt(1, delta);
                stmt.setString(2, ClockSync.getAdjustedTimestampIso());
                stmt.setString(3, syncId);
                int rows = stmt.executeUpdate();
                if (rows == 0) {
                    conn.rollback();
                    return false;
                }
            }

            // 2. Queue Payload for Remote Supabase RPC Delta
            JsonObject payload = new JsonObject();
            payload.addProperty("sync_id", syncId);
            payload.addProperty("delta", delta);

            WriteQueueManager.enqueueOperation(
                    conn,
                    userId,
                    "stock",
                    "DELTA_STOCK",
                    syncId,
                    null,
                    payload.toString()
            );

            conn.commit();

            // 3. Trigger Local Reactive UI Invalidation
            ReactiveQueryEngine.notifyTableChanged("stock");
            return true;
        } catch (SQLException e) {
            conn.rollback();
            throw e;
        } finally {
            conn.setAutoCommit(autoCommit);
        }
    }
}
