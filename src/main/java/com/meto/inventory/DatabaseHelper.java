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
            stmt.execute("CREATE TABLE IF NOT EXISTS deleted_stock (id INTEGER PRIMARY KEY AUTOINCREMENT, item TEXT, quantity TEXT, deleted_at DATETIME DEFAULT CURRENT_TIMESTAMP)");

            // AUTOMATIC MIGRATION: Check for missing columns in legacy DBs
            ensureSchema(stmt);

        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

    private void ensureSchema(Statement stmt) throws SQLException {
        // 1. Check STOCK table for 'available_pieces'
        try {
            ResultSet rs = stmt.executeQuery("PRAGMA table_info(stock)");
            boolean hasAvailablePieces = false;
            while (rs.next()) {
                if ("available_pieces".equalsIgnoreCase(rs.getString("name"))) {
                    hasAvailablePieces = true;
                    break;
                }
            }
            if (!hasAvailablePieces) {
                System.out.println("Migrating Schema: Adding 'available_pieces' to stock table.");
                stmt.execute("ALTER TABLE stock ADD COLUMN available_pieces REAL DEFAULT 0");
                // Optional: Backfill available_pieces from old logic if possible,
                // but since we don't know the logic, 0 is safer than crashing.
            }
        } catch (SQLException e) {
            System.err.println("Schema check failed for stock: " + e.getMessage());
        }

        // 2. Check SALES table for 'cost_price' and 'base_quantity'
        try {
            ResultSet rs = stmt.executeQuery("PRAGMA table_info(sales)");
            boolean hasCostPrice = false;
            boolean hasBaseQty = false;
            while (rs.next()) {
                String col = rs.getString("name");
                if ("cost_price".equalsIgnoreCase(col))
                    hasCostPrice = true;
                if ("base_quantity".equalsIgnoreCase(col))
                    hasBaseQty = true;
            }

            if (!hasCostPrice) {
                System.out.println("Migrating Schema: Adding 'cost_price' to sales table.");
                stmt.execute("ALTER TABLE sales ADD COLUMN cost_price REAL DEFAULT 0");
            }
            if (!hasBaseQty) {
                System.out.println("Migrating Schema: Adding 'base_quantity' to sales table.");
                stmt.execute("ALTER TABLE sales ADD COLUMN base_quantity REAL DEFAULT 0");
            }
        } catch (SQLException e) {
            System.err.println("Schema check failed for sales: " + e.getMessage());
        }

        // 3. New device_source column
        try {
            ResultSet rs = stmt.executeQuery("PRAGMA table_info(stock)");
            boolean hasSource = false;
            while (rs.next()) {
                if ("device_source".equalsIgnoreCase(rs.getString("name"))) {
                    hasSource = true;
                    break;
                }
            }
            if (!hasSource) {
                stmt.execute("ALTER TABLE stock ADD COLUMN device_source TEXT DEFAULT 'Desktop'");
                stmt.execute("ALTER TABLE sales ADD COLUMN device_source TEXT DEFAULT 'Desktop'");
            }
        } catch (SQLException e) {}
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
            } else {
                return String.format("%,.1f kg", totalBase);
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
        if (multiplier == 6.0) friendlyName = "Half Doz";
        else if (multiplier == 12.0) friendlyName = "Doz";
        else if (sizeLower.contains("crate")) friendlyName = "Crs";
        else if (sizeLower.contains("carton")) friendlyName = "Cts";
        else if (sizeLower.contains("pack")) friendlyName = "Pks";
        else if (sizeLower.contains("bundle")) friendlyName = "Bndls";
        else friendlyName = "Bx"; 

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
            if (display.length() > 0) display.append(" / ");
            display.append(dozens).append(" Doz");
        }

        // Level 3: Remaining pcs
        if (leftover > 0) {
            if (display.length() > 0) display.append(" / ");
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
        String selectSql = "SELECT id, available_pieces, price FROM stock WHERE item = ? AND quantity = ?";
        try (PreparedStatement selectStmt = connection.prepareStatement(selectSql)) {
            selectStmt.setString(1, itemName);
            selectStmt.setString(2, size);
            ResultSet rs = selectStmt.executeQuery();

            if (rs.next()) {
                int id = rs.getInt("id");
                double existingPieces = rs.getDouble("available_pieces");
                double existingCostPerPiece = rs.getDouble("price");

                double quantityNumber = extractNumericValue(newUnit);
                double multiplier = getUnitMultiplier(newUnit, size, newUnit);
                double incomingPieces = quantityNumber * multiplier;
                double newCostPerPiece = newPrice / (multiplier > 0 ? multiplier : 1);

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
                    updateStmt.setString(5, newUnit);
                    updateStmt.setInt(6, id); 
                    updateStmt.executeUpdate();
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
        // Added cost_price and base_quantity with default 0.0 for stock entries
        String sql = "INSERT INTO sales(customer, item, quantity, unit, price, cost_price, base_quantity, amount, type, date, device_source) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'Desktop')";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, customer);
            pstmt.setString(2, item);
            pstmt.setString(3, quantity);
            pstmt.setString(4, unit);
            pstmt.setDouble(5, price);
            pstmt.setDouble(6, 0.0); // Default cost_price for 'NEW STOCK'
            pstmt.setDouble(7, 0.0); // Default base_quantity for 'NEW STOCK'
            pstmt.setDouble(8, amount);
            pstmt.setString(9, type);
            pstmt.setString(10, date);
            pstmt.executeUpdate();
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

    public ObservableList<HistoryItem> getHistory(String filter) {
        ObservableList<HistoryItem> history = FXCollections.observableArrayList();

        // 1. Updated SQL to include cost_price and base_quantity
        String sql = "SELECT customer, item, type, quantity, unit, price, cost_price, base_quantity, amount, date FROM sales WHERE 1=1";

        if (filter != null && !filter.isEmpty() && !"ALL".equals(filter))
            sql += " AND type = ?";
        sql += " ORDER BY date DESC, created_at DESC";

        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            if (filter != null && !filter.isEmpty() && !"ALL".equals(filter))
                pstmt.setString(1, filter);
            ResultSet rs = pstmt.executeQuery();

            while (rs.next()) {
                double amount = rs.getDouble("amount"); // e.g., 52,000.0
                double cost = rs.getDouble("cost_price"); // e.g., 2,083.3333
                double baseQty = rs.getDouble("base_quantity"); // e.g., 24.0

                // Precision math: 52000 - (2083.3333 * 24) = 2000.0
                long profitVal = Math.round(amount - (cost * baseQty));

                history.add(new HistoryItem(
                        rs.getString("customer"),
                        rs.getString("item"),
                        rs.getString("type"),
                        rs.getString("quantity"),
                        rs.getString("unit"),
                        String.format("%,.0f", rs.getDouble("price")),
                        String.format("%,.0f", amount),
                        String.format("%,d", profitVal), // Displays exactly 2,000
                        rs.getString("date")));
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return history;
    }

    public ObservableList<HistoryItem> getTodaysSales() {
        ObservableList<HistoryItem> history = FXCollections.observableArrayList();
        String today = LocalDate.now().toString();
        String sql = "SELECT customer, item, type, quantity, unit, price, amount, cost_price, base_quantity, date FROM sales "
                +
                "WHERE date = ? AND type != 'NEW STOCK' ORDER BY created_at DESC";

        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, today);
            ResultSet rs = pstmt.executeQuery();
            while (rs.next()) {
                double amount = rs.getDouble("amount"); // e.g., 52,000.0
                double cost = rs.getDouble("cost_price"); // e.g., 2,083.3333
                double baseQty = rs.getDouble("base_quantity"); // e.g., 24.0

                // Precision math: 52000 - (2083.3333 * 24) = 2000.0
                double profitVal = amount - (cost * baseQty);

                history.add(new HistoryItem(
                        rs.getString("customer"),
                        rs.getString("item"),
                        rs.getString("type"),
                        rs.getString("quantity"),
                        rs.getString("unit"),
                        String.format("%,.2f", rs.getDouble("price")),
                        String.format("%,.2f", amount),
                        String.format("%,.2f", profitVal), // Displays exactly 2,000.00
                        rs.getString("date")));
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return history;
    }

    public void addSaleWithProfit(String customer, String item, String size, String unit, double sellingPrice,
            double totalAmount,
            String type) {
        // Remove Math.floor here if you added it earlier!
        double costPrice = getLastRecordedPrice(item, size);

        // Retrieve bulk unit from stock to ensure correct multiplier detection
        String bulkUnit = "";
        try (PreparedStatement pstmt = connection.prepareStatement("SELECT unit FROM stock WHERE item = ? AND quantity = ? LIMIT 1")) {
            pstmt.setString(1, item);
            pstmt.setString(2, size);
            ResultSet rs = pstmt.executeQuery();
            if (rs.next()) bulkUnit = rs.getString("unit");
        } catch (SQLException e) { e.printStackTrace(); }

        // 1. Get the raw number (e.g., "2" from "2 dozen")
        double quantityFactor = extractNumericValue(unit);

        // 2. Get the multiplier
        double multiplier = getUnitMultiplier(unit, size, bulkUnit);
        double baseQty = quantityFactor * multiplier;

        String sql = "INSERT INTO sales(customer, item, quantity, unit, price, cost_price, base_quantity, amount, type, date, is_edited, device_source) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 'Desktop')";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, customer);
            pstmt.setString(2, item);
            pstmt.setString(3, size);
            pstmt.setString(4, unit);
            pstmt.setDouble(5, sellingPrice);
            pstmt.setDouble(6, costPrice);
            pstmt.setDouble(7, baseQty);
            pstmt.setDouble(8, totalAmount); // Use the explicit amount
            pstmt.setString(9, type);
            pstmt.setString(10, LocalDate.now().toString());
            pstmt.executeUpdate();
        } catch (SQLException e) {
            e.printStackTrace();
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
        if (unitText == null || unitText.isEmpty()) return 1.0;
        String type = unitText.toLowerCase().replaceAll("\\s+", ""); // Normalize spaces
        String sizeLower = size.toLowerCase().replaceAll("\\s+", "");
        String bulkLower = (bulkUnit != null) ? bulkUnit.toLowerCase().replaceAll("\\s+", "") : "";

        double sizeNum = extractNumericValue(sizeLower);
        boolean isBulkSack = sizeLower.contains("kg") && sizeNum >= 10.0;

        if (type.contains("sack") || (isBulkSack && (type.contains("pc") || type.contains("item")))) {
            return sizeNum;
        }

        // 1. Check for explicit multiplier in the unit itself (e.g. "pcs*12" or "box*72")
        if (type.contains("*")) {
            try {
                String afterStar = type.substring(type.lastIndexOf("*") + 1).trim();
                double val = extractNumericValue(afterStar);
                if (val > 0) return val;
            } catch (Exception e) {}
        }

        // Normalize 'type' by removing leading quantities for generic matching (e.g. "2 boxes" -> "boxes")
        String normalizedType = type.replaceAll("^[0-9./* ]+", "");

        // 2. Specific Handle Piece or Item units (always 1.0 unless explicit * was used above)
        if (normalizedType.equals("pc") || normalizedType.equals("pcs") || normalizedType.equals("item") || normalizedType.equals("items")) {
            return 1.0;
        }

        // 3. Check for specific packaging (Dozens, etc.)
        if (normalizedType.contains("halfdoz")) return 6.0;
        if (normalizedType.contains("half")) return 0.5;
        if (normalizedType.contains("quarter")) return 0.25;
        if (normalizedType.contains("dozen") || normalizedType.contains("doz")) return 12.0;

        // 4. Generic bulk unit text matching item's metadata (Box, Carton, etc.)
        if (normalizedType.equals("box") || normalizedType.equals("boxes") || normalizedType.contains("carton") || normalizedType.contains("crate")) {
            // First check the size meta-data for multiplier
            if (sizeLower.contains("*")) {
                try {
                    String afterStar = sizeLower.substring(sizeLower.lastIndexOf("*") + 1).trim();
                    double val = extractNumericValue(afterStar);
                    if (val > 0) return val;
                } catch (Exception e) {}
            }
            // Then check the bulk unit meta-data for multiplier
            if (bulkLower.contains("*")) {
                try {
                    String afterStar = bulkLower.substring(bulkLower.lastIndexOf("*") + 1).trim();
                    double val = extractNumericValue(afterStar);
                    if (val > 0) return val;
                } catch (Exception e) {}
            }
            return 20.0; // Standard fallback for generic box
        }

        // Legacy Fallbacks (space-normalized)
        if (type.contains("box*10")) return 10.0;
        if (type.contains("box*12")) return 12.0;
        if (type.contains("box*24")) return 24.0;
        if (type.contains("crate*25")) return 25.0;
        if (type.contains("box*72")) return 72.0;
        if (type.contains("box*20")) return 20.0;

        return 1.0;
    }

    public void addStock(String s, String i, String q, String u, double p, String d) {
        double unitCount = extractNumericValue(u);
        double multiplier = getUnitMultiplier(u, q, u);
        double totalPieces = unitCount * multiplier;

        // Change this line to keep the decimals
        double pricePerSinglePiece = (double) p / multiplier; // e.g., 2083.33333333

        String sql = "INSERT INTO stock(supplier, item, quantity, unit, price, available_pieces, date, is_edited, device_source) VALUES(?, ?, ?, ?, ?, ?, ?, 1, 'Desktop')";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, s);
            pstmt.setString(2, i);
            pstmt.setString(3, q);
            pstmt.setString(4, u);
            pstmt.setDouble(5, pricePerSinglePiece); // SQL REAL type will store decimals
            pstmt.setDouble(6, totalPieces);
            pstmt.setString(7, d);
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
            // Track the deletion for cloud merging
            try (PreparedStatement delTrack = connection.prepareStatement("INSERT INTO deleted_stock(item, quantity) VALUES(?, ?)")) {
                delTrack.setString(1, itemName);
                delTrack.setString(2, size);
                delTrack.executeUpdate();
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

    public ObservableList<String> getDistinctSuppliers() {
        ObservableList<String> names = FXCollections.observableArrayList();
        try (Statement stmt = connection.createStatement();
             ResultSet rs = stmt.executeQuery("SELECT DISTINCT supplier FROM stock ORDER BY supplier")) {
            while (rs.next()) {
                String s = rs.getString("supplier");
                if (s != null && !s.isBlank()) names.add(s);
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
        } catch (SQLException e) { e.printStackTrace(); }
        return records;
    }

    public List<Map<String, String>> getDeletedStock() {
        List<Map<String, String>> deleted = new ArrayList<>();
        try (Statement stmt = connection.createStatement(); ResultSet rs = stmt.executeQuery("SELECT item, quantity FROM deleted_stock")) {
            while (rs.next()) {
                Map<String, String> m = new HashMap<>();
                m.put("item", rs.getString("item"));
                m.put("quantity", rs.getString("quantity"));
                deleted.add(m);
            }
        } catch (SQLException e) { e.printStackTrace(); }
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
        } catch (SQLException e) { e.printStackTrace(); }
        return deleted;
    }

    public static class DirtyRecord {
        public final Map<String, Object> data;
        public DirtyRecord(Map<String, Object> data) { this.data = data; }
    }

    public boolean isStockDeleted(String item, String quantity) {
        String sql = "SELECT 1 FROM deleted_stock WHERE item = ? AND quantity = ?";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, item);
            pstmt.setString(2, quantity);
            try (ResultSet rs = pstmt.executeQuery()) {
                return rs.next();
            }
        } catch (SQLException e) { return false; }
    }

    public boolean isSaleDeleted(String customer, String item, Object amount, String date) {
        String sql = "SELECT 1 FROM deleted_history WHERE customer = ? AND item = ? AND amount = ? AND date = ?";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, customer);
            pstmt.setString(2, item);
            pstmt.setObject(3, amount);
            pstmt.setString(4, date);
            try (ResultSet rs = pstmt.executeQuery()) {
                return rs.next();
            }
        } catch (SQLException e) { return false; }
    }

    public void applyDirtyRecord(String table, DirtyRecord record) {
        // Create a copy and remove 'id' to let the new database assign a local ID
        Map<String, Object> data = new HashMap<>(record.data);
        data.remove("id");

        // TOMBSTONE CHECK: Don't restore if deleted in the cloud (other device)
        if ("stock".equals(table)) {
            if (isStockDeleted((String)data.get("item"), (String)data.get("quantity"))) {
                System.out.println("SYNC: Skipping restore of " + data.get("item") + " - Deleted in cloud.");
                return;
            }
        }
        if ("sales".equals(table)) {
            if (isSaleDeleted((String)data.get("customer"), (String)data.get("item"), data.get("amount"), (String)data.get("date"))) {
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
                            if (sets.length() > 0) sets.append(", ");
                            sets.append(k).append(" = ?");
                            args.add(v);
                        });
                        String updateSql = "UPDATE stock SET " + sets + " WHERE id = ?";
                        try (PreparedStatement upstmt = connection.prepareStatement(updateSql)) {
                            for (int i = 0; i < args.size(); i++) upstmt.setObject(i + 1, args.get(i));
                            upstmt.setInt(args.size() + 1, existingId);
                            upstmt.executeUpdate();
                            return;
                        }
                    }
                }
            } catch (SQLException e) { e.printStackTrace(); }
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
                    if (rs.next()) return; // Already exists
                }
            } catch (SQLException e) { e.printStackTrace(); }
        }

        // Standard Insert
        StringBuilder cols = new StringBuilder();
        StringBuilder vals = new StringBuilder();
        List<Object> args = new ArrayList<>();
        
        data.forEach((k, v) -> {
            if (cols.length() > 0) { cols.append(","); vals.append(","); }
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
        } catch (SQLException e) { e.printStackTrace(); }
    }

    public void applyStockDeletion(String item, String quantity) {
        try (PreparedStatement pstmt = connection.prepareStatement("DELETE FROM stock WHERE item = ? AND quantity = ?")) {
            pstmt.setString(1, item);
            pstmt.setString(2, quantity);
            pstmt.executeUpdate();
        } catch (SQLException e) { e.printStackTrace(); }
    }

    public void applyHistoryDeletion(String customer, String item, String amount, String date) {
        String sql = "DELETE FROM sales WHERE customer = ? AND item = ? AND amount = ? AND date = ?";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, customer);
            pstmt.setString(2, item);
            pstmt.setString(3, amount);
            pstmt.setString(4, date);
            pstmt.executeUpdate();
        } catch (SQLException e) { e.printStackTrace(); }
    }

    public void clearDirtyFlags() {
        try (Statement stmt = connection.createStatement()) {
            stmt.execute("UPDATE stock SET is_edited = 0");
            stmt.execute("UPDATE sales SET is_edited = 0");
            stmt.execute("DELETE FROM deleted_stock");
        } catch (SQLException e) { e.printStackTrace(); }
    }
}
