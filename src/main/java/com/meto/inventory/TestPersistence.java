package com.meto.inventory;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.io.File;

public class TestPersistence {

    // Mimic the DatabaseHelper logic
    private static String dbUrl = "jdbc:sqlite:test_persistence.db";
    private static Connection connection;

    public static void main(String[] args) {
        try {
            System.out.println("TEST: Starting Persistence Check...");

            // 1. Create DB and Table
            connect();
            createTables();

            // 2. Check Empty
            boolean initial = hasData();
            System.out.println("Initial hasData: " + initial); // Should be false

            // 3. Add Data
            System.out.println("Adding dummy data...");
            try (Statement stmt = connection.createStatement()) {
                stmt.execute(
                        "INSERT INTO stock (supplier, item, quantity, unit, price, date) VALUES ('Sup', 'Item1', '10', 'kg', 100, '2023-01-01')");
            }

            // 4. Check Full
            boolean hasData = hasData();
            System.out.println("After Insert hasData: " + hasData); // Should be true

            // 5. Close and Re-open
            close();
            System.out.println("Closed DB.");

            connect();
            System.out.println("Re-opened DB.");

            boolean recheck = hasData();
            System.out.println("Re-opened hasData: " + recheck); // Should be true

            // 6. Cleanup
            close();
            java.nio.file.Files.delete(java.nio.file.Path.of("test_persistence.db"));
            System.out.println("TEST COMPLETE");

        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    // --- Helper Methods ---

    private static void connect() throws SQLException {
        try {
            Class.forName("org.sqlite.JDBC");
        } catch (ClassNotFoundException e) {
            e.printStackTrace();
        }
        connection = DriverManager.getConnection(dbUrl);
    }

    private static void close() {
        try {
            if (connection != null)
                connection.close();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    private static void createTables() throws SQLException {
        String createStockTable = "CREATE TABLE IF NOT EXISTS stock (" +
                "id INTEGER PRIMARY KEY AUTOINCREMENT," +
                "supplier TEXT NOT NULL," +
                "item TEXT NOT NULL," +
                "quantity TEXT NOT NULL," +
                "unit TEXT NOT NULL," +
                "price REAL NOT NULL," +
                "available_pieces REAL DEFAULT 0," +
                "date TEXT NOT NULL," +
                "created_at DATETIME DEFAULT CURRENT_TIMESTAMP" +
                ")";
        String createSalesTable = "CREATE TABLE IF NOT EXISTS sales (" +
                "id INTEGER PRIMARY KEY AUTOINCREMENT," +
                "amount REAL" +
                ")";

        try (Statement stmt = connection.createStatement()) {
            stmt.execute(createStockTable);
            stmt.execute(createSalesTable);
        }
    }

    private static boolean hasData() {
        try {
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
}
