package com.meto.inventory;
import java.sql.*;
public class TestHistory {
    public static void main(String[] args) {
        String dbUrl = "jdbc:sqlite:/home/bexwrld/METO_IMS_DATA/inventory_f91a785e_b4eb_4607_9e0d_920779bfd3a4.db";
        try (Connection conn = DriverManager.getConnection(dbUrl)) {
            System.out.println("--- NUTS INVENTORY ---");
            try (Statement stmt = conn.createStatement(); ResultSet rs = stmt.executeQuery("SELECT item, quantity, unit, available_pieces FROM stock WHERE item LIKE '%nut%'")) {
                while (rs.next()) {
                    System.out.println("Item: " + rs.getString("item") + " | Size: " + rs.getString("quantity") + " | Unit: " + rs.getString("unit") + " | Pieces: " + rs.getDouble("available_pieces"));
                }
            }
            System.out.println("\n--- NUTS HISTORY (LEDGER) ---");
            try (Statement stmt = conn.createStatement(); ResultSet rs = stmt.executeQuery("SELECT type, amount, quantity, unit, device_source, created_at FROM sales WHERE item LIKE '%nut%' ORDER BY created_at DESC")) {
                while (rs.next()) {
                    System.out.println("Type: " + rs.getString("type") + " | Addition: " + rs.getString("quantity") + " " + rs.getString("unit") + " | Source: " + rs.getString("device_source") + " | Time: " + rs.getString("created_at"));
                }
            }
        } catch (Exception e) { e.printStackTrace(); }
    }
}
