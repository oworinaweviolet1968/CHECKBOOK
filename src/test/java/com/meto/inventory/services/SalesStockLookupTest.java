package com.meto.inventory.services;

import com.meto.inventory.DatabaseHelper;
import com.meto.inventory.models.StockItem;
import javafx.collections.ObservableList;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.io.File;
import java.sql.Connection;
import java.sql.PreparedStatement;

import static org.junit.jupiter.api.Assertions.*;

public class SalesStockLookupTest {

    private String testDbName = "test_sales_stock_lookup.db";
    private DatabaseHelper dbHelper;

    @BeforeEach
    public void setUp() throws Exception {
        dbHelper = new DatabaseHelper();
        dbHelper.setDatabaseName(testDbName);

        Connection conn = dbHelper.getConnection();
        try (PreparedStatement stmt = conn.prepareStatement(
                "INSERT INTO stock (sync_id, supplier, item, quantity, unit, price, available_pieces, date, is_edited) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)")) {
            stmt.setString(1, "sync_dove_400ml");
            stmt.setString(2, "Unilever");
            stmt.setString(3, "dove restoring care body lotion");
            stmt.setString(4, "400ml");
            stmt.setString(5, "Box * 12");
            stmt.setDouble(6, 15000.0);
            stmt.setDouble(7, 24.0);
            stmt.setString(8, "2026-07-31");
            stmt.executeUpdate();
        }
    }

    @AfterEach
    public void tearDown() {
        File dbFile = new File(dbHelper.getCurrentDbName());
        if (dbFile.exists()) {
            dbFile.delete();
        }
    }

    @Test
    public void testStockItemQtyPreservesVariantSize() {
        ObservableList<StockItem> stockList = dbHelper.getInStock();
        assertFalse(stockList.isEmpty(), "Stock list should contain inserted item");

        StockItem found = null;
        for (StockItem item : stockList) {
            if ("dove restoring care body lotion".equalsIgnoreCase(item.getItems())) {
                found = item;
                break;
            }
        }

        assertNotNull(found, "Item 'dove restoring care body lotion' should be found in stock");
        assertEquals("400ml", found.getQty(), "StockItem.getQty() must preserve the exact size variant '400ml'");
    }

    @Test
    public void testCleanPackagingStringPreservesVolumeVariants() {
        assertEquals("400ml", DatabaseHelper.cleanPackagingString("400ml"), "cleanPackagingString should not strip numbers from '400ml'");
        assertEquals("500g", DatabaseHelper.cleanPackagingString("500g"), "cleanPackagingString should not strip numbers from '500g'");
        assertEquals("10kg", DatabaseHelper.cleanPackagingString("10kg"), "cleanPackagingString should not strip numbers from '10kg'");
        assertEquals("Box", DatabaseHelper.cleanPackagingString("12 Box"), "cleanPackagingString should strip quantity from bulk unit '12 Box'");
    }
}
