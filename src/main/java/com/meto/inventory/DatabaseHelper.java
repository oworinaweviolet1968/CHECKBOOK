package com.meto.inventory;

import com.meto.inventory.models.HistoryItem;
import com.meto.inventory.models.StockItem;
import javafx.collections.FXCollections;
import javafx.collections.ObservableList;

import java.sql.*;
import java.time.LocalDate;
import java.util.HashMap;
import java.util.Map;

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

        try (Statement stmt = connection.createStatement()) {
            stmt.execute(createStockTable);
            stmt.execute(createSalesTable);
            stmt.execute(createSummaryTable);

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
        return count * getUnitMultiplier(unitCount, size);
    }

    private String formatStockForDisplay(double totalBase, String size, String bulkUnit) {
        String sizeLower = size.toLowerCase();

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
        double multiplier = getUnitMultiplier(bulkUnit, size);

        // If multiplier is 1 or box*10, just show pcs
        if (multiplier <= 1.0 || multiplier == 10.0) {
            if (totalBase % 1 == 0) {
                return String.format("%,.0f pcs", totalBase);
            }
            return String.format("%,.1f pcs", totalBase);
        }

        // Friendly name for the highest unit
        String friendlyName;
        if (multiplier == 6.0) friendlyName = "Half Doz";
        else if (multiplier == 25.0) friendlyName = "Crates";
        else friendlyName = "Boxes"; // box*12, box*20, box*24, box*72 all show as "Boxes"

        int mainCount = (int) (totalBase / multiplier);
        int leftover = (int) (totalBase % multiplier);

        StringBuilder display = new StringBuilder();

        // Level 1: Highest unit
        if (mainCount > 0) {
            display.append(mainCount).append(" ").append(friendlyName);
        }

        // Level 2: Doz (only if highest unit > 12 and leftover >= 12)
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

        return display.length() > 0 ? display.toString() : String.format("%,.0f pcs", totalBase);
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
                double multiplier = getUnitMultiplier(newUnit, size);
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
                String updateSql = "UPDATE stock SET available_pieces = ?, price = ?, supplier = ?, date = ?, unit = ? WHERE id = ?";
                try (PreparedStatement updateStmt = connection.prepareStatement(updateSql)) {
                    updateStmt.setDouble(1, existingPieces + incomingPieces);
                    updateStmt.setDouble(2,
                            ((existingPieces * existingCostPerPiece) + (incomingPieces * newCostPerPiece))
                                    / (existingPieces + incomingPieces));
                    updateStmt.setString(3, supplier);
                    updateStmt.setString(4, LocalDate.now().toString());
                    updateStmt.setString(5, newUnit);
                    updateStmt.setInt(6, id); // Set the 6th parameter!
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
            String sql = "SELECT id, available_pieces FROM stock WHERE item = ? AND quantity = ?";
            PreparedStatement pstmt = connection.prepareStatement(sql);
            pstmt.setString(1, itemName);
            pstmt.setString(2, soldSize);
            ResultSet rs = pstmt.executeQuery();

            if (rs.next()) {
                int id = rs.getInt("id");
                double currentPieces = rs.getDouble("available_pieces");
                double soldPieces = extractNumericValue(soldUnit) * getUnitMultiplier(soldUnit, soldSize);
                double remaining = currentPieces - soldPieces;

                if (remaining >= 0) {
                    PreparedStatement updatePstmt = connection.prepareStatement(
                            "UPDATE stock SET available_pieces = ? WHERE id = ?");
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
                .prepareStatement("SELECT available_pieces FROM stock WHERE item = ? AND quantity = ?")) {
            pstmt.setString(1, itemName);
            pstmt.setString(2, size);
            ResultSet rs = pstmt.executeQuery();
            if (rs.next()) {
                double stockAvailable = rs.getDouble("available_pieces");
                double amountTryingToSell = extractNumericValue(soldUnit) * getUnitMultiplier(soldUnit, size);
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
        String sql = "INSERT INTO sales(customer, item, quantity, unit, price, cost_price, base_quantity, amount, type, date) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
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

        // 1. Get the raw number (e.g., "2" from "2 dozen")
        // NOTE: For "3 1/2 kg", this now returns 1.5 (Total Weight/Qty), NOT 3 (Count)
        double quantityFactor = extractNumericValue(unit);

        // 2. Get the multiplier
        double multiplier = getUnitMultiplier(unit, size);

        // Logic check: If extractNumericValue returns 1.5, and multiplier returns 1
        // (for KG/fractions),
        // then baseQty = 1.5. Correct for stock deduction.
        // If multiplier returns non-1 (e.g. sack=20), checks needed.
        // Assuming getUnitMultiplier handles "1/2 kg" by returning 1 or similar if the
        // fraction logic is inside extractNumericValue.
        double baseQty = quantityFactor * multiplier;

        // DEBUG: Ensure we use the PASSED totalAmount
        // double totalAmount = unitCount * sellingPrice; <--- REMOVED

        String sql = "INSERT INTO sales(customer, item, quantity, unit, price, cost_price, base_quantity, amount, type, date) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
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

        // 2. Extract the FIRST whole number (e.g., the "12" in "12 box*12")
        // Use regex to find the first sequence of digits and dots
        java.util.regex.Pattern pattern = java.util.regex.Pattern.compile("(\\d+\\.?\\d*)");
        java.util.regex.Matcher matcher = pattern.matcher(lowercaseText.replace("1/4", "").replace("1/2", ""));

        if (matcher.find()) {
            try {
                double wholeNumber = Double.parseDouble(matcher.group(1));
                if (fractionValue > 0) {
                    return wholeNumber * fractionValue;
                }
                return wholeNumber;
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

    public double getUnitMultiplier(String unitText, String size) {
        if (unitText == null)
            return 1.0;
        String type = unitText.toLowerCase().trim();
        String sizeLower = size.toLowerCase().trim();

        // 1. Check for the LONGEST/MOST SPECIFIC strings first
        // If it's a sack, use the KG number from the size (e.g., "50kg" -> 50)
        // ONLY treat "pc" as a "Sack" if the size is 10kg or more (Bulk)
        // This protects small 1kg or 2kg packs from the sack logic
        double sizeNum = extractNumericValue(sizeLower);
        boolean isBulkSack = sizeLower.contains("kg") && sizeNum >= 10.0;

        if (type.contains("sack") || (isBulkSack && type.contains("pc"))) {
            return sizeNum;
        }

        // --- IMPROVED: Extract from * notation if present (e.g. box*12 -> 12) ---
        if (type.contains("*")) {
            try {
                String afterStar = type.substring(type.lastIndexOf("*") + 1).trim();
                double val = extractNumericValue(afterStar);
                if (val > 0)
                    return val;
            } catch (Exception e) {
                // fall through
            }
        }

        if (type.contains("half doz"))
            return 6.0;

        // 2. Check for the shorter/general strings last
        if (type.contains("box*10"))
            return 10.0;
        if (type.contains("box*12") || type.contains("dozen") || type.contains("doz"))
            return 12.0;
        if (type.contains("box*20") || type.equals("box"))
            return 20.0;
        if (type.contains("box*24") || type.contains("carton"))
            return 24.0;
        if (type.contains("box*72"))
            return 72.0;
        if (type.contains("crate") || type.contains("crate*25"))
            return 25.0;
        if (type.contains("box"))
            return 20.0;

        return 1.0;
    }

    public void addStock(String s, String i, String q, String u, double p, String d) {
        double unitCount = extractNumericValue(u);
        double multiplier = getUnitMultiplier(u, q);
        double totalPieces = unitCount * multiplier;

        // Use double for precision. If p is 25000 and multiplier is 12,
        // this needs to be 2083.33333333, not 2083.
        // Change this line to keep the decimals
        double pricePerSinglePiece = (double) p / multiplier; // e.g., 2083.33333333

        String sql = "INSERT INTO stock(supplier, item, quantity, unit, price, available_pieces, date) VALUES(?, ?, ?, ?, ?, ?, ?)";
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

    public void close() {
        try {
            if (connection != null)
                connection.close();
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }
}