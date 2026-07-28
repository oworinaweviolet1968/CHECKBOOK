package com.meto.inventory;

import com.meto.inventory.models.HistoryItem;
import com.meto.inventory.models.StockItem;
import javafx.collections.FXCollections;
import javafx.collections.ObservableList;
import java.sql.*;
import java.time.LocalDate;
import java.util.HashMap;
import java.util.Map;
import java.util.List;
import java.util.ArrayList;
import java.util.Set;
import java.util.HashSet;

public class DatabaseHelper {

    private String dbUrl = "jdbc:sqlite:" + resolvePath("inventory.db"); // Default
    private String currentDbName = resolvePath("inventory.db");
    private Connection connection;

    private static String resolvePath(String fileName) {
        String userHome = System.getProperty("user.home");
        String appData = System.getenv("APPDATA");

        // Prefer APPDATA on Windows, user.home otherwise
        String rootDir = (appData != null) ? appData : userHome;

        java.io.File dir = new java.io.File(rootDir, "METO_IMS_DATA");
        if (!dir.exists()) {
            boolean created = dir.mkdirs();
            System.out.println("DEBUG: Created data dir: " + dir.getAbsolutePath() + " -> " + created);
        } else {
            System.out.println("DEBUG: Data dir exists: " + dir.getAbsolutePath());
        }
        return new java.io.File(dir, fileName).getAbsolutePath();
    }

    public static String getAppDir() {
        // Re-resolve to get the same directory logic
        String userHome = System.getProperty("user.home");
        String appData = System.getenv("APPDATA");
        String rootDir = (appData != null) ? appData : userHome;
        return new java.io.File(rootDir, "METO_IMS_DATA").getAbsolutePath();
    }

    public void initializeDatabase() {
        try {
            System.out.println("DEBUG: Connecting to DB URL: " + dbUrl);
            connection = DriverManager.getConnection(dbUrl);
            try (Statement pragmaStmt = connection.createStatement()) {
                pragmaStmt.execute("PRAGMA busy_timeout = 10000;");
                pragmaStmt.execute("PRAGMA journal_mode = WAL;");
            }
            createTables();
        } catch (SQLException e) {
            System.err.println("CRITICAL: Failed to connect to DB at " + dbUrl);
            e.printStackTrace();
        }
    }

    public void setDatabaseName(String localFileName) {
        try {
            if (connection != null && !connection.isClosed()) {
                connection.close();
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }

        String fullPath = resolvePath(localFileName);
        // FORCE FORWARD SLASHES for JDBC URL stability on Windows
        String validUrlPath = fullPath.replace(java.io.File.separatorChar, '/');

        this.currentDbName = fullPath;
        this.dbUrl = "jdbc:sqlite:" + validUrlPath;

        System.out.println("DEBUG: Setting DB Name. Path=" + fullPath + ", URL=" + dbUrl);
        initializeDatabase();
    }

    public String getCurrentDbName() {
        return currentDbName;
    }

    public void connect() {
        initializeDatabase();
    }

    private void createTables() {
        String createStockTable = """
                    CREATE TABLE IF NOT EXISTS stock (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        supplier TEXT NOT NULL,
                        item TEXT NOT NULL,
                        quantity TEXT NOT NULL,
                        unit TEXT NOT NULL,
                        price REAL NOT NULL,
                        available_pieces REAL DEFAULT 0,
                        date TEXT NOT NULL,
                        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
                    )
                """;

        String createSalesTable = """
                    CREATE TABLE IF NOT EXISTS sales (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        customer TEXT NOT NULL,
                        item TEXT NOT NULL,
                        quantity TEXT NOT NULL,
                        unit TEXT NOT NULL,
                        price REAL NOT NULL,
                        cost_price REAL NOT NULL,
                        base_quantity REAL NOT NULL,
                        amount REAL NOT NULL,
                        type TEXT NOT NULL,
                        date TEXT NOT NULL,
                        is_debt INTEGER DEFAULT 0,
                        is_paid INTEGER DEFAULT 0,
                        paid_amount REAL DEFAULT 0,
                        is_edited INTEGER DEFAULT 0,
                        device_source TEXT DEFAULT 'Desktop',
                        created_at DATETIME DEFAULT CURRENT_TIMESTAMP
                    )
                """;

        String createSummaryTable = """
                    CREATE TABLE IF NOT EXISTS yearly_summaries (
                        year INTEGER PRIMARY KEY,
                        total_profit REAL,
                        total_sales REAL,
                        closed_at DATETIME DEFAULT CURRENT_TIMESTAMP
                    )
                """;

        String createDebtPaymentsTable = """
                    CREATE TABLE IF NOT EXISTS debt_payments (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        sale_id INTEGER NOT NULL,
                        amount_paid REAL NOT NULL,
                        payment_date TEXT NOT NULL,
                        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
                        FOREIGN KEY (sale_id) REFERENCES sales(id)
                    )
                """;

        String createSettingsTable = """
                    CREATE TABLE IF NOT EXISTS settings (
                        key TEXT PRIMARY KEY,
                        value TEXT
                    )
                """;
        try (Statement stmt = connection.createStatement()) {
            stmt.execute(createStockTable);
            stmt.execute(createSalesTable);
            stmt.execute(createSummaryTable);
            stmt.execute(createSettingsTable);
            stmt.execute(createDebtPaymentsTable);
            stmt.execute(
                    "CREATE TABLE IF NOT EXISTS deleted_stock (id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT, quantity TEXT, deleted_at DATETIME DEFAULT CURRENT_TIMESTAMP)");
            stmt.execute(
                    "CREATE TABLE IF NOT EXISTS deleted_history (id INTEGER PRIMARY KEY AUTOINCREMENT, customer TEXT, item TEXT, amount TEXT, date TEXT, deleted_at DATETIME DEFAULT CURRENT_TIMESTAMP)");
            stmt.execute(
                    "CREATE TABLE IF NOT EXISTS notifications (id INTEGER PRIMARY KEY AUTOINCREMENT, message TEXT, source TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP, is_read INTEGER DEFAULT 0)");
            stmt.execute(
                    "CREATE TABLE IF NOT EXISTS stock_movement_log (id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT, quantity TEXT, change_pieces REAL NOT NULL, previous_pieces REAL NOT NULL, new_pieces REAL NOT NULL, change_reason TEXT NOT NULL, device_source TEXT DEFAULT 'Desktop', created_at DATETIME DEFAULT CURRENT_TIMESTAMP)");

            // AUTOMATIC MIGRATION: Check for missing columns in legacy DBs
            ensureSchema(stmt);

            // POWERSYNC INITIALIZATION: Queue table & index
            try {
                com.meto.inventory.powersync.WriteQueueManager.initializeQueueTable(stmt.getConnection());
                com.meto.inventory.powersync.PowerSyncEngine.getInstance().start();
            } catch (Exception ex) {
                System.err.println("DatabaseHelper: Failed to init PowerSync Queue: " + ex.getMessage());
            }

        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

    private void ensureSchema(Statement stmt) throws SQLException {
        // --- ADD SYNC_ID TO ALL TABLES ---
        String[] tables = { "stock", "sales", "deleted_history", "debt_payments", "notifications", "deleted_stock" };
        for (String table : tables) {
            try {
                ResultSet rs = stmt.executeQuery("PRAGMA table_info(" + table + ")");
                boolean hasSyncId = false;
                while (rs.next()) {
                    if ("sync_id".equalsIgnoreCase(rs.getString("name"))) {
                        hasSyncId = true;
                        break;
                    }
                }
                if (!hasSyncId) {
                    stmt.execute("ALTER TABLE " + table + " ADD COLUMN sync_id TEXT");
                    // Populate existing rows with a basic UUID-like string
                    stmt.execute("UPDATE " + table
                            + " SET sync_id = lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))),2) || '-a' || substr(lower(hex(randomblob(2))),2) || '-' || lower(hex(randomblob(6))) WHERE sync_id IS NULL");
                }
            } catch (SQLException e) {
                System.err.println("Schema check failed for sync_id on " + table + ": " + e.getMessage());
            }
        }

        // Normalize any existing 32-character hex sync_ids to standard 36-character dashed UUIDs
        for (String table : tables) {
            try {
                stmt.execute("UPDATE " + table + " SET sync_id = substr(sync_id, 1, 8) || '-' || substr(sync_id, 9, 4) || '-' || substr(sync_id, 13, 4) || '-' || substr(sync_id, 17, 4) || '-' || substr(sync_id, 21, 12) WHERE length(sync_id) = 32");
            } catch (SQLException e) {
                System.err.println("Failed to normalize sync_id on table " + table + ": " + e.getMessage());
                try {
                    stmt.execute("DELETE FROM " + table + " WHERE length(sync_id) = 32 AND (substr(sync_id, 1, 8) || '-' || substr(sync_id, 9, 4) || '-' || substr(sync_id, 13, 4) || '-' || substr(sync_id, 17, 4) || '-' || substr(sync_id, 21, 12)) IN (SELECT sync_id FROM " + table + " WHERE length(sync_id) = 36)");
                    stmt.execute("UPDATE " + table + " SET sync_id = substr(sync_id, 1, 8) || '-' || substr(sync_id, 9, 4) || '-' || substr(sync_id, 13, 4) || '-' || substr(sync_id, 17, 4) || '-' || substr(sync_id, 21, 12) WHERE length(sync_id) = 32");
                } catch (SQLException innerErr) {
                    System.err.println("Failed to resolve unique constraint conflict on table " + table + ": " + innerErr.getMessage());
                }
            }
        }

        // 1. Check STOCK table
        try {
            ResultSet rs = stmt.executeQuery("PRAGMA table_info(stock)");
            boolean hasAvailablePieces = false;
            boolean hasSource = false;
            boolean hasIsEdited = false;
            boolean hasCostPrice = false;
            boolean hasBaseQuantity = false;
            while (rs.next()) {
                String col = rs.getString("name");
                if ("available_pieces".equalsIgnoreCase(col))
                    hasAvailablePieces = true;
                if ("device_source".equalsIgnoreCase(col))
                    hasSource = true;
                if ("is_edited".equalsIgnoreCase(col))
                    hasIsEdited = true;
                if ("cost_price".equalsIgnoreCase(col))
                    hasCostPrice = true;
                if ("base_quantity".equalsIgnoreCase(col))
                    hasBaseQuantity = true;
            }
            if (!hasAvailablePieces)
                stmt.execute("ALTER TABLE stock ADD COLUMN available_pieces REAL DEFAULT 0");
            if (!hasSource)
                stmt.execute("ALTER TABLE stock ADD COLUMN device_source TEXT DEFAULT 'Desktop'");
            if (!hasIsEdited) {
                stmt.execute("ALTER TABLE stock ADD COLUMN is_edited INTEGER DEFAULT 0");
                stmt.execute("UPDATE stock SET is_edited = 1");
            }
            if (!hasCostPrice)
                stmt.execute("ALTER TABLE stock ADD COLUMN cost_price REAL DEFAULT 0.0");
            if (!hasBaseQuantity)
                stmt.execute("ALTER TABLE stock ADD COLUMN base_quantity REAL DEFAULT 1.0");
        } catch (SQLException e) {
            System.err.println("Schema check failed for stock: " + e.getMessage());
        }

        // 2. Check SALES table
        try {
            ResultSet rs = stmt.executeQuery("PRAGMA table_info(sales)");
            boolean hasCostPrice = false;
            boolean hasBaseQty = false;
            boolean hasSource = false;
            boolean hasIsDebt = false;
            boolean hasIsPaid = false;
            boolean hasPaidAmount = false;
            boolean hasIsEdited = false;
            boolean hasReceiptId = false;

            while (rs.next()) {
                String col = rs.getString("name");
                if ("cost_price".equalsIgnoreCase(col))
                    hasCostPrice = true;
                if ("base_quantity".equalsIgnoreCase(col))
                    hasBaseQty = true;
                if ("device_source".equalsIgnoreCase(col))
                    hasSource = true;
                if ("is_debt".equalsIgnoreCase(col))
                    hasIsDebt = true;
                if ("is_paid".equalsIgnoreCase(col))
                    hasIsPaid = true;
                if ("paid_amount".equalsIgnoreCase(col))
                    hasPaidAmount = true;
                if ("is_edited".equalsIgnoreCase(col))
                    hasIsEdited = true;
                if ("receipt_id".equalsIgnoreCase(col))
                    hasReceiptId = true;
            }

            if (!hasCostPrice)
                stmt.execute("ALTER TABLE sales ADD COLUMN cost_price REAL DEFAULT 0");
            if (!hasBaseQty)
                stmt.execute("ALTER TABLE sales ADD COLUMN base_quantity REAL DEFAULT 0");
            if (!hasSource)
                stmt.execute("ALTER TABLE sales ADD COLUMN device_source TEXT DEFAULT 'Desktop'");
            if (!hasIsDebt)
                stmt.execute("ALTER TABLE sales ADD COLUMN is_debt INTEGER DEFAULT 0");
            if (!hasIsPaid)
                stmt.execute("ALTER TABLE sales ADD COLUMN is_paid INTEGER DEFAULT 0");
            if (!hasPaidAmount)
                stmt.execute("ALTER TABLE sales ADD COLUMN paid_amount REAL DEFAULT 0");
            if (!hasIsEdited) {
                stmt.execute("ALTER TABLE sales ADD COLUMN is_edited INTEGER DEFAULT 0");
                stmt.execute("UPDATE sales SET is_edited = 1");
            }
            if (!hasReceiptId)
                stmt.execute("ALTER TABLE sales ADD COLUMN receipt_id TEXT");
        } catch (SQLException e) {
            System.err.println("Schema check failed for sales: " + e.getMessage());
        }

        // 3. Check DELETED_HISTORY table
        try {
            ResultSet rs = stmt.executeQuery("PRAGMA table_info(deleted_history)");
            Set<String> existingCols = new HashSet<>();
            while (rs.next()) {
                existingCols.add(rs.getString("name").toLowerCase());
            }
            if (!existingCols.contains("quantity")) stmt.execute("ALTER TABLE deleted_history ADD COLUMN quantity TEXT");
            if (!existingCols.contains("unit")) stmt.execute("ALTER TABLE deleted_history ADD COLUMN unit TEXT");
            if (!existingCols.contains("price")) stmt.execute("ALTER TABLE deleted_history ADD COLUMN price REAL");
            if (!existingCols.contains("cost_price")) stmt.execute("ALTER TABLE deleted_history ADD COLUMN cost_price REAL");
            if (!existingCols.contains("base_quantity")) stmt.execute("ALTER TABLE deleted_history ADD COLUMN base_quantity REAL");
            if (!existingCols.contains("type")) stmt.execute("ALTER TABLE deleted_history ADD COLUMN type TEXT");
            if (!existingCols.contains("date")) stmt.execute("ALTER TABLE deleted_history ADD COLUMN date TEXT");
            if (!existingCols.contains("is_debt")) stmt.execute("ALTER TABLE deleted_history ADD COLUMN is_debt INTEGER DEFAULT 0");
            if (!existingCols.contains("is_paid")) stmt.execute("ALTER TABLE deleted_history ADD COLUMN is_paid INTEGER DEFAULT 0");
            if (!existingCols.contains("paid_amount")) stmt.execute("ALTER TABLE deleted_history ADD COLUMN paid_amount REAL DEFAULT 0");
            if (!existingCols.contains("is_edited")) stmt.execute("ALTER TABLE deleted_history ADD COLUMN is_edited INTEGER DEFAULT 0");
            if (!existingCols.contains("device_source")) stmt.execute("ALTER TABLE deleted_history ADD COLUMN device_source TEXT DEFAULT 'Desktop'");
            if (!existingCols.contains("sync_id")) stmt.execute("ALTER TABLE deleted_history ADD COLUMN sync_id TEXT");
        } catch (SQLException e) {
            System.err.println("Schema check failed for deleted_history: " + e.getMessage());
        }

        // --- ENFORCE UNIQUE INDEXES FOR DELTA SYNC ---
        try {
            // Clean up existing duplicates before applying unique constraints
            stmt.execute("DELETE FROM stock WHERE id NOT IN (SELECT MAX(id) FROM stock GROUP BY item, quantity)");
            stmt.execute(
                    "DELETE FROM sales WHERE id NOT IN (SELECT MAX(id) FROM sales GROUP BY created_at, customer, item, amount, date)");

            // Create Unique Indexes
            stmt.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_stock_item_qty ON stock(item, quantity)");
            stmt.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_stock_sync_id ON stock(sync_id)");
            stmt.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_sync_id ON sales(sync_id)");

            // One-time backfill of is_edited flag for unsynced local rows
            boolean backfilled = false;
            try (ResultSet rs = stmt.executeQuery("SELECT 1 FROM settings WHERE key = 'has_backfilled_is_edited_v1'")) {
                if (rs.next()) {
                    backfilled = true;
                }
            } catch (SQLException ignore) {}
            if (!backfilled) {
                stmt.execute("UPDATE sales SET is_edited = 1 WHERE is_edited = 0");
                stmt.execute("UPDATE stock SET is_edited = 1 WHERE is_edited = 0");
                stmt.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('has_backfilled_is_edited_v1', '1')");
                System.out.println("DEBUG: Backfilled local changes with is_edited = 1 for sync.");
            }

            // One-time migration to re-sync all sales to restore any missing records
            boolean reSynced = false;
            try (ResultSet rs = stmt.executeQuery("SELECT 1 FROM settings WHERE key = 'has_re_synced_missing_sales_v3'")) {
                if (rs.next()) {
                    reSynced = true;
                }
            } catch (SQLException ignore) {}
            if (!reSynced) {
                try {
                    stmt.execute("UPDATE sales SET is_edited = 1");
                    stmt.execute("DELETE FROM deleted_history"); // Clear all stale deletion logs!
                    stmt.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('last_backup_timestamp', '0')");
                    stmt.execute("INSERT OR REPLACE INTO settings (key, value) VALUES ('has_re_synced_missing_sales_v3', '1')");
                    System.out.println("RE-SYNC MIGRATION (Desktop): Marked all sales as edited, cleared deleted_history, and reset sync cursor.");
                } catch (SQLException e) {
                    System.err.println("Failed to run re-sync migration on Desktop: " + e.getMessage());
                }
            }

            stmt.execute("UPDATE sales SET receipt_id = NULL, is_edited = 1 WHERE receipt_id = '' OR receipt_id = 'null'");

            // Cleanup/reconcile legacy sales that lack a receipt_id but were created around the same time for the same customer
            try {
                String selectSql = "SELECT id, customer, date, created_at FROM sales WHERE (receipt_id IS NULL OR receipt_id = '') AND customer != 'Walk-in Customer' ORDER BY customer, created_at";
                List<LegacySale> legacySales = new ArrayList<>();
                try (ResultSet rs = stmt.executeQuery(selectSql)) {
                    while (rs.next()) {
                        legacySales.add(new LegacySale(
                            rs.getInt("id"),
                            rs.getString("customer"),
                            rs.getString("date"),
                            rs.getString("created_at")
                        ));
                    }
                }
                
                int i = 0;
                while (i < legacySales.size()) {
                    LegacySale base = legacySales.get(i);
                    List<Integer> idsToGroup = new ArrayList<>();
                    idsToGroup.add(base.id);
                    
                    int j = i + 1;
                    while (j < legacySales.size()) {
                        LegacySale next = legacySales.get(j);
                        if (base.customer.equals(next.customer)) {
                            long diffSeconds = getSecondsDifference(base.createdAt, next.createdAt);
                            if (diffSeconds >= 0 && diffSeconds <= 30) {
                                idsToGroup.add(next.id);
                                j++;
                            } else {
                                break;
                            }
                        } else {
                            break;
                        }
                    }
                    
                    if (idsToGroup.size() > 1) {
                        String newReceiptId = java.util.UUID.randomUUID().toString();
                        StringBuilder updateSqlBuilder = new StringBuilder("UPDATE sales SET receipt_id = ?, is_edited = 1 WHERE id IN (");
                        for (int k = 0; k < idsToGroup.size(); k++) {
                            updateSqlBuilder.append(idsToGroup.get(k));
                            if (k < idsToGroup.size() - 1) {
                                updateSqlBuilder.append(",");
                            }
                        }
                        updateSqlBuilder.append(")");
                        try (PreparedStatement updateStmt = connection.prepareStatement(updateSqlBuilder.toString())) {
                            updateStmt.setString(1, newReceiptId);
                            updateStmt.executeUpdate();
                            System.out.println("DEBUG: Consolidated legacy sales: " + idsToGroup + " under receipt_id: " + newReceiptId);
                        }
                    }
                    i = j;
                }
            } catch (SQLException e) {
                System.err.println("Failed to clean up legacy sales: " + e.getMessage());
            }

            // Deduplicate zombie duplicate sales entries (e.g. from checkout double-taps)
            try {
                String dupQuery = "SELECT id, sync_id, customer FROM sales WHERE sync_id IS NOT NULL AND id NOT IN (SELECT MIN(id) FROM sales GROUP BY sync_id)";
                try (PreparedStatement dupStmt = connection.prepareStatement(dupQuery);
                     ResultSet dupRs = dupStmt.executeQuery()) {
                    while (dupRs.next()) {
                        int dupId = dupRs.getInt("id");
                        String dupSyncId = dupRs.getString("sync_id");
                        String dupCustomer = dupRs.getString("customer");

                        try (PreparedStatement deleteStmt = connection.prepareStatement("DELETE FROM sales WHERE id = ?")) {
                            deleteStmt.setInt(1, dupId);
                            deleteStmt.executeUpdate();
                            System.out.println("DEDUPLICATE CLEANUP (Desktop): Deleted duplicate sale ID: " + dupId + " (sync_id: " + dupSyncId + ") for customer: " + dupCustomer);
                        }
                    }
                }
            } catch (SQLException e) {
                System.err.println("Failed to deduplicate sales: " + e.getMessage());
            }
        } catch (SQLException e) {
            System.err.println("Unique index creation failed: " + e.getMessage());
        }
    }

    // --- LOGIC ENGINE: CONVERSIONS ---

    public double convertToBaseUnit(String unit) {
        if (unit == null)
            return 1.0;
        String cleanUnit = unit.toLowerCase().trim();

        // SPECIFIC FIRST
        if (cleanUnit.contains("half doz"))
            return 6.0;

        // GENERAL SECOND
        if (cleanUnit.contains("box*10"))
            return 10.0;
        if (cleanUnit.contains("box*12") || cleanUnit.contains("dozen") || cleanUnit.contains("doz"))
            return 12.0;
        if (cleanUnit.contains("box*20") || cleanUnit.equals("box"))
            return 20.0;
        if (cleanUnit.contains("box*24") || cleanUnit.contains("carton"))
            return 24.0;
        if (cleanUnit.contains("box*72"))
            return 72.0;
        if (cleanUnit.contains("crate"))
            return 25.0;
        if (cleanUnit.contains("box"))
            return 20.0;

        return 1.0;
    }

    private double calculateTotalBaseStock(String unitCount, String size) {
        double count = extractNumericValue(unitCount);
        // if (size.toLowerCase().contains("kg")) {
        // double kgPerSack = extractNumericValue(size);
        // return count * (kgPerSack > 0 ? kgPerSack : 1);
        // }
        return count * getUnitMultiplier(unitCount, size, unitCount);
    }

    private String formatStockForDisplay(double totalBase, String size, String bulkUnit) {
        String sizeLower = size.toLowerCase().replaceAll("\\s+", "");

        // --- WEIGHT-BASED (Sacks / kg) ---
        if (sizeLower.contains("kg")) {
            double kgPerSack = extractNumericValue(size);
            if (kgPerSack >= 10.0) {
                int sacks = (int) (totalBase / kgPerSack);
                double remainingKg = totalBase % kgPerSack;
                if (sacks > 0 && remainingKg > 0.01)
                    return String.format("%d Sacks / %.1f kg", sacks, remainingKg);
                if (sacks > 0)
                    return String.format("%d Sacks", sacks);
                return String.format("%.1f kg", remainingKg);
            }
        }

        // --- PIECE-BASED: Highest unit → Doz → pcs ---
        double multiplier = getUnitMultiplier(bulkUnit, size, bulkUnit);

        // If multiplier is 1, just show pcs
        if (multiplier <= 1.0) {
            return String.format("%,.0f pcs", totalBase);
        }

        // Friendly name for the highest unit
        String friendlyName;
        if (multiplier == 6.0)
            friendlyName = "Half Doz";
        else if (multiplier == 12.0)
            friendlyName = "Doz";
        else if (sizeLower.contains("crate"))
            friendlyName = "Crs";
        else if (sizeLower.contains("carton"))
            friendlyName = "Cts";
        else if (sizeLower.contains("pack"))
            friendlyName = "Pks";
        else if (sizeLower.contains("bundle"))
            friendlyName = "Bndls";
        else
            friendlyName = "Bx";

        int mainCount = (int) (totalBase / multiplier);
        int leftover = (int) (Math.round(totalBase % multiplier));

        StringBuilder display = new StringBuilder();

        if (mainCount > 0) {
            display.append(mainCount).append(" ").append(friendlyName);
        }

        // Level 2: Doz (only if highest unit > 12)
        if (multiplier > 12.0 && leftover >= 12) {
            int dozens = leftover / 12;
            leftover = leftover % 12;
            if (display.length() > 0)
                display.append(" / ");
            display.append(dozens).append(" Doz");
        }

        // Level 3: Remaining pcs
        if (leftover > 0) {
            if (display.length() > 0)
                display.append(" / ");
            display.append(leftover).append(" pcs");
        }

        return display.length() > 0 ? display.toString() : "0 pcs";
    }

    // --- STOCK OPERATIONS ---

    public boolean itemExists(String itemName, String size) {
        String sql = "SELECT COUNT(*) FROM stock WHERE item = ? AND quantity = ?";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, itemName);
            pstmt.setString(2, size);
            ResultSet rs = pstmt.executeQuery();
            if (rs.next())
                return rs.getInt(1) > 0;
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return false;
    }

    public boolean mergeStock(String itemName, String size, String newUnit, double newPrice, String supplier,
            boolean forceSave) {
        String selectSql = "SELECT id, available_pieces, price, unit FROM stock WHERE item = ? AND quantity = ?";
        try (PreparedStatement selectStmt = connection.prepareStatement(selectSql)) {
            selectStmt.setString(1, itemName);
            selectStmt.setString(2, size);
            ResultSet rs = selectStmt.executeQuery();

            if (rs.next()) {
                int id = rs.getInt("id");
                double existingPieces = rs.getDouble("available_pieces");
                double existingCostPerPiece = rs.getDouble("price");
                String existingUnit = rs.getString("unit");

                double quantityNumber = extractNumericValue(newUnit);
                double multiplier = getUnitMultiplier(newUnit, size, newUnit);
                double incomingPieces = quantityNumber * multiplier;
                double newCostPerPiece = newPrice / (multiplier > 0 ? multiplier : 1);

                // --- SMART UNIT PERSISTENCE ---
                // Only upgrade the unit if the NEW one is "larger" or equal (e.g. from Pcs to
                // Doz)
                // This prevents downgrading to 'pcs' just because the user added 6 pcs.
                double existingMultiplier = getUnitMultiplier(existingUnit, size, existingUnit);
                String unitToSave = (multiplier >= existingMultiplier) ? newUnit : existingUnit;

                // --- VALIDATION GATE ---
                if (!forceSave && existingCostPerPiece > 0) {
                    double diff = Math.abs(newCostPerPiece - existingCostPerPiece);
                    if ((diff / existingCostPerPiece) > 0.20) {
                        return false; // Tell the controller to show an alert
                    }
                }

                // Logic Fix: Setting all 6 parameters for the UPDATE
                String updateSql = "UPDATE stock SET available_pieces = ?, price = ?, supplier = ?, date = ?, unit = ?, is_edited = 1 WHERE id = ?";
                try (PreparedStatement updateStmt = connection.prepareStatement(updateSql)) {
                    updateStmt.setDouble(1, existingPieces + incomingPieces);
                    updateStmt.setDouble(2,
                            ((existingPieces * existingCostPerPiece) + (incomingPieces * newCostPerPiece))
                                    / (existingPieces + incomingPieces));
                    updateStmt.setString(3, supplier);
                    updateStmt.setString(4, LocalDate.now().toString());
                    updateStmt.setString(5, unitToSave);
                    updateStmt.setInt(6, id);
                    updateStmt.executeUpdate();
                    logStockMovement(itemName, size, incomingPieces, existingPieces, existingPieces + incomingPieces, "Stock Merged (" + supplier + " - " + newUnit + ")", "Desktop");
                    return true;
                }
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return false;
    }

    public void updateStockQuantity(String itemName, String soldSize, String soldUnit) {
        try {
            String sql = "SELECT id, unit, available_pieces FROM stock WHERE item = ? AND quantity = ?";
            PreparedStatement pstmt = connection.prepareStatement(sql);
            pstmt.setString(1, itemName);
            pstmt.setString(2, soldSize);
            ResultSet rs = pstmt.executeQuery();

            if (rs.next()) {
                int id = rs.getInt("id");
                String bulkUnit = rs.getString("unit");
                double currentPieces = rs.getDouble("available_pieces");

                double multiplier = getUnitMultiplier(soldUnit, soldSize, bulkUnit);
                double soldPieces = extractNumericValue(soldUnit) * multiplier;
                double remaining = currentPieces - soldPieces;

                if (remaining >= 0) {
                    PreparedStatement updatePstmt = connection.prepareStatement(
                            "UPDATE stock SET available_pieces = ?, is_edited = 1 WHERE id = ?");
                    updatePstmt.setDouble(1, remaining);
                    updatePstmt.setInt(2, id);
                    updatePstmt.executeUpdate();
                    logStockMovement(itemName, soldSize, -soldPieces, currentPieces, remaining, "Sale Deducted (" + soldUnit + ")", "Desktop");
                }
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

    public void reconcileUntrackedStockDiscrepancies() {
        try (Statement stmt = connection.createStatement()) {
            // Find stock items where available_pieces is less than initial addition and no sale log explains the deduction
            String sql = "SELECT item, quantity, available_pieces FROM stock";
            try (ResultSet rs = stmt.executeQuery(sql)) {
                while (rs.next()) {
                    String item = rs.getString("item");
                    String size = rs.getString("quantity");
                    double avail = rs.getDouble("available_pieces");

                    // Sum all new stock additions for this item
                    double totalAdded = 0.0;
                    try (PreparedStatement pAdd = connection.prepareStatement("SELECT SUM(base_quantity) FROM sales WHERE item = ? AND quantity = ? AND type = 'NEW STOCK'")) {
                        pAdd.setString(1, item);
                        pAdd.setString(2, size);
                        try (ResultSet rAdd = pAdd.executeQuery()) {
                            if (rAdd.next()) totalAdded = rAdd.getDouble(1);
                        }
                    }

                    // Sum all non-new-stock sales for this item
                    double totalSold = 0.0;
                    try (PreparedStatement pSale = connection.prepareStatement("SELECT SUM(base_quantity) FROM sales WHERE item = ? AND quantity = ? AND type != 'NEW STOCK'")) {
                        pSale.setString(1, item);
                        pSale.setString(2, size);
                        try (ResultSet rSale = pSale.executeQuery()) {
                            if (rSale.next()) totalSold = rSale.getDouble(1);
                        }
                    }

                    if (totalAdded > 0) {
                        double expected = totalAdded - totalSold;
                        if (expected > avail && Math.abs(expected - avail) >= 1.0) {
                            double difference = expected - avail;
                            System.out.println("AUDIT NOTE: Stock " + item + " (" + size + ") calculated net: " + expected + ", stored available: " + avail + ", diff: " + difference);
                        }
                    }
                }
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

    public ObservableList<StockItem> getInStock() {
        ObservableList<StockItem> stockList = FXCollections.observableArrayList();
        // Fetch unit column too!
        String sql = "SELECT item, quantity, unit, available_pieces, price, supplier, date FROM stock ORDER BY item";

        try (Statement stmt = connection.createStatement();
                ResultSet rs = stmt.executeQuery(sql)) {
            while (rs.next()) {
                double totalPieces = rs.getDouble("available_pieces");
                double costPerPiece = rs.getDouble("price");
                String itemSize = rs.getString("quantity");
                String bulkUnit = rs.getString("unit");

                stockList.add(new StockItem(
                        rs.getString("item"),
                        itemSize,
                        formatStockForDisplay(totalPieces, itemSize, bulkUnit),
                        String.format("%,.2f", costPerPiece),
                        String.format("%,.2f", totalPieces * costPerPiece),
                        rs.getString("supplier"),
                        rs.getString("date")));
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return stockList;
    }

    public boolean hasEnoughStock(String itemName, String size, String soldUnit) {
        try (PreparedStatement pstmt = connection
                .prepareStatement("SELECT unit, available_pieces FROM stock WHERE item = ? AND quantity = ?")) {
            pstmt.setString(1, itemName);
            pstmt.setString(2, size);
            ResultSet rs = pstmt.executeQuery();
            if (rs.next()) {
                double stockAvailable = rs.getDouble("available_pieces");
                String bulkUnit = rs.getString("unit");
                double multiplier = getUnitMultiplier(soldUnit, size, bulkUnit);
                double amountTryingToSell = extractNumericValue(soldUnit) * multiplier;
                return stockAvailable >= amountTryingToSell;
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return false;
    }

    public String getAvailableStock(String itemName, String size) {
        try (PreparedStatement pstmt = connection
                .prepareStatement("SELECT unit, quantity FROM stock WHERE item = ? AND quantity = ?")) {
            pstmt.setString(1, itemName);
            pstmt.setString(2, size);
            ResultSet rs = pstmt.executeQuery();
            if (rs.next()) {
                double total = calculateTotalBaseStock(rs.getString("unit"), rs.getString("quantity"));
                return formatStockForDisplay(total, rs.getString("quantity"), rs.getString("unit"));
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return "0 pcs";
    }

    public Map<String, Object> getStockPriceInfo(String item, String size) {
        Map<String, Object> data = new HashMap<>();
        // ORDER BY id DESC ensures we get the NEWEST price recorded
        String sql = "SELECT price, unit FROM stock WHERE item = ? AND quantity = ? ORDER BY id DESC LIMIT 1";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, item);
            pstmt.setString(2, size);
            ResultSet rs = pstmt.executeQuery();
            if (rs.next()) {
                data.put("price", rs.getDouble("price"));
                data.put("unit", rs.getString("unit").toLowerCase());
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return data;
    }
    // --- SALES & HISTORY ---

    public void addSale(String customer, String item, String quantity, String unit, double price, double amount,
            String type, String date) {
        String syncId = java.util.UUID.randomUUID().toString();
        String sql = "INSERT INTO sales(sync_id, customer, item, quantity, unit, price, cost_price, base_quantity, amount, type, date, is_edited, device_source, created_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 'Desktop', ?)";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, syncId);
            pstmt.setString(2, customer);
            pstmt.setString(3, item);
            pstmt.setString(4, quantity);
            pstmt.setString(5, unit);
            pstmt.setDouble(6, price);
            pstmt.setDouble(7, 0.0); // Default cost_price for 'NEW STOCK'
            pstmt.setDouble(8, 0.0); // Default base_quantity for 'NEW STOCK'
            pstmt.setDouble(9, amount);
            pstmt.setString(10, type);
            pstmt.setString(11, date);
            pstmt.setString(12, java.time.LocalDateTime.now().toString());
            pstmt.executeUpdate();
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

    public ObservableList<HistoryItem> getHistory(String filter) {
        ObservableList<HistoryItem> history = FXCollections.observableArrayList();

        String sql;
        if ("DEBTS".equals(filter)) {
            sql = "SELECT MIN(id) as id, customer, " +
                    "GROUP_CONCAT(quantity || ' ' || unit || ' ' || item || ' @ ' || price || ' = ' || amount || ' (' || date || ')', '\n') as item, "
                    +
                    "type, SUM(amount) as amount, SUM(amount - (cost_price * base_quantity)) as profit, " +
                    "MAX(date) as date, is_debt, is_paid, SUM(COALESCE(paid_amount, 0)) as paid_amount, " +
                    "receipt_id, MAX(created_at) as created_at " +
                    "FROM sales WHERE is_debt = 1 AND is_paid = 0 AND customer != 'Walk-in Customer' " +
                    "GROUP BY customer ORDER BY MAX(date) DESC, REPLACE(MAX(created_at), 'T', ' ') DESC";
        } else {
            sql = "SELECT MIN(id) as id, customer, " +
                    "GROUP_CONCAT(quantity || ' ' || unit || ' ' || item || ' @ ' || price || ' = ' || amount, '\n') as item, "
                    +
                    "type, SUM(amount) as amount, SUM(amount - (cost_price * base_quantity)) as profit, " +
                    "date, is_debt, is_paid, SUM(COALESCE(paid_amount, 0)) as paid_amount, " +
                    "receipt_id, MAX(created_at) as created_at " +
                    "FROM sales ";

            if (filter != null && !filter.isEmpty() && !"ALL".equals(filter)) {
                sql += "WHERE type = ? ";
            } else {
                // When ALL is selected, just show everything including NEW STOCK
                sql += "WHERE 1=1 ";
            }
            sql += " GROUP BY COALESCE(NULLIF(receipt_id, ''), CASE WHEN (created_at IS NOT NULL AND created_at != '') THEN (created_at || customer) ELSE id END) " +
                    " ORDER BY date DESC, REPLACE(MAX(created_at), 'T', ' ') DESC";
        }

        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            if (filter != null && !filter.isEmpty() && !"ALL".equals(filter) && !"DEBTS".equals(filter))
                pstmt.setString(1, filter);
            ResultSet rs = pstmt.executeQuery();

            while (rs.next()) {
                double amount = rs.getDouble("amount");
                long profitVal = Math.round(rs.getDouble("profit"));

                history.add(new HistoryItem(
                        rs.getInt("id"),
                        rs.getString("customer"),
                        rs.getString("item"),
                        rs.getString("type"),
                        "-", // quantity (merged into item)
                        "-", // unit (merged into item)
                        "-", // individual price (merged into item)
                        String.format("%,.0f", amount),
                        String.format("%,d", profitVal),
                        rs.getString("date"),
                        rs.getInt("is_debt") == 1,
                        rs.getInt("is_paid") == 1,
                        String.format("%,.0f", rs.getDouble("paid_amount"))));
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return history;
    }

    public ObservableList<HistoryItem> getTodaysSales() {
        ObservableList<HistoryItem> history = FXCollections.observableArrayList();
        String today = LocalDate.now().toString();
        String sql = "SELECT id, customer, item, type, quantity, unit, price, amount, cost_price, base_quantity, date, is_debt, is_paid, paid_amount FROM sales "
                + "WHERE date = ? AND type != 'NEW STOCK' "
                + "AND NOT EXISTS ("
                + "  SELECT 1 FROM deleted_history "
                + "  WHERE (sales.sync_id IS NOT NULL AND sales.sync_id != '' AND deleted_history.sync_id = sales.sync_id) "
                + "     OR ((sales.sync_id IS NULL OR sales.sync_id = '') AND deleted_history.item = sales.item AND deleted_history.date = sales.date AND (deleted_history.customer = sales.customer OR deleted_history.customer IS NULL OR deleted_history.customer = '' OR sales.customer IS NULL OR sales.customer = ''))"
                + ") ORDER BY created_at DESC";

        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, today);
            ResultSet rs = pstmt.executeQuery();
            while (rs.next()) {
                double amount = rs.getDouble("amount");
                double cost = rs.getDouble("cost_price");
                double baseQty = rs.getDouble("base_quantity");
                double profitVal = amount - (cost * baseQty);

                history.add(new HistoryItem(
                        rs.getInt("id"),
                        rs.getString("customer"),
                        rs.getString("item"),
                        rs.getString("type"),
                        rs.getString("quantity"),
                        rs.getString("unit"),
                        String.format("%,.0f", rs.getDouble("price")),
                        String.format("%,.0f", amount),
                        String.format("%,.0f", profitVal),
                        rs.getString("date"),
                        rs.getInt("is_debt") == 1,
                        rs.getInt("is_paid") == 1,
                        String.format("%,.0f", rs.getDouble("paid_amount"))));
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return history;
    }

    public void addSaleWithProfit(String customer, String item, String size, String unit, double sellingPrice,
            double totalAmount, String type, boolean isDebt, String receiptId) {
        double costPrice = getLastRecordedPrice(item, size);

        String bulkUnit = "";
        try (PreparedStatement pstmt = connection
                .prepareStatement("SELECT unit FROM stock WHERE item = ? AND quantity = ? LIMIT 1")) {
            pstmt.setString(1, item);
            pstmt.setString(2, size);
            ResultSet rs = pstmt.executeQuery();
            if (rs.next())
                bulkUnit = rs.getString("unit");
        } catch (SQLException e) {
            e.printStackTrace();
        }

        double quantityFactor = extractNumericValue(unit);
        // For NEW STOCK the multiplier must be computed the same way addStock() does it
        // (passing `unit` as its own bulkUnit reference), so that base_quantity in the
        // sales history row exactly equals the available_pieces added to the stock table.
        // For WHOLESALE / RETAIL we continue to use the stock table's bulk unit so that
        // the deduction factor matches what updateStockQuantity() subtracts.
        double multiplier = "NEW STOCK".equals(type)
                ? getUnitMultiplier(unit, size, unit)
                : getUnitMultiplier(unit, size, bulkUnit);
        double baseQty = quantityFactor * multiplier;

        String syncId = java.util.UUID.randomUUID().toString();
        String sql = "INSERT INTO sales(sync_id, customer, item, quantity, unit, price, cost_price, base_quantity, amount, type, date, is_debt, is_paid, paid_amount, is_edited, device_source, receipt_id, created_at) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 'Desktop', ?, ?)";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, syncId);
            pstmt.setString(2, customer);
            pstmt.setString(3, item);
            pstmt.setString(4, size);
            pstmt.setString(5, unit);
            pstmt.setDouble(6, sellingPrice);
            pstmt.setDouble(7, costPrice);
            pstmt.setDouble(8, baseQty);
            pstmt.setDouble(9, totalAmount);
            pstmt.setString(10, type);
            pstmt.setString(11, LocalDate.now().toString());
            pstmt.setInt(12, isDebt ? 1 : 0);
            pstmt.setInt(13, isDebt ? 0 : 1); // is_paid
            pstmt.setDouble(14, isDebt ? 0 : totalAmount); // paid_amount
            pstmt.setString(15, receiptId);
            pstmt.setString(16, java.time.LocalDateTime.now().toString());
            pstmt.executeUpdate();
            if (!"NEW STOCK".equals(type)) {
                addNotification("Sale recorded: " + customer + " bought " + item + " (" + unit + ", UGX " + String.format("%,.0f", totalAmount) + ")", "Desktop");
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

    public List<com.meto.inventory.models.SaleItem> getReceiptItems(int saleId) {
        List<com.meto.inventory.models.SaleItem> items = new ArrayList<>();
        String getInfoSql = "SELECT customer, created_at, receipt_id FROM sales WHERE id = ?";
        try (PreparedStatement pstmt = connection.prepareStatement(getInfoSql)) {
            pstmt.setInt(1, saleId);
            ResultSet rs = pstmt.executeQuery();
            if (rs.next()) {
                String customer = rs.getString("customer");
                String createdAt = rs.getString("created_at");
                String receiptId = rs.getString("receipt_id");

                String getItemsSql;
                if (receiptId != null && !receiptId.isEmpty()) {
                    getItemsSql = "SELECT item, quantity, unit, price, amount FROM sales WHERE receipt_id = ?";
                } else {
                    // Fallback for legacy data: Group by customer and exact created_at
                    getItemsSql = "SELECT item, quantity, unit, price, amount FROM sales WHERE customer = ? AND created_at = ?";
                }

                try (PreparedStatement pstmtItems = connection.prepareStatement(getItemsSql)) {
                    if (receiptId != null && !receiptId.isEmpty()) {
                        pstmtItems.setString(1, receiptId);
                    } else {
                        pstmtItems.setString(1, customer);
                        pstmtItems.setString(2, createdAt);
                    }
                    ResultSet rsItems = pstmtItems.executeQuery();
                    while (rsItems.next()) {
                        items.add(new com.meto.inventory.models.SaleItem(
                                rsItems.getString("item"),
                                rsItems.getString("quantity"),
                                rsItems.getString("unit"),
                                String.format("%,.2f", rsItems.getDouble("price")),
                                String.format("%,.2f", rsItems.getDouble("amount"))));
                    }
                }
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return items;
    }

    public void markSaleAsPaid(int id, double newPayment) {
        String selectSql = "SELECT amount, paid_amount FROM sales WHERE id = ?";
        try (PreparedStatement selectStmt = connection.prepareStatement(selectSql)) {
            selectStmt.setInt(1, id);
            ResultSet rs = selectStmt.executeQuery();
            if (rs.next()) {
                double totalAmount = rs.getDouble("amount");
                double currentPaid = rs.getDouble("paid_amount");
                double updatedPaid = currentPaid + newPayment;

                // 1. Record the payment log
                try (PreparedStatement payStmt = connection.prepareStatement(
                        "INSERT INTO debt_payments(sale_id, amount_paid, payment_date, sync_id) VALUES(?, ?, ?, ?)")) {
                    payStmt.setInt(1, id);
                    payStmt.setDouble(2, newPayment);
                    payStmt.setString(3, LocalDate.now().toString());
                    payStmt.setString(4, java.util.UUID.randomUUID().toString());
                    payStmt.executeUpdate();
                }

                // 2. Update the sale status
                if (updatedPaid >= totalAmount) {
                    try (PreparedStatement updateStmt = connection.prepareStatement(
                            "UPDATE sales SET paid_amount = amount, is_paid = 1, is_edited = 1 WHERE id = ?")) {
                        updateStmt.setInt(1, id);
                        updateStmt.executeUpdate();
                    }
                } else {
                    try (PreparedStatement updateStmt = connection
                            .prepareStatement("UPDATE sales SET paid_amount = ?, is_edited = 1 WHERE id = ?")) {
                        updateStmt.setDouble(1, updatedPaid);
                        updateStmt.setInt(2, id);
                        updateStmt.executeUpdate();
                    }
                }
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        addNotification("Payment of " + newPayment + " received for sale #" + id, "Desktop");
        com.meto.inventory.services.NotificationService.getInstance()
                .sendDesktopActionNotification("Debt payment received", "Sale #" + id + " paid UGX "
                        + String.format("%,.0f", newPayment) + " toward their debt. Tap to view their balance");
    }

    public void markDebtAsPaid(String customer, double newPayment) {
        String selectSql = "SELECT id, amount, paid_amount FROM sales WHERE customer = ? AND is_debt = 1 AND is_paid = 0 ORDER BY date ASC, created_at ASC";
        try (PreparedStatement selectStmt = connection.prepareStatement(selectSql)) {
            selectStmt.setString(1, customer);
            ResultSet rs = selectStmt.executeQuery();
            double remainingPayment = newPayment;

            while (rs.next() && remainingPayment > 0) {
                int id = rs.getInt("id");
                double totalAmount = rs.getDouble("amount");
                double currentPaid = rs.getDouble("paid_amount");
                double debtRemainingOnItem = totalAmount - currentPaid;

                double amountToApply = Math.min(debtRemainingOnItem, remainingPayment);
                double updatedPaid = currentPaid + amountToApply;
                remainingPayment -= amountToApply;

                // 1. Record the payment log
                try (PreparedStatement payStmt = connection.prepareStatement(
                        "INSERT INTO debt_payments(sale_id, amount_paid, payment_date, sync_id) VALUES(?, ?, ?, ?)")) {
                    payStmt.setInt(1, id);
                    payStmt.setDouble(2, amountToApply);
                    payStmt.setString(3, LocalDate.now().toString());
                    payStmt.setString(4, java.util.UUID.randomUUID().toString());
                    payStmt.executeUpdate();
                }

                // 2. Update the sale status
                // Do not set is_paid = 1 yet. Wait until the whole debt is cleared.
                try (PreparedStatement updateStmt = connection
                        .prepareStatement("UPDATE sales SET paid_amount = ?, is_edited = 1 WHERE id = ?")) {
                    updateStmt.setDouble(1, updatedPaid);
                    updateStmt.setInt(2, id);
                    updateStmt.executeUpdate();
                }
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }

        // 3. Check if all debt is cleared
        double totalDebtNow = getCustomerDebt(customer);
        if (totalDebtNow <= 0) {
            // Entire debt cycle cleared! Mark all as paid.
            try (PreparedStatement updateStmt = connection.prepareStatement(
                    "UPDATE sales SET is_paid = 1, is_edited = 1 WHERE customer = ? AND is_debt = 1 AND is_paid = 0")) {
                updateStmt.setString(1, customer);
                updateStmt.executeUpdate();
            } catch (SQLException e) {
                e.printStackTrace();
            }
        }
        addNotification("Payment of " + newPayment + " received for " + customer, "Desktop");

        // Custom FCM Notification
        double remainingDebt = getCustomerDebt(customer);
        if (remainingDebt <= 0) {
            com.meto.inventory.services.NotificationService.getInstance().sendDesktopActionNotification(
                    "Debt payment received", customer + " just cleared their outstanding balance.");
        } else {
            com.meto.inventory.services.NotificationService.getInstance()
                    .sendDesktopActionNotification("Debt payment received", customer + " paid UGX "
                            + String.format("%,.0f", newPayment) + " toward their debt. Tap to view their balance");
        }
    }

    public double getCurrentYearProfit() {
        String yearPrefix = LocalDate.now().getYear() + "-%";
        String sql = "SELECT SUM(amount - (cost_price * base_quantity)) FROM sales WHERE date LIKE ? AND type != 'NEW STOCK'";

        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, yearPrefix);
            ResultSet rs = pstmt.executeQuery();
            if (rs.next())
                return rs.getDouble(1);
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return 0.0;
    }

    public void archiveYearlyProfit() {
        int year = LocalDate.now().getYear();
        double totalProfit = getCurrentYearProfit();

        String sql = "INSERT OR REPLACE INTO yearly_summaries (year, total_profit) VALUES (?, ?)";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setInt(1, year);
            pstmt.setDouble(2, totalProfit);
            pstmt.executeUpdate();
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

    public double getLastRecordedPrice(String item, String size) {
        // Find the most recent price in the stock table for this specific item/size
        String sql = "SELECT price FROM stock WHERE item = ? AND quantity = ? LIMIT 1";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, item);
            pstmt.setString(2, size);
            ResultSet rs = pstmt.executeQuery();
            if (rs.next()) {
                return rs.getDouble("price");
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return 0.0;
    }

    // --- DATA HELPERS ---

    public double extractNumericValue(String text) {
        if (text == null || text.isEmpty())
            return 0.0;

        String lowercaseText = text.toLowerCase().trim();
        double fractionValue = 0.0;

        // 1. Identify the fraction value
        if (lowercaseText.contains("1/4"))
            fractionValue = 0.25;
        else if (lowercaseText.contains("1/2"))
            fractionValue = 0.5;

        // 2. Extract the FIRST whole number
        // We strip known fractions first to avoid confusing the regex
        String cleaned = lowercaseText.replace("1/4", "").replace("1/2", "");
        java.util.regex.Pattern pattern = java.util.regex.Pattern.compile("(\\d+\\.?\\d*)");
        java.util.regex.Matcher matcher = pattern.matcher(cleaned);

        if (matcher.find()) {
            try {
                double value = Double.parseDouble(matcher.group(1));
                // If it's something like "2 1/2", we should probably ADD them,
                // but the user says "only numbers" (no decimals).
                // However, internal logic still supports fractions for weight.
                if (fractionValue > 0) {
                    return value + fractionValue; // Changed from * to + for correct composite values like "2 1/2"
                }
                return value;
            } catch (NumberFormatException e) {
                return fractionValue;
            }
        }
        return fractionValue;
    }

    public double getExistingPrice(String item, String size) {
        String sql = "SELECT price FROM stock WHERE item = ? AND quantity = ? LIMIT 1";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, item);
            pstmt.setString(2, size);
            ResultSet rs = pstmt.executeQuery();
            if (rs.next()) {
                return rs.getDouble("price"); // This is the price per 1 KG (e.g., 3000)
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return 0.0;
    }

    public double getUnitMultiplier(String unitText, String size, String bulkUnit) {
        if (unitText == null || unitText.isEmpty())
            return 1.0;
        String type = unitText.toLowerCase().replaceAll("\\s+", ""); // Normalize spaces
        String sizeLower = size.toLowerCase().replaceAll("\\s+", "");
        String bulkLower = (bulkUnit != null) ? bulkUnit.toLowerCase().replaceAll("\\s+", "") : "";

        double sizeNum = extractNumericValue(sizeLower);
        boolean isBulkSack = sizeLower.contains("kg") && sizeNum >= 10.0;

        if (type.contains("sack") || (isBulkSack && (type.contains("pc") || type.contains("item")))) {
            return sizeNum;
        }

        // 1. Check for explicit multiplier in the unit itself (e.g. "pcs*12" or
        // "box*72")
        if (type.contains("*")) {
            try {
                String afterStar = type.substring(type.lastIndexOf("*") + 1).trim();
                double val = extractNumericValue(afterStar);
                if (val > 0)
                    return val;
            } catch (Exception e) {
            }
        }

        // Normalize 'type' by removing leading quantities for generic matching (e.g. "2
        // boxes" -> "boxes")
        String normalizedType = type.replaceAll("^[0-9./* ]+", "");

        // 2. Specific Handle Piece or Item units (always 1.0 unless explicit * was used
        // above)
        if (normalizedType.equals("pc") || normalizedType.equals("pcs") || normalizedType.equals("item")
                || normalizedType.equals("items")) {
            return 1.0;
        }

        // 3. Check for specific packaging (Dozens, etc.)
        if (normalizedType.contains("halfdoz"))
            return 6.0;
        if (normalizedType.contains("half"))
            return 0.5;
        if (normalizedType.contains("quarter"))
            return 0.25;
        if (normalizedType.contains("dozen") || normalizedType.contains("doz"))
            return 12.0;

        // 4. Generic bulk unit text matching item's metadata (Box, Carton, etc.)
        if (normalizedType.equals("box") || normalizedType.equals("boxes") || normalizedType.contains("carton")
                || normalizedType.contains("crate")) {
            // First check the size meta-data for multiplier
            if (sizeLower.contains("*")) {
                try {
                    String afterStar = sizeLower.substring(sizeLower.lastIndexOf("*") + 1).trim();
                    double val = extractNumericValue(afterStar);
                    if (val > 0)
                        return val;
                } catch (Exception e) {
                }
            }
            // Then check the bulk unit meta-data for multiplier
            if (bulkLower.contains("*")) {
                try {
                    String afterStar = bulkLower.substring(bulkLower.lastIndexOf("*") + 1).trim();
                    double val = extractNumericValue(afterStar);
                    if (val > 0)
                        return val;
                } catch (Exception e) {
                }
            }

            // Fallback if no star but it's a known bulk term
            if (normalizedType.contains("carton"))
                return 24.0;
            if (normalizedType.contains("crate"))
                return 25.0;
            return 20.0; // Standard fallback for generic box
        }

        // Legacy Fallbacks (space-normalized)
        if (type.contains("box*10"))
            return 10.0;
        if (type.contains("box*12"))
            return 12.0;
        if (type.contains("box*24"))
            return 24.0;
        if (type.contains("crate*25"))
            return 25.0;
        if (type.contains("box*72"))
            return 72.0;
        if (type.contains("box*20"))
            return 20.0;

        return 1.0;
    }

    public void addStock(String s, String i, String q, String u, double p, String d) {
        double unitCount = extractNumericValue(u);
        double multiplier = getUnitMultiplier(u, q, u);
        double totalPieces = unitCount * multiplier;

        // Change this line to keep the decimals
        double pricePerSinglePiece = (double) p / multiplier; // e.g., 2083.33333333

        // Clear any prior deletion tombstone when re-adding stock
        try (PreparedStatement delTomb = connection.prepareStatement("DELETE FROM deleted_stock WHERE item = ? AND quantity = ?")) {
            delTomb.setString(1, i);
            delTomb.setString(2, q);
            delTomb.executeUpdate();
        } catch (SQLException ignored) {}

        String syncId = java.util.UUID.randomUUID().toString();
        String sql = "INSERT INTO stock(sync_id, supplier, item, quantity, unit, price, available_pieces, date, is_edited, device_source) VALUES(?, ?, ?, ?, ?, ?, ?, ?, 1, 'Desktop')";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, syncId);
            pstmt.setString(2, s);
            pstmt.setString(3, i);
            pstmt.setString(4, q);
            pstmt.setString(5, u);
            pstmt.setDouble(6, pricePerSinglePiece); // SQL REAL type will store decimals
            pstmt.setDouble(7, totalPieces);
            pstmt.setString(8, d);
            pstmt.executeUpdate();
            logStockMovement(i, q, totalPieces, 0, totalPieces, "New Stock Added (" + s + ")", "Desktop");
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

    public void logStockMovement(String item, String size, double changePieces, double prevPieces, double newPieces, String reason, String deviceSource) {
        String sql = "INSERT INTO stock_movement_log(item, quantity, change_pieces, previous_pieces, new_pieces, change_reason, device_source) VALUES(?, ?, ?, ?, ?, ?, ?)";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, item);
            pstmt.setString(2, size);
            pstmt.setDouble(3, changePieces);
            pstmt.setDouble(4, prevPieces);
            pstmt.setDouble(5, newPieces);
            pstmt.setString(6, reason);
            pstmt.setString(7, deviceSource != null ? deviceSource : "Desktop");
            pstmt.executeUpdate();
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

    public boolean hasData() {
        try {
            // Check if there are any rows in stock or sales
            try (Statement stmt = connection.createStatement()) {
                ResultSet rs1 = stmt.executeQuery("SELECT 1 FROM stock LIMIT 1");
                if (rs1.next())
                    return true;

                ResultSet rs2 = stmt.executeQuery("SELECT 1 FROM sales LIMIT 1");
                if (rs2.next())
                    return true;

                // NEW: Also check deletions!
                ResultSet rs3 = stmt.executeQuery("SELECT 1 FROM deleted_stock LIMIT 1");
                if (rs3.next())
                    return true;

                ResultSet rs4 = stmt.executeQuery("SELECT 1 FROM deleted_history LIMIT 1");
                if (rs4.next())
                    return true;
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return false;
    }

    public ObservableList<String> getAvailableItems() {
        ObservableList<String> items = FXCollections.observableArrayList();
        try (Statement stmt = connection.createStatement();
                ResultSet rs = stmt.executeQuery("SELECT DISTINCT item FROM stock ORDER BY item")) {
            while (rs.next())
                items.add(rs.getString("item"));
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return items;
    }

    public ObservableList<String> getItemSizes(String itemName) {
        ObservableList<String> sizes = FXCollections.observableArrayList();
        try (PreparedStatement pstmt = connection
                .prepareStatement("SELECT DISTINCT quantity FROM stock WHERE item = ?")) {
            pstmt.setString(1, itemName);
            ResultSet rs = pstmt.executeQuery();
            while (rs.next())
                sizes.add(rs.getString("quantity"));
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return sizes;
    }

    public boolean deleteStockItem(String itemName, String size) {
        String sql = "DELETE FROM stock WHERE item = ? AND quantity = ?";
        try {
            // Fetch sync_id before deletion
            String syncId = null;
            try (PreparedStatement fetch = connection
                    .prepareStatement("SELECT sync_id FROM stock WHERE item = ? AND quantity = ?")) {
                fetch.setString(1, itemName);
                fetch.setString(2, size);
                ResultSet rs = fetch.executeQuery();
                if (rs.next())
                    syncId = rs.getString("sync_id");
            }
            if (syncId == null)
                syncId = java.util.UUID.randomUUID().toString();

            // Track the deletion for cloud merging
            try (PreparedStatement delTrack = connection
                    .prepareStatement("INSERT INTO deleted_stock(sync_id, item, quantity) VALUES(?, ?, ?)")) {
                delTrack.setString(1, syncId);
                delTrack.setString(2, itemName);
                delTrack.setString(3, size);
                delTrack.executeUpdate();
            }

            // Also move associated sales into deleted_history and remove from sales table
            try (PreparedStatement fetchSales = connection.prepareStatement("SELECT sync_id, customer, item, quantity, unit, price, cost_price, base_quantity, amount, type, date, is_debt, is_paid, paid_amount FROM sales WHERE item = ? OR LOWER(REPLACE(item, ' ', '')) = LOWER(REPLACE(?, ' ', ''))");
                 PreparedStatement insHist = connection.prepareStatement("INSERT INTO deleted_history(sync_id, customer, item, quantity, unit, price, cost_price, base_quantity, amount, type, date, is_debt, is_paid, paid_amount, is_edited) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)");
                 PreparedStatement delSales = connection.prepareStatement("DELETE FROM sales WHERE item = ? OR LOWER(REPLACE(item, ' ', '')) = LOWER(REPLACE(?, ' ', ''))")) {
                fetchSales.setString(1, itemName);
                fetchSales.setString(2, itemName);
                ResultSet rsSales = fetchSales.executeQuery();
                while (rsSales.next()) {
                    String sId = rsSales.getString("sync_id");
                    if (sId == null || sId.isEmpty()) sId = java.util.UUID.randomUUID().toString();
                    insHist.setString(1, sId);
                    insHist.setString(2, rsSales.getString("customer"));
                    insHist.setString(3, rsSales.getString("item"));
                    insHist.setString(4, rsSales.getString("quantity"));
                    insHist.setString(5, rsSales.getString("unit"));
                    insHist.setDouble(6, rsSales.getDouble("price"));
                    insHist.setDouble(7, rsSales.getDouble("cost_price"));
                    insHist.setDouble(8, rsSales.getDouble("base_quantity"));
                    insHist.setString(9, rsSales.getString("amount"));
                    insHist.setString(10, rsSales.getString("type"));
                    insHist.setString(11, rsSales.getString("date"));
                    insHist.setInt(12, rsSales.getInt("is_debt"));
                    insHist.setInt(13, rsSales.getInt("is_paid"));
                    insHist.setDouble(14, rsSales.getDouble("paid_amount"));
                    insHist.executeUpdate();
                }
                delSales.setString(1, itemName);
                delSales.setString(2, itemName);
                delSales.executeUpdate();
            } catch (SQLException e) {
                System.err.println("Warning clearing associated sales on stock deletion: " + e.getMessage());
            }

            try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
                pstmt.setString(1, itemName);
                pstmt.setString(2, size);
                int affected = pstmt.executeUpdate();
                return affected > 0;
            }
        } catch (SQLException e) {
            e.printStackTrace();
            return false;
        }
    }

    public boolean deleteHistoryItem(int id) {
        String getInfoSql = "SELECT sync_id, customer, item, quantity, unit, price, cost_price, base_quantity, amount, type, date, is_debt, is_paid, paid_amount, receipt_id, created_at FROM sales WHERE id = ?";
        try {
            String receiptId = null;
            try (PreparedStatement pstmt = connection.prepareStatement(getInfoSql)) {
                pstmt.setInt(1, id);
                ResultSet rs = pstmt.executeQuery();
                if (rs.next()) {
                    receiptId = rs.getString("receipt_id");
                } else {
                    return false;
                }
            }

            List<Integer> idsToDelete = new ArrayList<>();
            if (receiptId != null && !receiptId.isEmpty() && !"null".equalsIgnoreCase(receiptId)) {
                try (PreparedStatement gPstmt = connection.prepareStatement("SELECT id FROM sales WHERE receipt_id = ?")) {
                    gPstmt.setString(1, receiptId);
                    ResultSet gRs = gPstmt.executeQuery();
                    while (gRs.next()) idsToDelete.add(gRs.getInt("id"));
                }
            } else {
                idsToDelete.add(id);
            }

            for (int itemId : idsToDelete) {
                try (PreparedStatement fetch = connection.prepareStatement("SELECT sync_id, customer, item, quantity, unit, price, cost_price, base_quantity, amount, type, date, is_debt, is_paid, paid_amount FROM sales WHERE id = ?");
                     PreparedStatement ins = connection.prepareStatement("INSERT INTO deleted_history(sync_id, customer, item, quantity, unit, price, cost_price, base_quantity, amount, type, date, is_debt, is_paid, paid_amount, is_edited) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1)");
                     PreparedStatement del = connection.prepareStatement("DELETE FROM sales WHERE id = ?")) {
                    fetch.setInt(1, itemId);
                    ResultSet r = fetch.executeQuery();
                    if (r.next()) {
                        String sId = r.getString("sync_id");
                        if (sId == null || sId.isEmpty()) sId = java.util.UUID.randomUUID().toString();
                        ins.setString(1, sId);
                        ins.setString(2, r.getString("customer"));
                        ins.setString(3, r.getString("item"));
                        ins.setString(4, r.getString("quantity"));
                        ins.setString(5, r.getString("unit"));
                        ins.setDouble(6, r.getDouble("price"));
                        ins.setDouble(7, r.getDouble("cost_price"));
                        ins.setDouble(8, r.getDouble("base_quantity"));
                        ins.setString(9, r.getString("amount"));
                        ins.setString(10, r.getString("type"));
                        ins.setString(11, r.getString("date"));
                        ins.setInt(12, r.getInt("is_debt"));
                        ins.setInt(13, r.getInt("is_paid"));
                        ins.setDouble(14, r.getDouble("paid_amount"));
                        ins.executeUpdate();

                        String sItem = r.getString("item");
                        String sQty = r.getString("quantity");
                        String sUnit = r.getString("unit");
                        String sType = r.getString("type");

                        if (sItem != null && !sItem.isEmpty() && sQty != null && !sQty.isEmpty()) {
                            double count = extractNumericValue(sUnit) * getUnitMultiplier(sUnit, sQty, sUnit);
                            if (!"NEW STOCK".equals(sType) && !"Debt Payment".equals(sType) && !"Payment".equals(sType)) {
                                try (PreparedStatement uStock = connection.prepareStatement("UPDATE stock SET available_pieces = available_pieces + ?, is_edited = 1 WHERE item = ? AND quantity = ?")) {
                                    uStock.setDouble(1, count);
                                    uStock.setString(2, sItem);
                                    uStock.setString(3, sQty);
                                    uStock.executeUpdate();
                                }
                            }
                        }

                        del.setInt(1, itemId);
                        del.executeUpdate();
                    }
                }
            }
            return true;
        } catch (SQLException e) {
            e.printStackTrace();
            return false;
        }
    }

    public ObservableList<String> getDistinctSuppliers() {
        ObservableList<String> names = FXCollections.observableArrayList();
        String sql = "SELECT supplier FROM stock WHERE supplier IS NOT NULL AND supplier != '' " +
                     "UNION " +
                     "SELECT customer AS supplier FROM sales WHERE type = 'NEW STOCK' AND customer IS NOT NULL AND customer != '' " +
                     "ORDER BY supplier COLLATE NOCASE";
        try (Statement stmt = connection.createStatement();
                ResultSet rs = stmt.executeQuery(sql)) {
            while (rs.next()) {
                String s = rs.getString("supplier");
                if (s != null && !s.isBlank())
                    names.add(s);
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return names;
    }

    public ObservableList<String> getPriceHistory(String item, String size) {
        ObservableList<String> prices = FXCollections.observableArrayList();
        String sql = "SELECT DISTINCT price FROM sales WHERE item = ? AND quantity = ? AND type != 'NEW STOCK' ORDER BY created_at DESC LIMIT 10";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, item);
            pstmt.setString(2, size);
            ResultSet rs = pstmt.executeQuery();
            java.text.DecimalFormat df = new java.text.DecimalFormat("#,###");
            while (rs.next()) {
                prices.add(df.format(rs.getDouble("price")));
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return prices;
    }

    public ObservableList<String> getDistinctCustomers() {
        ObservableList<String> names = FXCollections.observableArrayList();
        try (Statement stmt = connection.createStatement();
                ResultSet rs = stmt.executeQuery(
                        "SELECT DISTINCT customer FROM sales WHERE type != 'NEW STOCK' ORDER BY customer")) {
            while (rs.next()) {
                String c = rs.getString("customer");
                if (c != null && !c.isBlank() && !c.equalsIgnoreCase("Walk-in Customer"))
                    names.add(c);
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return names;
    }

    public void saveSetting(String key, String value) {
        String sql = "INSERT OR REPLACE INTO settings (key, value) VALUES (?, ?)";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, key);
            pstmt.setString(2, value);
            pstmt.executeUpdate();
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

    public String getSetting(String key) {
        try {
            if (connection == null || connection.isClosed()) {
                initializeDatabase();
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }

        String sql = "SELECT value FROM settings WHERE key = ?";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, key);
            ResultSet rs = pstmt.executeQuery();
            if (rs.next()) {
                return rs.getString("value");
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return null;
    }

    public void checkAutoResyncMigration() {
        try {
            String done = getSetting("auto_resync_zombie_v5");
            if (done == null || !"1".equals(done)) {
                System.out.println("MIGRATION (Desktop): Performing one-time auto-resync and cache cleanup for zombie stock & sales");
                try (Statement stmt = connection.createStatement()) {
                    stmt.execute("UPDATE sales SET is_edited = 0 WHERE sync_id IS NOT NULL AND sync_id != ''");
                } catch (Exception e) {}
                saveSetting("last_backup_timestamp", "0");
                cleanupZombieStock();
                saveSetting("auto_resync_zombie_v5", "1");
            }

            String doneTombstones = getSetting("has_cleared_stale_tombstones_v1");
            if (doneTombstones == null || !"1".equals(doneTombstones)) {
                try (Statement stmt = connection.createStatement()) {
                    stmt.execute("DELETE FROM deleted_stock WHERE EXISTS (SELECT 1 FROM stock WHERE stock.item = deleted_stock.item AND stock.quantity = deleted_stock.quantity)");
                    stmt.execute("DELETE FROM deleted_history WHERE EXISTS (SELECT 1 FROM sales WHERE sales.customer = deleted_history.customer AND sales.item = deleted_history.item AND sales.date = deleted_history.date)");
                    saveSetting("has_cleared_stale_tombstones_v1", "1");
                    System.out.println("MIGRATION (Desktop): Cleared stale tombstones for active stock/sales.");
                } catch (Exception e) {
                    System.err.println("Failed to clear stale tombstones on Desktop: " + e.getMessage());
                }
            }

            String doneGhostSales = getSetting("has_purged_ghost_sales_v1");
            if (doneGhostSales == null || !"1".equals(doneGhostSales)) {
                try (Statement stmt = connection.createStatement()) {
                    stmt.execute("DELETE FROM sales WHERE EXISTS (SELECT 1 FROM deleted_history WHERE (deleted_history.sync_id = sales.sync_id AND sales.sync_id IS NOT NULL AND sales.sync_id != '') OR (deleted_history.item = sales.item AND deleted_history.date = sales.date))");
                    saveSetting("has_purged_ghost_sales_v1", "1");
                    System.out.println("MIGRATION (Desktop): Purged ghost sales matching deleted_history.");
                } catch (Exception e) {
                    System.err.println("Failed to purge ghost sales on Desktop: " + e.getMessage());
                }
            }

            String doneStockSales = getSetting("has_purged_deleted_stock_sales_v3");
            if (doneStockSales == null || !"1".equals(doneStockSales)) {
                try (Statement stmt = connection.createStatement()) {
                    stmt.execute("INSERT INTO deleted_history (sync_id, customer, item, quantity, unit, price, cost_price, base_quantity, amount, type, date, is_debt, is_paid, paid_amount, is_edited, device_source) " +
                        "SELECT COALESCE(NULLIF(sales.sync_id, ''), lower(hex(randomblob(4))) || '-' || lower(hex(randomblob(2))) || '-4' || substr(lower(hex(randomblob(2))),2) || '-a' || substr(lower(hex(randomblob(2))),2) || '-' || lower(hex(randomblob(6)))), " +
                        "sales.customer, sales.item, sales.quantity, sales.unit, sales.price, sales.cost_price, sales.base_quantity, sales.amount, sales.type, sales.date, sales.is_debt, sales.is_paid, sales.paid_amount, 1, 'Migration' " +
                        "FROM sales WHERE (" +
                        "  EXISTS (" +
                        "    SELECT 1 FROM deleted_stock WHERE LOWER(REPLACE(deleted_stock.item, ' ', '')) = LOWER(REPLACE(sales.item, ' ', '')) OR sales.item LIKE '%' || deleted_stock.item || '%' OR deleted_stock.item LIKE '%' || sales.item || '%'" +
                        "  )" +
                        ") AND sales.type != 'NEW STOCK'");
                    stmt.execute("DELETE FROM sales WHERE (" +
                        "  EXISTS (" +
                        "    SELECT 1 FROM deleted_stock WHERE LOWER(REPLACE(deleted_stock.item, ' ', '')) = LOWER(REPLACE(sales.item, ' ', '')) OR sales.item LIKE '%' || deleted_stock.item || '%' OR deleted_stock.item LIKE '%' || sales.item || '%'" +
                        "  )" +
                        ") AND sales.type != 'NEW STOCK'");
                    saveSetting("has_purged_deleted_stock_sales_v3", "1");
                    System.out.println("MIGRATION (Desktop): Purged ghost sales associated with deleted stock.");
                } catch (Exception e) {
                    System.err.println("Failed to purge ghost sales for deleted stock on Desktop: " + e.getMessage());
                }
            }

            String fixZerospot = getSetting("fix_zerospot_tombstones_v1");
            if (fixZerospot == null || !"1".equals(fixZerospot)) {
                try (Statement stmt = connection.createStatement()) {
                    stmt.execute("DELETE FROM deleted_history WHERE (LOWER(item) LIKE '%zerospot%' OR LOWER(item) LIKE '%zero%spot%') AND device_source = 'Migration'");
                    saveSetting("fix_zerospot_tombstones_v1", "1");
                    System.out.println("MIGRATION (Desktop): Cleared invalid migration tombstones for zerospot.");
                } catch (Exception e) {
                    System.err.println("Failed to clear zerospot tombstones: " + e.getMessage());
                }
            }

            // Perform automatic audit reconciliation for untracked piece discrepancies
            reconcileUntrackedStockDiscrepancies();
        } catch (Exception e) {
            System.err.println("Auto resync migration check failed: " + e.getMessage());
        }
    }

    public void cleanupZombieStock() {
        String sql = "SELECT id, item, quantity, sync_id FROM stock WHERE (available_pieces <= 0 OR NOT EXISTS (SELECT 1 FROM sales WHERE sales.item = stock.item AND sales.quantity = stock.quantity AND sales.type = 'NEW STOCK')) AND (is_edited = 0 OR is_edited IS NULL)";
        try (Statement stmt = connection.createStatement();
             ResultSet rs = stmt.executeQuery(sql)) {
            List<Map<String, String>> zombies = new ArrayList<>();
            while (rs.next()) {
                Map<String, String> z = new HashMap<>();
                z.put("id", String.valueOf(rs.getInt("id")));
                z.put("item", rs.getString("item"));
                z.put("quantity", rs.getString("quantity"));
                String syncId = rs.getString("sync_id");
                z.put("sync_id", (syncId != null && !syncId.isEmpty()) ? syncId : java.util.UUID.randomUUID().toString());
                zombies.add(z);
            }
            try (PreparedStatement ins = connection.prepareStatement("INSERT INTO deleted_stock (sync_id, item, quantity) VALUES (?, ?, ?)");
                 PreparedStatement del = connection.prepareStatement("DELETE FROM stock WHERE id = ?")) {
                for (Map<String, String> z : zombies) {
                    ins.setString(1, z.get("sync_id"));
                    ins.setString(2, z.get("item"));
                    ins.setString(3, z.get("quantity"));
                    ins.executeUpdate();

                    del.setInt(1, Integer.parseInt(z.get("id")));
                    del.executeUpdate();
                    System.out.println("CLEANUP ZOMBIE STOCK (Desktop): Deleted orphan stock '" + z.get("item") + " (" + z.get("quantity") + ")'");
                }
            }
        } catch (SQLException e) {
            System.err.println("Error cleaning up zombie stock: " + e.getMessage());
        }
    }

    public Connection getConnection() {
        return connection;
    }

    public void close() {
        try {
            if (connection != null)
                connection.close();
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

    // --- CONFLICT MERGING HELPERS ---

    public List<DirtyRecord> getDirtyRecords(String table) {
        List<DirtyRecord> records = new ArrayList<>();
        String sql = "SELECT * FROM " + table + " WHERE is_edited = 1";
        try (Statement stmt = connection.createStatement(); ResultSet rs = stmt.executeQuery(sql)) {
            ResultSetMetaData meta = rs.getMetaData();
            int colCount = meta.getColumnCount();
            while (rs.next()) {
                Map<String, Object> data = new HashMap<>();
                for (int i = 1; i <= colCount; i++) {
                    data.put(meta.getColumnName(i), rs.getObject(i));
                }
                records.add(new DirtyRecord(data));
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return records;
    }

    public List<Map<String, String>> getDeletedStock() {
        List<Map<String, String>> deleted = new ArrayList<>();
        try (Statement stmt = connection.createStatement();
                ResultSet rs = stmt.executeQuery("SELECT item, quantity FROM deleted_stock")) {
            while (rs.next()) {
                Map<String, String> m = new HashMap<>();
                m.put("item", rs.getString("item"));
                m.put("quantity", rs.getString("quantity"));
                deleted.add(m);
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return deleted;
    }

    public List<Map<String, String>> getDeletedHistory() {
        List<Map<String, String>> deleted = new ArrayList<>();
        String sql = "SELECT customer, item, amount, date FROM deleted_history";
        try (Statement stmt = connection.createStatement(); ResultSet rs = stmt.executeQuery(sql)) {
            while (rs.next()) {
                Map<String, String> m = new HashMap<>();
                m.put("customer", rs.getString("customer"));
                m.put("item", rs.getString("item"));
                m.put("amount", rs.getString("amount"));
                m.put("date", rs.getString("date"));
                deleted.add(m);
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return deleted;
    }

    public static class DirtyRecord {
        public final Map<String, Object> data;

        public DirtyRecord(Map<String, Object> data) {
            this.data = data;
        }
    }

    public boolean isStockDeleted(String item, String quantity) {
        return isStockDeleted(item, quantity, null);
    }

    public boolean isStockDeleted(String item, String quantity, String syncId) {
        if (syncId != null && !syncId.isEmpty()) {
            String sqlSync = "SELECT 1 FROM deleted_stock WHERE sync_id = ?";
            try (PreparedStatement pstmt = connection.prepareStatement(sqlSync)) {
                pstmt.setString(1, syncId);
                try (ResultSet rs = pstmt.executeQuery()) {
                    if (rs.next()) return true;
                }
            } catch (SQLException ignored) {}
        }
        String sql = "SELECT 1 FROM deleted_stock WHERE item = ? AND quantity = ?";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, item);
            pstmt.setString(2, quantity);
            try (ResultSet rs = pstmt.executeQuery()) {
                return rs.next();
            }
        } catch (SQLException e) {
            return false;
        }
    }

    public boolean isSaleDeleted(String customer, String item, Object amount, String date) {
        return isSaleDeleted(customer, item, amount, date, null);
    }

    public boolean isSaleDeleted(String customer, String item, Object amount, String date, String syncId) {
        if (syncId != null && !syncId.isEmpty()) {
            String sqlSync = "SELECT 1 FROM deleted_history WHERE sync_id = ?";
            try (PreparedStatement pstmt = connection.prepareStatement(sqlSync)) {
                pstmt.setString(1, syncId);
                try (ResultSet rs = pstmt.executeQuery()) {
                    return rs.next();
                }
            } catch (SQLException ignored) {
                return false;
            }
        }
        String sql = "SELECT 1 FROM deleted_history WHERE item = ? AND date = ? AND (customer = ? OR customer IS NULL OR customer = '' OR ? IS NULL OR ? = '')";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, item != null ? item : "");
            pstmt.setString(2, date != null ? date : "");
            pstmt.setString(3, customer != null ? customer : "");
            pstmt.setString(4, customer != null ? customer : "");
            pstmt.setString(5, customer != null ? customer : "");
            try (ResultSet rs = pstmt.executeQuery()) {
                return rs.next();
            }
        } catch (SQLException e) {
            return false;
        }
    }

    public void applyDirtyRecord(String table, DirtyRecord record) {
        // Create a copy and remove 'id' to let the new database assign a local ID
        Map<String, Object> data = new HashMap<>(record.data);
        data.remove("id");

        // TOMBSTONE CHECK: Don't restore if deleted in the cloud (other device)
        if ("stock".equals(table)) {
            if (isStockDeleted((String) data.get("item"), (String) data.get("quantity"))) {
                System.out.println("SYNC: Skipping restore of " + data.get("item") + " - Deleted in cloud.");
                return;
            }
        }
        if ("sales".equals(table)) {
            if (isSaleDeleted((String) data.get("customer"), (String) data.get("item"), data.get("amount"),
                    (String) data.get("date"))) {
                System.out.println("SYNC: Skipping restore of sale " + data.get("item") + " - Deleted in cloud.");
                return;
            }
        }

        if ("stock".equals(table)) {
            // Check for existing by Name + Size
            String checkSql = "SELECT id FROM stock WHERE item = ? AND quantity = ?";
            try (PreparedStatement checkStmt = connection.prepareStatement(checkSql)) {
                checkStmt.setString(1, (String) data.get("item"));
                checkStmt.setString(2, (String) data.get("quantity"));
                try (ResultSet rs = checkStmt.executeQuery()) {
                    if (rs.next()) {
                        int existingId = rs.getInt("id");
                        StringBuilder sets = new StringBuilder();
                        List<Object> args = new ArrayList<>();
                        data.forEach((k, v) -> {
                            if (sets.length() > 0)
                                sets.append(", ");
                            sets.append(k).append(" = ?");
                            args.add(v);
                        });
                        String updateSql = "UPDATE stock SET " + sets + " WHERE id = ?";
                        try (PreparedStatement upstmt = connection.prepareStatement(updateSql)) {
                            for (int i = 0; i < args.size(); i++)
                                upstmt.setObject(i + 1, args.get(i));
                            upstmt.setInt(args.size() + 1, existingId);
                            upstmt.executeUpdate();
                            return;
                        }
                    }
                }
            } catch (SQLException e) {
                e.printStackTrace();
            }
        }

        if ("sales".equals(table)) {
            // Check for identical to avoid duplicates
            String checkSql = "SELECT id FROM sales WHERE customer = ? AND item = ? AND amount = ? AND date = ?";
            try (PreparedStatement checkStmt = connection.prepareStatement(checkSql)) {
                checkStmt.setString(1, (String) data.get("customer"));
                checkStmt.setString(2, (String) data.get("item"));
                checkStmt.setObject(3, data.get("amount"));
                checkStmt.setString(4, (String) data.get("date"));
                try (ResultSet rs = checkStmt.executeQuery()) {
                    if (rs.next())
                        return; // Already exists
                }
            } catch (SQLException e) {
                e.printStackTrace();
            }
        }

        // Standard Insert
        StringBuilder cols = new StringBuilder();
        StringBuilder vals = new StringBuilder();
        List<Object> args = new ArrayList<>();

        data.forEach((k, v) -> {
            if (cols.length() > 0) {
                cols.append(",");
                vals.append(",");
            }
            cols.append(k);
            vals.append("?");
            args.add(v);
        });

        String sql = "INSERT INTO " + table + " (" + cols + ") VALUES (" + vals + ")";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            for (int i = 0; i < args.size(); i++) {
                pstmt.setObject(i + 1, args.get(i));
            }
            pstmt.executeUpdate();
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

    public void applyStockDeletion(String item, String quantity) {
        try (PreparedStatement pstmt = connection
                .prepareStatement("DELETE FROM stock WHERE item = ? AND quantity = ?")) {
            pstmt.setString(1, item);
            pstmt.setString(2, quantity);
            pstmt.executeUpdate();
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

    public void applyHistoryDeletion(String customer, String item, String amount, String date) {
        String sql = "DELETE FROM sales WHERE customer = ? AND item = ? AND amount = ? AND date = ?";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, customer);
            pstmt.setString(2, item);
            pstmt.setString(3, amount);
            pstmt.setString(4, date);
            pstmt.executeUpdate();
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

    public void clearDirtyFlags() {
        try (Statement stmt = connection.createStatement()) {
            stmt.execute("UPDATE stock SET is_edited = 0");
            stmt.execute("UPDATE sales SET is_edited = 0");
            stmt.execute("DELETE FROM deleted_stock");
            stmt.execute("DELETE FROM deleted_history");
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

    public int getPendingSyncCount() {
        int count = 0;
        try (Statement stmt = connection.createStatement()) {
            try (ResultSet rs = stmt.executeQuery("SELECT COUNT(*) FROM stock WHERE is_edited = 1")) {
                if (rs.next()) count += rs.getInt(1);
            }
            try (ResultSet rs = stmt.executeQuery("SELECT COUNT(*) FROM sales WHERE is_edited = 1")) {
                if (rs.next()) count += rs.getInt(1);
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return count;
    }

    public com.google.gson.JsonArray getDirtyStock() {
        com.google.gson.JsonArray array = new com.google.gson.JsonArray();
        String sql = "SELECT sync_id, item, quantity, unit, price, cost_price, base_quantity, available_pieces, device_source, date FROM stock WHERE is_edited = 1";
        try (Statement stmt = connection.createStatement(); ResultSet rs = stmt.executeQuery(sql)) {
            while (rs.next()) {
                com.google.gson.JsonObject obj = new com.google.gson.JsonObject();
                String syncId = rs.getString("sync_id");
                if (syncId == null || syncId.isEmpty()) {
                    syncId = java.util.UUID.randomUUID().toString();
                }
                obj.addProperty("sync_id", syncId);
                obj.addProperty("item", rs.getString("item"));
                obj.addProperty("quantity", rs.getString("quantity"));
                obj.addProperty("unit", rs.getString("unit"));
                obj.addProperty("price", rs.getString("price"));
                obj.addProperty("cost_price", rs.getDouble("cost_price"));
                obj.addProperty("base_quantity", rs.getDouble("base_quantity"));
                obj.addProperty("available_pieces", rs.getDouble("available_pieces"));
                obj.addProperty("device_source", rs.getString("device_source"));
                obj.addProperty("date", rs.getString("date"));
                array.add(obj);
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return array;
    }

    public com.google.gson.JsonArray getDirtySales() {
        com.google.gson.JsonArray array = new com.google.gson.JsonArray();
        String sql = "SELECT sync_id, customer, item, quantity, unit, price, cost_price, base_quantity, amount, type, date, is_debt, is_paid, paid_amount, receipt_id, device_source, created_at FROM sales WHERE is_edited = 1";
        try (Statement stmt = connection.createStatement(); ResultSet rs = stmt.executeQuery(sql)) {
            while (rs.next()) {
                com.google.gson.JsonObject obj = new com.google.gson.JsonObject();
                String syncId = rs.getString("sync_id");
                if (syncId == null || syncId.isEmpty()) {
                    syncId = java.util.UUID.randomUUID().toString();
                }
                obj.addProperty("sync_id", syncId);
                obj.addProperty("customer", rs.getString("customer"));
                obj.addProperty("item", rs.getString("item"));
                obj.addProperty("quantity", rs.getString("quantity"));
                obj.addProperty("unit", rs.getString("unit"));
                obj.addProperty("price", rs.getString("price"));
                obj.addProperty("cost_price", rs.getDouble("cost_price"));
                obj.addProperty("base_quantity", rs.getDouble("base_quantity"));
                obj.addProperty("amount", rs.getString("amount"));
                obj.addProperty("type", rs.getString("type"));
                obj.addProperty("date", rs.getString("date"));
                obj.addProperty("is_debt", rs.getInt("is_debt"));
                obj.addProperty("is_paid", rs.getInt("is_paid"));
                obj.addProperty("paid_amount", rs.getDouble("paid_amount"));
                obj.addProperty("receipt_id", rs.getString("receipt_id"));
                obj.addProperty("device_source", rs.getString("device_source"));
                obj.addProperty("created_at", rs.getString("created_at"));
                array.add(obj);
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return array;
    }

    public com.google.gson.JsonArray getDirtyDeletedStock() {
        com.google.gson.JsonArray array = new com.google.gson.JsonArray();
        String sql = "SELECT sync_id, item, quantity, deleted_at FROM deleted_stock WHERE sync_id IS NOT NULL";
        try (Statement stmt = connection.createStatement(); ResultSet rs = stmt.executeQuery(sql)) {
            while (rs.next()) {
                com.google.gson.JsonObject obj = new com.google.gson.JsonObject();
                obj.addProperty("sync_id", rs.getString("sync_id"));
                obj.addProperty("item", rs.getString("item"));
                obj.addProperty("quantity", rs.getString("quantity"));
                obj.addProperty("deleted_at", rs.getString("deleted_at"));
                array.add(obj);
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return array;
    }

    public com.google.gson.JsonArray getDirtyDeletedHistory() {
        com.google.gson.JsonArray array = new com.google.gson.JsonArray();
        String sql = "SELECT sync_id, customer, item, amount, date, deleted_at FROM deleted_history";
        try (Statement stmt = connection.createStatement(); ResultSet rs = stmt.executeQuery(sql)) {
            while (rs.next()) {
                com.google.gson.JsonObject obj = new com.google.gson.JsonObject();
                String sId = rs.getString("sync_id");
                obj.addProperty("sync_id", sId != null ? sId : "");
                obj.addProperty("customer", rs.getString("customer") != null ? rs.getString("customer") : "");
                obj.addProperty("item", rs.getString("item") != null ? rs.getString("item") : "");
                obj.addProperty("amount", rs.getString("amount") != null ? rs.getString("amount") : "");
                obj.addProperty("date", rs.getString("date") != null ? rs.getString("date") : "");
                obj.addProperty("deleted_at", rs.getString("deleted_at") != null ? rs.getString("deleted_at") : "");
                array.add(obj);
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return array;
    }

    /**
     * Pull cloud stock into local DB.
     * @param forceAcceptPieces true on manual/full sync to correct drift.
     *   During incremental background sync, pass false so delta merge handles counts.
     */
    public void upsertCloudStock(com.google.gson.JsonArray cloudStock, boolean forceAcceptPieces) {
        if (cloudStock == null || cloudStock.size() == 0)
            return;
            
        String updateMetaOnly = "UPDATE stock SET sync_id=?, supplier=?, item=?, quantity=?, unit=?, price=?, device_source=?, date=? WHERE id=?";
        String updateWithPieces = "UPDATE stock SET sync_id=?, supplier=?, item=?, quantity=?, unit=?, price=?, available_pieces=?, device_source=?, date=?, is_edited=0 WHERE id=?";
        String insertSql = "INSERT INTO stock (sync_id, supplier, item, quantity, unit, price, available_pieces, device_source, date, is_edited) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0)";
        
        try (PreparedStatement checkStmt = connection.prepareStatement("SELECT id, is_edited, price, item, quantity, unit FROM stock WHERE sync_id = ?");
             PreparedStatement checkByItemQtyStmt = connection.prepareStatement("SELECT id, is_edited, price, item, quantity, unit FROM stock WHERE item = ? AND quantity = ?");
             PreparedStatement updateMetaStmt = connection.prepareStatement(updateMetaOnly);
             PreparedStatement updateFullStmt = connection.prepareStatement(updateWithPieces);
             PreparedStatement insertStmt = connection.prepareStatement(insertSql)) {
             
            for (com.google.gson.JsonElement el : cloudStock) {
                com.google.gson.JsonObject obj = el.getAsJsonObject();
                String syncId = obj.has("sync_id") && !obj.get("sync_id").isJsonNull() ? obj.get("sync_id").getAsString() : null;
                String supplier = obj.has("supplier") && !obj.get("supplier").isJsonNull() ? obj.get("supplier").getAsString() : "Unknown";
                String item = obj.has("item") && !obj.get("item").isJsonNull() ? obj.get("item").getAsString() : "Unknown";
                String quantity = obj.has("quantity") && !obj.get("quantity").isJsonNull() ? obj.get("quantity").getAsString() : "0";

                if (isStockDeleted(item, quantity, syncId)) {
                    System.out.println("SYNC: Skipping restore of stock " + item + " (" + quantity + ") - Deleted in tombstone.");
                    continue;
                }
                String unit = obj.has("unit") && !obj.get("unit").isJsonNull() ? obj.get("unit").getAsString() : "";
                String price = obj.has("price") && !obj.get("price").isJsonNull() ? obj.get("price").getAsString() : "0";
                double availablePieces = obj.has("available_pieces") && !obj.get("available_pieces").isJsonNull() ? obj.get("available_pieces").getAsDouble() : 0;
                String deviceSource = obj.has("device_source") && !obj.get("device_source").isJsonNull() ? obj.get("device_source").getAsString() : "Cloud";
                String date = obj.has("date") && !obj.get("date").isJsonNull() ? obj.get("date").getAsString() : LocalDate.now().toString();

                checkStmt.setString(1, syncId);
                ResultSet rs = checkStmt.executeQuery();
                boolean exists = rs.next();
                
                int localId = -1;
                boolean localIsDirty = false;
                double oldPrice = 0.0;
                String localItem = item;
                String localQuantity = quantity;
                String localUnit = unit;

                if (exists) {
                    localId = rs.getInt("id");
                    localIsDirty = rs.getInt("is_edited") == 1;
                    oldPrice = rs.getDouble("price");
                    localItem = rs.getString("item");
                    localQuantity = rs.getString("quantity");
                    localUnit = rs.getString("unit");
                } else {
                    // Fallback to name + size to prevent UNIQUE constraint violation
                    checkByItemQtyStmt.setString(1, item);
                    checkByItemQtyStmt.setString(2, quantity);
                    try (ResultSet rs2 = checkByItemQtyStmt.executeQuery()) {
                        if (rs2.next()) {
                            exists = true;
                            localId = rs2.getInt("id");
                            localIsDirty = rs2.getInt("is_edited") == 1;
                            oldPrice = rs2.getDouble("price");
                            localItem = rs2.getString("item");
                            localQuantity = rs2.getString("quantity");
                            localUnit = rs2.getString("unit");
                        }
                    }
                }
                
                if (exists) {
                    double newPriceVal = 0.0;
                    try {
                        newPriceVal = Double.parseDouble(price);
                    } catch (NumberFormatException ignored) {}
                    
                    if (Math.abs(oldPrice - newPriceVal) > 0.0001 && !"Desktop".equals(deviceSource)) {
                        double multiplier = getUnitMultiplier(localUnit, localQuantity, localUnit);
                        double oldUnitPrice = oldPrice * multiplier;
                        double newUnitPrice = newPriceVal * multiplier;
                        
                        addNotification(
                            String.format("Price updated for %s (%s): UGX %,.0f ➔ UGX %,.0f per %s", 
                                localItem, localQuantity, oldUnitPrice, newUnitPrice, localUnit),
                            deviceSource
                        );
                    }

                    if (!localIsDirty) {
                        // Check if local pieces is lower than cloud pieces due to local sales
                        double localPieces = 0.0;
                        try (PreparedStatement getPiecesPstmt = connection.prepareStatement("SELECT available_pieces FROM stock WHERE id = ?")) {
                            getPiecesPstmt.setInt(1, localId);
                            try (ResultSet rPieces = getPiecesPstmt.executeQuery()) {
                                if (rPieces.next()) {
                                    localPieces = rPieces.getDouble("available_pieces");
                                }
                            }
                        } catch (Exception ignored) {}

                        // If local has fewer pieces than cloud, check if a sale was made today locally
                        double piecesToUse = availablePieces;
                        if (localPieces < availablePieces) {
                            try (PreparedStatement checkSalePstmt = connection.prepareStatement("SELECT 1 FROM sales WHERE item = ? AND date = ? LIMIT 1")) {
                                checkSalePstmt.setString(1, localItem);
                                checkSalePstmt.setString(2, LocalDate.now().toString());
                                try (ResultSet rSale = checkSalePstmt.executeQuery()) {
                                    if (rSale.next()) {
                                        // Keep lower local pieces to prevent sold pieces from reappearing
                                        piecesToUse = localPieces;
                                    }
                                }
                            } catch (Exception ignored) {}
                        }

                        // Accept cloud available_pieces to sync stock changes across devices
                        updateFullStmt.setString(1, syncId);
                        updateFullStmt.setString(2, supplier);
                        updateFullStmt.setString(3, item);
                        updateFullStmt.setString(4, quantity);
                        updateFullStmt.setString(5, unit);
                        updateFullStmt.setString(6, price);
                        updateFullStmt.setDouble(7, piecesToUse);
                        updateFullStmt.setString(8, deviceSource);
                        updateFullStmt.setString(9, date);
                        updateFullStmt.setInt(10, localId);
                        updateFullStmt.executeUpdate();
                    } else {
                        // Local has unsynced offline edits: preserve local metadata until upload
                        updateMetaStmt.setString(1, syncId);
                        updateMetaStmt.setString(2, supplier);
                        updateMetaStmt.setString(3, item);
                        updateMetaStmt.setString(4, quantity);
                        updateMetaStmt.setString(5, unit);
                        updateMetaStmt.setString(6, price);
                        updateMetaStmt.setString(7, deviceSource);
                        updateMetaStmt.setString(8, date);
                        updateMetaStmt.setInt(9, localId);
                        updateMetaStmt.executeUpdate();
                    }
                } else {
                    insertStmt.setString(1, syncId);
                    insertStmt.setString(2, supplier);
                    insertStmt.setString(3, item);
                    insertStmt.setString(4, quantity);
                    insertStmt.setString(5, unit);
                    insertStmt.setString(6, price);
                    insertStmt.setDouble(7, availablePieces);
                    insertStmt.setString(8, deviceSource);
                    insertStmt.setString(9, date);
                    insertStmt.executeUpdate();
                }
            }

            if (forceAcceptPieces) {
                Set<String> cloudSyncIds = new HashSet<>();
                Set<String> cloudItemKeys = new HashSet<>();
                for (com.google.gson.JsonElement el : cloudStock) {
                    com.google.gson.JsonObject o = el.getAsJsonObject();
                    if (o.has("sync_id") && !o.get("sync_id").isJsonNull()) cloudSyncIds.add(o.get("sync_id").getAsString());
                    String item = o.has("item") && !o.get("item").isJsonNull() ? o.get("item").getAsString() : "";
                    String quantity = o.has("quantity") && !o.get("quantity").isJsonNull() ? o.get("quantity").getAsString() : "";
                    cloudItemKeys.add(item + "____" + quantity);
                }

                try (Statement stmt = connection.createStatement();
                     ResultSet rs = stmt.executeQuery("SELECT id, sync_id, item, quantity, is_edited FROM stock")) {
                    List<Integer> idsToDelete = new ArrayList<>();
                    while (rs.next()) {
                        int id = rs.getInt("id");
                        String syncId = rs.getString("sync_id");
                        String itemKey = rs.getString("item") + "____" + rs.getString("quantity");
                        boolean isEdited = rs.getInt("is_edited") == 1;

                        boolean inCloud = (syncId != null && cloudSyncIds.contains(syncId)) || cloudItemKeys.contains(itemKey);
                        if (!inCloud && !isEdited) {
                            idsToDelete.add(id);
                        }
                    }
                    try (PreparedStatement delStmt = connection.prepareStatement("DELETE FROM stock WHERE id = ?")) {
                        for (int id : idsToDelete) {
                            delStmt.setInt(1, id);
                            delStmt.executeUpdate();
                        }
                    }
                }
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

    public void upsertCloudSales(com.google.gson.JsonArray cloudSales, boolean isIncremental) {
        if (cloudSales == null || (cloudSales.size() == 0 && isIncremental))
            return;
        String updateSql = "UPDATE sales SET customer=?, item=?, quantity=?, unit=?, price=?, cost_price=?, base_quantity=?, amount=?, type=?, date=?, is_debt=?, is_paid=?, paid_amount=?, receipt_id=?, device_source=?, is_edited=0 WHERE sync_id=?";
        String insertSql = "INSERT INTO sales (sync_id, customer, item, quantity, unit, price, cost_price, base_quantity, amount, type, date, is_debt, is_paid, paid_amount, receipt_id, device_source, created_at, is_edited) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0)";
        
        try (PreparedStatement checkStmt = connection.prepareStatement("SELECT id, paid_amount FROM sales WHERE sync_id = ?");
             PreparedStatement updateStmt = connection.prepareStatement(updateSql);
             PreparedStatement insertStmt = connection.prepareStatement(insertSql)) {
             
            for (com.google.gson.JsonElement el : cloudSales) {
                com.google.gson.JsonObject obj = el.getAsJsonObject();
                String syncId = obj.get("sync_id").getAsString();
                
                // Check if this is a brand new entry from the cloud
                boolean isNew = false;
                double localPaidAmount = 0.0;
                int localId = -1;
                checkStmt.setString(1, syncId);
                try (ResultSet checkRs = checkStmt.executeQuery()) {
                    if (!checkRs.next()) {
                        isNew = true;
                    } else {
                        localId = checkRs.getInt("id");
                        localPaidAmount = checkRs.getDouble("paid_amount");
                    }
                }
                
                String customer = obj.has("customer") && !obj.get("customer").isJsonNull() ? obj.get("customer").getAsString() : "";
                String item = obj.has("item") && !obj.get("item").isJsonNull() ? obj.get("item").getAsString() : "Unknown";
                String quantity = obj.has("quantity") && !obj.get("quantity").isJsonNull() ? obj.get("quantity").getAsString() : "0";
                String unit = obj.has("unit") && !obj.get("unit").isJsonNull() ? obj.get("unit").getAsString() : "";
                String price = obj.has("price") && !obj.get("price").isJsonNull() ? obj.get("price").getAsString() : "0";
                double costPrice = obj.has("cost_price") && !obj.get("cost_price").isJsonNull() ? obj.get("cost_price").getAsDouble() : 0;
                double baseQuantity = obj.has("base_quantity") && !obj.get("base_quantity").isJsonNull() ? obj.get("base_quantity").getAsDouble() : 0;
                String amount = obj.has("amount") && !obj.get("amount").isJsonNull() ? obj.get("amount").getAsString() : "0";
                String type = obj.has("type") && !obj.get("type").isJsonNull() ? obj.get("type").getAsString() : "";
                String date = obj.has("date") && !obj.get("date").isJsonNull() ? obj.get("date").getAsString() : LocalDate.now().toString();

                if (isNew && isSaleDeleted(customer, item, amount, date, syncId)) {
                    System.out.println("SYNC: Skipping restore of sale " + item + " (" + customer + ") - Deleted in tombstone.");
                    continue;
                }
                
                int isDebt = 0;
                if (obj.has("is_debt") && !obj.get("is_debt").isJsonNull()) {
                    com.google.gson.JsonElement e = obj.get("is_debt");
                    isDebt = (e.isJsonPrimitive() && e.getAsJsonPrimitive().isBoolean()) ? (e.getAsBoolean() ? 1 : 0) : e.getAsInt();
                }
                
                int isPaid = 0;
                if (obj.has("is_paid") && !obj.get("is_paid").isJsonNull()) {
                    com.google.gson.JsonElement e = obj.get("is_paid");
                    isPaid = (e.isJsonPrimitive() && e.getAsJsonPrimitive().isBoolean()) ? (e.getAsBoolean() ? 1 : 0) : e.getAsInt();
                }
                
                double cloudPaidAmount = obj.has("paid_amount") && !obj.get("paid_amount").isJsonNull() ? obj.get("paid_amount").getAsDouble() : 0.0;
                String receiptId = obj.has("receipt_id") && !obj.get("receipt_id").isJsonNull() ? obj.get("receipt_id").getAsString() : null;
                if (receiptId != null && (receiptId.isEmpty() || "null".equalsIgnoreCase(receiptId))) {
                    receiptId = null;
                }
                String deviceSource = obj.has("device_source") && !obj.get("device_source").isJsonNull() ? obj.get("device_source").getAsString() : "Cloud";
                String createdAt = obj.has("created_at") && !obj.get("created_at").isJsonNull() ? obj.get("created_at").getAsString() : java.time.LocalDateTime.now().toString();

                if (isNew) {
                    insertStmt.setString(1, syncId);
                    insertStmt.setString(2, customer);
                    insertStmt.setString(3, item);
                    insertStmt.setString(4, quantity);
                    insertStmt.setString(5, unit);
                    insertStmt.setString(6, price);
                    insertStmt.setDouble(7, costPrice);
                    insertStmt.setDouble(8, baseQuantity);
                    insertStmt.setString(9, amount);
                    insertStmt.setString(10, type);
                    insertStmt.setString(11, date);
                    insertStmt.setInt(12, isDebt);
                    insertStmt.setInt(13, isPaid);
                    insertStmt.setDouble(14, cloudPaidAmount);
                    insertStmt.setString(15, receiptId);
                    insertStmt.setString(16, deviceSource);
                    insertStmt.setString(17, createdAt);
                    insertStmt.executeUpdate();
                } else {
                    updateStmt.setString(1, customer);
                    updateStmt.setString(2, item);
                    updateStmt.setString(3, quantity);
                    updateStmt.setString(4, unit);
                    updateStmt.setString(5, price);
                    updateStmt.setDouble(6, costPrice);
                    updateStmt.setDouble(7, baseQuantity);
                    updateStmt.setString(8, amount);
                    updateStmt.setString(9, type);
                    updateStmt.setString(10, date);
                    updateStmt.setInt(11, isDebt);
                    updateStmt.setInt(12, isPaid);
                    updateStmt.setDouble(13, cloudPaidAmount);
                    updateStmt.setString(14, receiptId);
                    updateStmt.setString(15, deviceSource);
                    updateStmt.setString(16, syncId);
                    updateStmt.executeUpdate();
                }
                
                if (isNew) {
                    boolean isRecent = false;
                    if (createdAt != null && !createdAt.isEmpty()) {
                        try {
                            java.time.Instant rowTime = java.time.Instant.parse(createdAt);
                            long ageSec = java.time.Duration.between(rowTime, java.time.Instant.now()).getSeconds();
                            if (Math.abs(ageSec) < 60) {
                                isRecent = true;
                            }
                        } catch (Exception ignored) {}
                    }

                    if ("Mobile".equals(deviceSource) && isRecent) {
                        if ("NEW STOCK".equals(type)) {
                            addNotification("NEW STOCK: " + item + " has been stocked", "Mobile");
                        } else {
                            addNotification("Sale recorded for " + customer + ": " + item + " (UGX " + amount + ")", "Mobile");
                        }
                    }

                    // Apply Event-Sourced Delta Merge whenever new sales arrive from ANY device in incremental mode
                    if (isIncremental && isNew && !item.isEmpty() && !quantity.isEmpty() && !unit.isEmpty()) {
                        double multiplier = getUnitMultiplier(unit, quantity, unit);
                        double count = extractNumericValue(unit) * multiplier;

                        if ("NEW STOCK".equals(type)) {
                            // Update supplier only
                            String updateStock = "UPDATE stock SET supplier = ? WHERE item = ? AND quantity = ?";
                            try (PreparedStatement uStmt = connection.prepareStatement(updateStock)) {
                                uStmt.setString(1, customer);
                                uStmt.setString(2, item);
                                uStmt.setString(3, quantity);
                                uStmt.executeUpdate();
                            }
                        } else if (!type.isEmpty() && !"Debt Payment".equals(type) && !"Payment".equals(type)) { 
                            // Regular sales and Debts subtract from local stock balance (CRDT Delta)
                            String updateStock = "UPDATE stock SET available_pieces = available_pieces - ? WHERE item = ? AND quantity = ?";
                            try (PreparedStatement uStmt = connection.prepareStatement(updateStock)) {
                                uStmt.setDouble(1, count);
                                uStmt.setString(2, item);
                                uStmt.setString(3, quantity);
                                uStmt.executeUpdate();
                            }

                            // Check for Negative Stock Discrepancy & notify manager
                            String checkDiscrepancy = "SELECT available_pieces FROM stock WHERE item = ? AND quantity = ?";
                            try (PreparedStatement cStmt = connection.prepareStatement(checkDiscrepancy)) {
                                cStmt.setString(1, item);
                                cStmt.setString(2, quantity);
                                try (ResultSet rs = cStmt.executeQuery()) {
                                    if (rs.next() && rs.getDouble("available_pieces") < 0) {
                                        addNotification(
                                            String.format("⚠️ Negative Stock Discrepancy: %s (%s) balance is %s pieces.", 
                                                item, quantity, String.format("%.0f", rs.getDouble("available_pieces"))),
                                            "System"
                                        );
                                    }
                                }
                            } catch (SQLException ignored) {}
                        }
                    }
                } else {
                    if (cloudPaidAmount > localPaidAmount) {
                        double diff = cloudPaidAmount - localPaidAmount;
                        addNotification("Payment of UGX " + (int) Math.round(diff) + " received for " + customer, "Mobile");
                        if (localId != -1) {
                            try (PreparedStatement payStmt = connection.prepareStatement(
                                    "INSERT INTO debt_payments(sale_id, amount_paid, payment_date, sync_id) VALUES(?, ?, ?, ?)")) {
                                payStmt.setInt(1, localId);
                                payStmt.setDouble(2, diff);
                                payStmt.setString(3, LocalDate.now().toString());
                                payStmt.setString(4, java.util.UUID.randomUUID().toString());
                                payStmt.executeUpdate();
                            } catch (SQLException e) {
                                System.err.println("Failed to insert synced debt payment log: " + e.getMessage());
                            }
                        }
                    }
                }
            }

            if (!isIncremental) {
                Set<String> cloudSyncIds = new HashSet<>();
                Set<String> cloudSaleKeys = new HashSet<>();
                for (com.google.gson.JsonElement el : cloudSales) {
                    com.google.gson.JsonObject o = el.getAsJsonObject();
                    if (o.has("sync_id") && !o.get("sync_id").isJsonNull()) {
                        cloudSyncIds.add(o.get("sync_id").getAsString());
                    }
                    String cust = o.has("customer") && !o.get("customer").isJsonNull() ? o.get("customer").getAsString() : "";
                    String item = o.has("item") && !o.get("item").isJsonNull() ? o.get("item").getAsString() : "";
                    String date = o.has("date") && !o.get("date").isJsonNull() ? o.get("date").getAsString() : "";
                    String amt = o.has("amount") && !o.get("amount").isJsonNull() ? o.get("amount").getAsString() : "";
                    cloudSaleKeys.add(cust + "____" + item + "____" + date + "____" + amt);
                }

                try (Statement stmt = connection.createStatement();
                     ResultSet rs = stmt.executeQuery("SELECT id, sync_id, customer, item, date, amount, is_edited, created_at FROM sales")) {
                    List<Integer> idsToDelete = new ArrayList<>();
                    while (rs.next()) {
                        int id = rs.getInt("id");
                        String syncId = rs.getString("sync_id");
                        String key = rs.getString("customer") + "____" + rs.getString("item") + "____" + rs.getString("date") + "____" + rs.getString("amount");
                        boolean isEdited = rs.getInt("is_edited") == 1;

                        boolean inCloud = (syncId != null && cloudSyncIds.contains(syncId)) || cloudSaleKeys.contains(key);
                        if (!inCloud) {
                            boolean isRecentLocalDraft = false;
                            if (isEdited && (syncId == null || syncId.isEmpty())) {
                                String createdAt = rs.getString("created_at");
                                if (createdAt != null && !createdAt.isEmpty()) {
                                    try {
                                        java.time.Instant rowTime = java.time.Instant.parse(createdAt);
                                        long ageSec = java.time.Duration.between(rowTime, java.time.Instant.now()).getSeconds();
                                        if (Math.abs(ageSec) < 600) {
                                            isRecentLocalDraft = true;
                                        }
                                    } catch (Exception ignored) {}
                                }
                            }
                            if (!isRecentLocalDraft) {
                                idsToDelete.add(id);
                            }
                        }
                    }
                    try (PreparedStatement delStmt = connection.prepareStatement("DELETE FROM sales WHERE id = ?")) {
                        for (int id : idsToDelete) {
                            delStmt.setInt(1, id);
                            delStmt.executeUpdate();
                        }
                    }
                }
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

    public void processCloudDeletions(com.google.gson.JsonArray deletedStock, com.google.gson.JsonArray deletedSales) {
        if (deletedStock != null && deletedStock.size() > 0) {
            String sql = "DELETE FROM stock WHERE sync_id = ?";
            try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
                for (com.google.gson.JsonElement el : deletedStock) {
                    pstmt.setString(1, el.getAsJsonObject().get("sync_id").getAsString());
                    pstmt.addBatch();
                }
                pstmt.executeBatch();
            } catch (SQLException e) {
                e.printStackTrace();
            }
        }
        if (deletedSales != null && deletedSales.size() > 0) {
            String sql = "DELETE FROM sales WHERE sync_id = ?";
            try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
                for (com.google.gson.JsonElement el : deletedSales) {
                    pstmt.setString(1, el.getAsJsonObject().get("sync_id").getAsString());
                    pstmt.addBatch();
                }
                pstmt.executeBatch();
            } catch (SQLException e) {
                e.printStackTrace();
            }
        }
    }

    public double getTotalOutstandingDebt() {
        String sql = "SELECT SUM(amount - COALESCE(paid_amount, 0)) FROM sales WHERE is_debt = 1 AND is_paid = 0 AND customer != 'Walk-in Customer'";
        try (Statement stmt = connection.createStatement();
                ResultSet rs = stmt.executeQuery(sql)) {
            if (rs.next())
                return rs.getDouble(1);
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return 0;
    }

    public int getDebtorCount() {
        String sql = "SELECT COUNT(DISTINCT customer) FROM sales WHERE is_debt = 1 AND is_paid = 0 AND customer != 'Walk-in Customer'";
        try (Statement stmt = connection.createStatement();
                ResultSet rs = stmt.executeQuery(sql)) {
            if (rs.next())
                return rs.getInt(1);
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return 0;
    }

    public double getDebtCollectedToday() {
        String today = LocalDate.now().toString();
        String sql = "SELECT SUM(amount_paid) FROM debt_payments WHERE payment_date = ?";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, today);
            ResultSet rs = pstmt.executeQuery();
            if (rs.next())
                return rs.getDouble(1);
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return 0;
    }

    public ObservableList<com.meto.inventory.models.DebtPaymentLog> getRecentDebtPayments() {
        ObservableList<com.meto.inventory.models.DebtPaymentLog> logs = FXCollections.observableArrayList();
        String sql = "SELECT p.amount_paid, p.payment_date, s.customer, s.item " +
                "FROM debt_payments p JOIN sales s ON p.sale_id = s.id " +
                "ORDER BY p.created_at DESC LIMIT 50";
        try (Statement stmt = connection.createStatement();
                ResultSet rs = stmt.executeQuery(sql)) {
            while (rs.next()) {
                logs.add(new com.meto.inventory.models.DebtPaymentLog(
                        rs.getString("customer"),
                        rs.getString("item"),
                        rs.getDouble("amount_paid"),
                        rs.getString("payment_date")));
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return logs;
    }

    public ObservableList<HistoryItem> getSettledDebts() {
        ObservableList<HistoryItem> history = FXCollections.observableArrayList();
        String sql = "SELECT MIN(id) as id, customer, " +
                "GROUP_CONCAT(quantity || ' ' || unit || ' ' || item || ' @ ' || price || ' = ' || amount || ' (' || date || ')', '\n') as item, "
                +
                "type, '-' as quantity, '-' as unit, 0 as price, 0 as cost_price, 0 as base_quantity, " +
                "SUM(amount) as amount, MAX(date) as date, is_debt, is_paid, SUM(COALESCE(paid_amount, 0)) as paid_amount " +
                "FROM sales WHERE is_debt = 1 AND is_paid = 1 AND customer != 'Walk-in Customer' " +
                "GROUP BY customer ORDER BY MAX(date) DESC LIMIT 100";
        try (Statement stmt = connection.createStatement();
                ResultSet rs = stmt.executeQuery(sql)) {
            while (rs.next()) {
                double amount = rs.getDouble("amount");
                double cost = rs.getDouble("cost_price");
                double baseQty = rs.getDouble("base_quantity");
                long profitVal = Math.round(amount - (cost * baseQty));

                history.add(new HistoryItem(
                        rs.getInt("id"),
                        rs.getString("customer"),
                        rs.getString("item"),
                        rs.getString("type"),
                        rs.getString("quantity"),
                        rs.getString("unit"),
                        String.format("%,.0f", rs.getDouble("price")),
                        String.format("%,.0f", amount),
                        String.format("%,d", profitVal),
                        rs.getString("date"),
                        true, true,
                        String.format("%,.0f", rs.getDouble("paid_amount"))));
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return history;
    }

    // --- FCM NOTIFICATION HELPERS ---

    public double getCustomerDebt(String customer) {
        String sql = "SELECT SUM(amount - COALESCE(paid_amount, 0)) FROM sales WHERE customer = ? AND is_debt = 1 AND is_paid = 0";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, customer);
            ResultSet rs = pstmt.executeQuery();
            if (rs.next())
                return rs.getDouble(1);
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return 0.0;
    }

    public double getProfitPeak() {
        String sql = "SELECT SUM(amount - (cost_price * base_quantity)) as daily_profit FROM sales WHERE type != 'NEW STOCK' GROUP BY date ORDER BY daily_profit DESC LIMIT 1";
        try (Statement stmt = connection.createStatement();
                ResultSet rs = stmt.executeQuery(sql)) {
            if (rs.next())
                return rs.getDouble(1);
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return 0.0;
    }

    public double getTodaysProfit() {
        String today = java.time.LocalDate.now().toString();
        String sql = "SELECT SUM(amount - (cost_price * base_quantity)) FROM sales WHERE date = ? AND type != 'NEW STOCK'";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, today);
            ResultSet rs = pstmt.executeQuery();
            if (rs.next())
                return rs.getDouble(1);
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return 0.0;
    }

    public double getAvailablePieces(String item, String size) {
        String sql = "SELECT SUM(available_pieces) FROM stock WHERE item = ? AND quantity = ?";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, item);
            pstmt.setString(2, size);
            ResultSet rs = pstmt.executeQuery();
            if (rs.next())
                return rs.getDouble(1);
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return 0.0;
    }

    // --- NOTIFICATIONS ---

    public void addNotification(String message, String source) {
        String sql = "INSERT INTO notifications (message, source, sync_id) VALUES (?, ?, ?)";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, message);
            pstmt.setString(2, source);
            pstmt.setString(3, java.util.UUID.randomUUID().toString());
            pstmt.executeUpdate();
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

    public List<NotificationItem> getNotifications() {
        List<NotificationItem> notifications = new ArrayList<>();
        String sql = "SELECT id, message, source, created_at, is_read FROM notifications ORDER BY created_at DESC";
        try (Statement stmt = connection.createStatement();
                ResultSet rs = stmt.executeQuery(sql)) {
            while (rs.next()) {
                notifications.add(new NotificationItem(
                        rs.getInt("id"),
                        rs.getString("message"),
                        rs.getString("source"),
                        rs.getString("created_at"),
                        rs.getInt("is_read") == 1));
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return notifications;
    }

    public void markNotificationAsRead(int id) {
        String sql = "UPDATE notifications SET is_read = 1 WHERE id = ?";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setInt(1, id);
            pstmt.executeUpdate();
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

    public void clearAllNotifications() {
        String sql = "DELETE FROM notifications";
        try (Statement stmt = connection.createStatement()) {
            stmt.executeUpdate(sql);
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

    private static class LegacySale {
        int id;
        String customer;
        String createdAt;

        LegacySale(int id, String customer, String date, String createdAt) {
            this.id = id;
            this.customer = customer;
            this.createdAt = createdAt;
        }
    }

    private static long getSecondsDifference(String t1, String t2) {
        if (t1 == null || t2 == null) return 9999;
        try {
            String cleanT1 = t1.replace("Z", "").replace(" ", "T");
            String cleanT2 = t2.replace("Z", "").replace(" ", "T");
            if (cleanT1.length() >= 19 && cleanT2.length() >= 19) {
                java.time.LocalDateTime dt1 = java.time.LocalDateTime.parse(cleanT1.substring(0, 19));
                java.time.LocalDateTime dt2 = java.time.LocalDateTime.parse(cleanT2.substring(0, 19));
                return Math.abs(java.time.Duration.between(dt1, dt2).toSeconds());
            }
        } catch (Exception e) {
            // ignore
        }
        return 9999;
    }

    public static class NotificationItem {
        private int id;
        private String message;
        private String source;
        private String createdAt;
        private boolean isRead;

        public NotificationItem(int id, String message, String source, String createdAt, boolean isRead) {
            this.id = id;
            this.message = message;
            this.source = source;
            this.createdAt = createdAt;
            this.isRead = isRead;
        }

        public int getId() {
            return id;
        }

        public String getMessage() {
            return message;
        }

        public String getSource() {
            return source;
        }

        public String getCreatedAt() {
            return createdAt;
        }

        public boolean isRead() {
            return isRead;
        }

        public void setRead(boolean isRead) {
            this.isRead = isRead;
        }
    }
}


