package com.meto.inventory;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.Statement;

public class PrintSession {
    public static void main(String[] args) throws Exception {
        String url = "jdbc:sqlite:/home/bexwrld/METO_IMS_DATA/inventory_f91a785e_b4eb_4607_9e0d_920779bfd3a4.db";
        try (Connection conn = DriverManager.getConnection(url);
             Statement stmt = conn.createStatement()) {
            
            System.out.println("--- LOCAL SALES ROWS ---");
            try (ResultSet rs = stmt.executeQuery("SELECT id, customer, item, amount, is_debt, is_paid, is_edited, sync_id FROM sales")) {
                while (rs.next()) {
                    System.out.println(String.format(
                        "Local Row: id=%d | customer=%s | item=%s | amount=%.1f | is_debt=%d | is_paid=%d | is_edited=%d | sync_id=%s",
                        rs.getInt("id"),
                        rs.getString("customer"),
                        rs.getString("item"),
                        rs.getDouble("amount"),
                        rs.getInt("is_debt"),
                        rs.getInt("is_paid"),
                        rs.getInt("is_edited"),
                        rs.getString("sync_id")
                    ));
                }
            }
        }
        System.exit(0);
    }
}
