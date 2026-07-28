package com.meto.inventory.powersync;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

public class WriteQueueManager {
    public static void initializeQueueTable(Connection conn) throws SQLException {
        String sql = "CREATE TABLE IF NOT EXISTS sync_write_queue (" +
                "seq_id INTEGER PRIMARY KEY AUTOINCREMENT," +
                "mutation_id TEXT UNIQUE NOT NULL," +
                "device_id TEXT NOT NULL," +
                "user_id TEXT NOT NULL," +
                "table_name TEXT NOT NULL," +
                "op_type TEXT NOT NULL," + // 'DELTA_STOCK', 'INSERT', 'UPDATE', 'DELETE'
                "sync_id TEXT NOT NULL," +
                "parent_sync_id TEXT," +
                "payload TEXT NOT NULL," + // JSON payload
                "status TEXT DEFAULT 'PENDING'," + // 'PENDING', 'PROCESSING', 'FAILED'
                "retry_count INTEGER DEFAULT 0," +
                "last_error TEXT," +
                "created_at TEXT NOT NULL" +
                ");";
        try (PreparedStatement stmt = conn.prepareStatement(sql)) {
            stmt.executeUpdate();
        }

        // Local Database Indexing guideline: Add index on (status, seq_id)
        String indexSql = "CREATE INDEX IF NOT EXISTS idx_queue_status_seq ON sync_write_queue(status, seq_id);";
        try (PreparedStatement stmt = conn.prepareStatement(indexSql)) {
            stmt.executeUpdate();
        }
    }

    public static String enqueueOperation(Connection conn, String userId, String tableName, String opType, String syncId, String parentSyncId, String payload) throws SQLException {
        String mutationId = UUID.randomUUID().toString();
        String deviceId = DeviceIdentity.getDeviceId();
        String createdAt = ClockSync.getAdjustedTimestampIso();

        String sql = "INSERT INTO sync_write_queue " +
                "(mutation_id, device_id, user_id, table_name, op_type, sync_id, parent_sync_id, payload, status, created_at) " +
                "VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'PENDING', ?)";

        try (PreparedStatement stmt = conn.prepareStatement(sql)) {
            stmt.setString(1, mutationId);
            stmt.setString(2, deviceId);
            stmt.setString(3, userId);
            stmt.setString(4, tableName);
            stmt.setString(5, opType);
            stmt.setString(6, syncId);
            stmt.setString(7, parentSyncId);
            stmt.setString(8, payload);
            stmt.setString(9, createdAt);
            stmt.executeUpdate();
        }

        return mutationId;
    }

    public static List<Map<String, String>> fetchPendingBatch(Connection conn, int batchSize) throws SQLException {
        List<Map<String, String>> batch = new ArrayList<>();
        String sql = "SELECT seq_id, mutation_id, device_id, user_id, table_name, op_type, sync_id, parent_sync_id, payload, retry_count " +
                "FROM sync_write_queue " +
                "WHERE status = 'PENDING' " +
                "ORDER BY seq_id ASC " +
                "LIMIT ?";

        try (PreparedStatement stmt = conn.prepareStatement(sql)) {
            stmt.setInt(1, batchSize);
            try (ResultSet rs = stmt.executeQuery()) {
                while (rs.next()) {
                    Map<String, String> row = new HashMap<>();
                    row.put("seq_id", String.valueOf(rs.getInt("seq_id")));
                    row.put("mutation_id", rs.getString("mutation_id"));
                    row.put("device_id", rs.getString("device_id"));
                    row.put("user_id", rs.getString("user_id"));
                    row.put("table_name", rs.getString("table_name"));
                    row.put("op_type", rs.getString("op_type"));
                    row.put("sync_id", rs.getString("sync_id"));
                    row.put("parent_sync_id", rs.getString("parent_sync_id"));
                    row.put("payload", rs.getString("payload"));
                    row.put("retry_count", String.valueOf(rs.getInt("retry_count")));
                    batch.add(row);
                }
            }
        }
        return batch;
    }

    public static void markBatchCompleted(Connection conn, List<String> mutationIds) throws SQLException {
        if (mutationIds.isEmpty()) return;
        StringBuilder sql = new StringBuilder("DELETE FROM sync_write_queue WHERE mutation_id IN (");
        for (int i = 0; i < mutationIds.size(); i++) {
            sql.append(i == 0 ? "?" : ", ?");
        }
        sql.append(")");

        try (PreparedStatement stmt = conn.prepareStatement(sql.toString())) {
            for (int i = 0; i < mutationIds.size(); i++) {
                stmt.setString(i + 1, mutationIds.get(i));
            }
            stmt.executeUpdate();
        }
    }

    public static void markOperationFailed(Connection conn, String mutationId, String error) throws SQLException {
        String sql = "UPDATE sync_write_queue " +
                "SET retry_count = retry_count + 1, last_error = ?, status = 'PENDING' " +
                "WHERE mutation_id = ?";
        try (PreparedStatement stmt = conn.prepareStatement(sql)) {
            stmt.setString(1, error);
            stmt.setString(2, mutationId);
            stmt.executeUpdate();
        }
    }
}
