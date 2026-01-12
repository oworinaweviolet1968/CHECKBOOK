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
    private static final String DB_URL = "jdbc:sqlite:inventory.db";
    private Connection connection;

    public void initializeDatabase() {
        try {
            connection = DriverManager.getConnection(DB_URL);
            createTables();
        } catch (SQLException e) {
            e.printStackTrace();
        }
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

        // New table to "Store" the year's total before resetting
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
        } catch (SQLException e) {
            e.printStackTrace();
        }
    }

    // --- LOGIC ENGINE: CONVERSIONS ---

    public double convertToBaseUnit(String unit) {
        if (unit == null) return 1.0;
        String cleanUnit = unit.toLowerCase().trim();
        if (cleanUnit.contains("dozen") || cleanUnit.contains("doz")) return 12.0;
        if (cleanUnit.contains("half doz")) return 6.0;
        if (cleanUnit.contains("carton")) return 24.0;
        if (cleanUnit.contains("box")) return 10.0; // adjust to your actual box size
        return 1.0;
    }

    private double calculateTotalBaseStock(String unitCount, String size) {
        double count = extractNumericValue(unitCount);
        if (size.toLowerCase().contains("kg")) {
            double kgPerSack = extractNumericValue(size);
            return count * (kgPerSack > 0 ? kgPerSack : 1);
        }
        return convertToBaseUnit(unitCount);
    }

    private String formatStockForDisplay(double totalBase, String size) {
        if (size.toLowerCase().contains("kg")) {
            double kgPerSack = extractNumericValue(size);
            if (kgPerSack <= 0) return String.format("%.2f kg", totalBase);
            int sacks = (int) (totalBase / kgPerSack);
            double remainingKg = totalBase % kgPerSack;
            if (sacks > 0 && remainingKg > 0) return String.format("%d Sacks, %.2f kg", sacks, remainingKg);
            if (sacks > 0) return String.format("%d Sacks", sacks);
            return String.format("%.2f kg", remainingKg);
        }
        return String.format("%,.0f pcs", totalBase);
    }

    // --- STOCK OPERATIONS ---

    public boolean itemExists(String itemName, String size) {
        String sql = "SELECT COUNT(*) FROM stock WHERE item = ? AND quantity = ?";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, itemName);
            pstmt.setString(2, size);
            ResultSet rs = pstmt.executeQuery();
            if (rs.next()) return rs.getInt(1) > 0;
        } catch (SQLException e) { e.printStackTrace(); }
        return false;
    }

    public void mergeStock(String itemName, String size, String newUnit, double newPrice, String supplier) {
        // 1. Check existing stock
        String selectSql = "SELECT id, available_pieces, price FROM stock WHERE item = ? AND quantity = ?";
        try (PreparedStatement selectStmt = connection.prepareStatement(selectSql)) {
            selectStmt.setString(1, itemName);
            selectStmt.setString(2, size);
            ResultSet rs = selectStmt.executeQuery();

            if (rs.next()) {
                int id = rs.getInt("id");
                double existingPieces = rs.getDouble("available_pieces");
                double existingCostPerPiece = rs.getDouble("price");

                // 2. Calculate NEW incoming pieces
                double quantityNumber = extractNumericValue(newUnit); // e.g., 15
                double multiplier = getUnitMultiplier(newUnit);      // e.g., 12
                double incomingPieces = quantityNumber * multiplier; // Result: 180

                double newCostPerPiece = newPrice / (multiplier > 0 ? multiplier : 1);

                // 3. Weighted Average calculation
                double totalPieces = existingPieces + incomingPieces;
                double weightedAverageCost = ((existingPieces * existingCostPerPiece) + (incomingPieces * newCostPerPiece)) / totalPieces;

                // 4. Update Database (Updating available_pieces column!)
                String updateSql = "UPDATE stock SET available_pieces = ?, price = ?, supplier = ?, date = ?, unit = ? WHERE id = ?";
                try (PreparedStatement updateStmt = connection.prepareStatement(updateSql)) {
                    updateStmt.setDouble(1, totalPieces);
                    updateStmt.setDouble(2, weightedAverageCost);
                    updateStmt.setString(3, supplier);
                    updateStmt.setString(4, LocalDate.now().toString());
                    updateStmt.setString(5, newUnit); // Keep the last unit name for reference
                    updateStmt.setInt(6, id);
                    updateStmt.executeUpdate();
                }
            }
        } catch (SQLException e) { e.printStackTrace(); }
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
                double soldPieces = extractNumericValue(soldUnit) * getUnitMultiplier(soldUnit);
                double remaining = currentPieces - soldPieces;

                if (remaining >= 0) {
                    PreparedStatement updatePstmt = connection.prepareStatement(
                            "UPDATE stock SET available_pieces = ? WHERE id = ?");
                    updatePstmt.setDouble(1, remaining);
                    updatePstmt.setInt(2, id);
                    updatePstmt.executeUpdate();
                }
            }
        } catch (SQLException e) { e.printStackTrace(); }
    }

    public ObservableList<StockItem> getInStock() {
        ObservableList<StockItem> stockList = FXCollections.observableArrayList();
        // Fetch directly from our numeric column
        String sql = "SELECT item, quantity, available_pieces, price, supplier, date FROM stock ORDER BY item";

        try (Statement stmt = connection.createStatement();
             ResultSet rs = stmt.executeQuery(sql)) {
            while (rs.next()) {
                double totalPieces = rs.getDouble("available_pieces");
                double costPerPiece = rs.getDouble("price");
                String itemSize = rs.getString("quantity");

                stockList.add(new StockItem(
                        rs.getString("item"),
                        itemSize,
                        formatStockForDisplay(totalPieces, itemSize), // This will now show "180 pcs"
                        String.format("%,.0f", costPerPiece),
                        String.format("%,.0f", totalPieces * costPerPiece),
                        rs.getString("supplier"),
                        rs.getString("date")
                ));
            }
        } catch (SQLException e) { e.printStackTrace(); }
        return stockList;
    }

    public boolean hasEnoughStock(String itemName, String size, String soldUnit) {
        try (PreparedStatement pstmt = connection.prepareStatement("SELECT unit, quantity FROM stock WHERE item = ? AND quantity = ?")) {
            pstmt.setString(1, itemName);
            pstmt.setString(2, size);
            ResultSet rs = pstmt.executeQuery();
            if (rs.next()) {
                return calculateTotalBaseStock(rs.getString("unit"), rs.getString("quantity")) >= convertToBaseUnit(soldUnit);
            }
        } catch (SQLException e) { e.printStackTrace(); }
        return false;
    }

    public String getAvailableStock(String itemName, String size) {
        try (PreparedStatement pstmt = connection.prepareStatement("SELECT unit, quantity FROM stock WHERE item = ? AND quantity = ?")) {
            pstmt.setString(1, itemName);
            pstmt.setString(2, size);
            ResultSet rs = pstmt.executeQuery();
            if (rs.next()) {
                double total = calculateTotalBaseStock(rs.getString("unit"), rs.getString("quantity"));
                return formatStockForDisplay(total, rs.getString("quantity"));
            }
        } catch (SQLException e) { e.printStackTrace(); }
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
        } catch (SQLException e) { e.printStackTrace(); }
        return data;
    }
    // --- SALES & HISTORY ---

    public void addSale(String customer, String item, String quantity, String unit, double price, double amount, String type, String date) {
        // Added cost_price and base_quantity with default 0.0 for stock entries
        String sql = "INSERT INTO sales(customer, item, quantity, unit, price, cost_price, base_quantity, amount, type, date) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, customer);
            pstmt.setString(2, item);
            pstmt.setString(3, quantity);
            pstmt.setString(4, unit);
            pstmt.setDouble(5, price);
            pstmt.setDouble(6, 0.0);    // Default cost_price for 'NEW STOCK'
            pstmt.setDouble(7, 0.0);    // Default base_quantity for 'NEW STOCK'
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

        if (filter != null && !filter.isEmpty() && !"ALL".equals(filter)) sql += " AND type = ?";
        sql += " ORDER BY date DESC, created_at DESC";

        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            if (filter != null && !filter.isEmpty() && !"ALL".equals(filter)) pstmt.setString(1, filter);
            ResultSet rs = pstmt.executeQuery();

            while (rs.next()) {
                double amount = rs.getDouble("amount");        // e.g., 52,000.0
                double cost = rs.getDouble("cost_price");      // e.g., 2,083.3333
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
                        rs.getString("date")
                ));
            }
        } catch (SQLException e) {
            e.printStackTrace();
        }
        return history;
    }

    public ObservableList<HistoryItem> getTodaysSales() {
        ObservableList<HistoryItem> history = FXCollections.observableArrayList();
        String today = LocalDate.now().toString();
        String sql = "SELECT customer, item, type, quantity, unit, price, amount, cost_price, base_quantity, date FROM sales " +
                "WHERE date = ? AND type != 'NEW STOCK' ORDER BY created_at DESC";

        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, today);
            ResultSet rs = pstmt.executeQuery();
            while (rs.next()) {
                double amount = rs.getDouble("amount");        // e.g., 52,000.0
                double cost = rs.getDouble("cost_price");      // e.g., 2,083.3333
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
                        rs.getString("date")
                ));
            }
        } catch (SQLException e) { e.printStackTrace(); }
        return history;
    }

    public void addSaleWithProfit(String customer, String item, String size, String unit, double sellingPrice, String type) {
        // Remove Math.floor here if you added it earlier!
        double costPrice = getLastRecordedPrice(item, size);

        // 1. Get the raw number (e.g., "2" from "2 dozen")
        double unitCount = extractNumericValue(unit);

        // 2. Get the multiplier (e.g., 12 for dozen) to find total pieces for stock deduction
        double multiplier = getUnitMultiplier(unit);
        double baseQty = unitCount * multiplier;

        // 3. FIX: Total Amount should be (Count * Price)
        // Example: 2 (dozens) * 26,000 = 52,000
        double totalAmount = unitCount * sellingPrice;

        String sql = "INSERT INTO sales(customer, item, quantity, unit, price, cost_price, base_quantity, amount, type, date) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)";
        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, customer);
            pstmt.setString(2, item);
            pstmt.setString(3, size);
            pstmt.setString(4, unit);
            pstmt.setDouble(5, sellingPrice);
            pstmt.setDouble(6, costPrice);
            pstmt.setDouble(7, baseQty);       // Keep this as 24 for profit math (pieces * cost_per_piece)
            pstmt.setDouble(8, totalAmount);   // This will now be 52,000
            pstmt.setString(9, type);
            pstmt.setString(10, LocalDate.now().toString());
            pstmt.executeUpdate();
        } catch (SQLException e) { e.printStackTrace(); }
    }

    public double getCurrentYearProfit() {
        String yearPrefix = LocalDate.now().getYear() + "-%";
        String sql = "SELECT SUM(amount - (cost_price * base_quantity)) FROM sales WHERE date LIKE ? AND type != 'NEW STOCK'";

        try (PreparedStatement pstmt = connection.prepareStatement(sql)) {
            pstmt.setString(1, yearPrefix);
            ResultSet rs = pstmt.executeQuery();
            if (rs.next()) return rs.getDouble(1);
        } catch (SQLException e) { e.printStackTrace(); }
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
        } catch (SQLException e) { e.printStackTrace(); }
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
        } catch (SQLException e) { e.printStackTrace(); }
        return 0.0;
    }

    // --- DATA HELPERS ---

    private double extractNumericValue(String text) {
        if (text == null || text.isEmpty()) return 0.0;

        String lowercaseText = text.toLowerCase().trim();
        double fractionValue = 0.0;

        // 1. Identify the fraction value
        if (lowercaseText.contains("1/4")) fractionValue = 0.25;
        else if (lowercaseText.contains("1/2")) fractionValue = 0.5;

        // 2. Extract the whole number (the "2" in "2 1/2 kg")
        String numbersOnly = lowercaseText
                .replace("1/4", "")
                .replace("1/2", "")
                .replaceAll("[^0-9.]", "")
                .trim();

        if (!numbersOnly.isEmpty()) {
            try {
                double wholeNumber = Double.parseDouble(numbersOnly);

                // LOGIC FIX: If there is a fraction present, we MULTIPLY.
                // Example: "2 1/2" becomes 2 * 0.5 = 1.0kg
                if (fractionValue > 0) {
                    return wholeNumber * fractionValue;
                }
                return wholeNumber; // Just a regular number like "5 kg"

            } catch (NumberFormatException e) {
                return fractionValue; // Fallback to just the fraction if no whole number
            }
        }

        return fractionValue; // Return 0.25 or 0.5 if no leading number exists
    }

    private String extractUnitType(String text) {
        if (text == null) return "pcs";
        String type = text.replaceAll("[0-9.]", "").trim().toLowerCase();
        return type.isEmpty() ? "pcs" : type;
    }

    private double getUnitMultiplier(String unitText) {
        String type = extractUnitType(unitText); // gets "dozen", "carton", etc.
        return switch (type) {
            case "dozen" -> 12.0;
            case "carton" -> 24.0;
            case "box" -> 10.0;
            case "half doz" -> 6.0;
            default -> 1.0;
        };
    }

    public void addStock(String s, String i, String q, String u, double p, String d) {
        double unitCount = extractNumericValue(u);
        double multiplier = getUnitMultiplier(u);
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
        } catch (SQLException e) { e.printStackTrace(); }
    }

    public ObservableList<String> getAvailableItems() {
        ObservableList<String> items = FXCollections.observableArrayList();
        try (Statement stmt = connection.createStatement();
             ResultSet rs = stmt.executeQuery("SELECT DISTINCT item FROM stock ORDER BY item")) {
            while (rs.next()) items.add(rs.getString("item"));
        } catch (SQLException e) { e.printStackTrace(); }
        return items;
    }

    public ObservableList<String> getItemSizes(String itemName) {
        ObservableList<String> sizes = FXCollections.observableArrayList();
        try (PreparedStatement pstmt = connection.prepareStatement("SELECT DISTINCT quantity FROM stock WHERE item = ?")) {
            pstmt.setString(1, itemName);
            ResultSet rs = pstmt.executeQuery();
            while (rs.next()) sizes.add(rs.getString("quantity"));
        } catch (SQLException e) { e.printStackTrace(); }
        return sizes;
    }

    public void close() {
        try { if (connection != null) connection.close(); } catch (SQLException e) { e.printStackTrace(); }
    }
}