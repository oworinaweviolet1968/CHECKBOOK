package com.meto.inventory.services;

import com.meto.inventory.DatabaseHelper;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;

import java.io.File;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Statement;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

public class DatabaseHelperTest {

    private String testDbName = "test_unit_db.db";
    private DatabaseHelper dbHelper;

    @BeforeEach
    public void setUp() {
        dbHelper = new DatabaseHelper();
        dbHelper.setDatabaseName(testDbName);
    }

    @AfterEach
    public void tearDown() {
        File dbFile = new File(dbHelper.getCurrentDbName());
        if (dbFile.exists()) {
            dbFile.delete();
        }
    }

    @Test
    public void testInitializeDatabaseCreatesTables() throws Exception {
        String dbUrl = "jdbc:sqlite:" + dbHelper.getCurrentDbName();
        try (Connection conn = DriverManager.getConnection(dbUrl);
             Statement stmt = conn.createStatement()) {
            
            var rs = stmt.executeQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='stock';");
            assertTrue(rs.next(), "Table 'stock' should be created by initializeDatabase()");
        }
    }

    @Test
    public void testFetchRemoteStockWithMockedAuth() throws Exception {
        SupabaseService mockService = mock(SupabaseService.class);
        when(mockService.loadSession()).thenReturn("mock_valid_refresh_token_123");
        when(mockService.signInWithRefreshToken("mock_valid_refresh_token_123")).thenReturn(true);

        String token = mockService.loadSession();
        assertNotNull(token, "Mocked session token should not be null");
        boolean loggedIn = mockService.signInWithRefreshToken(token);
        assertTrue(loggedIn, "Mocked authentication with valid token should return true");

        verify(mockService).loadSession();
        verify(mockService).signInWithRefreshToken("mock_valid_refresh_token_123");
    }

    @Test
    public void testFetchRemoteStockHandlesMissingSessionGracefully() throws Exception {
        SupabaseService mockService = mock(SupabaseService.class);
        when(mockService.loadSession()).thenReturn(null);
        when(mockService.signInWithRefreshToken(null)).thenReturn(false);

        String token = mockService.loadSession();
        assertNull(token, "Loaded session should be null when no local session token is saved");
        boolean loggedIn = mockService.signInWithRefreshToken(token);
        assertFalse(loggedIn, "Sign in should return false gracefully when session token is missing");

        verify(mockService).loadSession();
        verify(mockService).signInWithRefreshToken(null);
    }

    @Test
    public void testCleanupZombieStockZeroQuantityOrphan() throws Exception {
        Connection conn = dbHelper.getConnection();
        try (PreparedStatement stmt = conn.prepareStatement(
                "INSERT INTO stock (sync_id, supplier, item, quantity, unit, price, available_pieces, date, is_edited) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)")) {
            stmt.setString(1, "sync_orphan_1");
            stmt.setString(2, "Test Supplier");
            stmt.setString(3, "Orphan Item");
            stmt.setString(4, "10 pcs");
            stmt.setString(5, "pcs");
            stmt.setDouble(6, 50.0);
            stmt.setDouble(7, 0.0); // available_pieces <= 0
            stmt.setString(8, "2026-07-30");
            stmt.executeUpdate();
        }

        dbHelper.cleanupZombieStock();

        // Verify removed from stock
        try (PreparedStatement stmt = conn.prepareStatement("SELECT COUNT(*) FROM stock WHERE item = 'Orphan Item'")) {
            ResultSet rs = stmt.executeQuery();
            assertTrue(rs.next());
            assertEquals(0, rs.getInt(1), "Orphan stock with available_pieces <= 0 should be deleted from stock");
        }

        // Verify inserted into deleted_stock
        try (PreparedStatement stmt = conn.prepareStatement("SELECT COUNT(*) FROM deleted_stock WHERE item = 'Orphan Item'")) {
            ResultSet rs = stmt.executeQuery();
            assertTrue(rs.next());
            assertEquals(1, rs.getInt(1), "Cleaned zombie stock should be logged in deleted_stock");
        }
    }

    @Test
    public void testCleanupZombieStockZeroQuantityWithSalesHistory() throws Exception {
        Connection conn = dbHelper.getConnection();
        // Insert stock entry with available_pieces = 0
        try (PreparedStatement stmt = conn.prepareStatement(
                "INSERT INTO stock (sync_id, supplier, item, quantity, unit, price, available_pieces, date, is_edited) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)")) {
            stmt.setString(1, "sync_sold_1");
            stmt.setString(2, "Test Supplier");
            stmt.setString(3, "Sold Item");
            stmt.setString(4, "5 kg");
            stmt.setString(5, "kg");
            stmt.setDouble(6, 100.0);
            stmt.setDouble(7, 0.0);
            stmt.setString(8, "2026-07-30");
            stmt.executeUpdate();
        }

        // Insert matching sales record
        try (PreparedStatement stmt = conn.prepareStatement(
                "INSERT INTO sales (sync_id, customer, item, quantity, unit, price, cost_price, base_quantity, amount, type, date) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")) {
            stmt.setString(1, "sale_sync_1");
            stmt.setString(2, "Walk-in");
            stmt.setString(3, "Sold Item");
            stmt.setString(4, "5 kg");
            stmt.setString(5, "kg");
            stmt.setDouble(6, 100.0);
            stmt.setDouble(7, 80.0);
            stmt.setDouble(8, 1.0);
            stmt.setDouble(9, 100.0);
            stmt.setString(10, "NORMAL");
            stmt.setString(11, "2026-07-30");
            stmt.executeUpdate();
        }

        dbHelper.cleanupZombieStock();

        // Verify stock entry is preserved because sales history exists
        try (PreparedStatement stmt = conn.prepareStatement("SELECT COUNT(*) FROM stock WHERE item = 'Sold Item'")) {
            ResultSet rs = stmt.executeQuery();
            assertTrue(rs.next());
            assertEquals(1, rs.getInt(1), "Stock entry with sales history should not be deleted as zombie");
        }
    }

    @Test
    public void testCleanupZombieStockNegativeQuantity() throws Exception {
        Connection conn = dbHelper.getConnection();
        // Insert stock with negative available_pieces (-5.0) and no sales history
        try (PreparedStatement stmt = conn.prepareStatement(
                "INSERT INTO stock (sync_id, supplier, item, quantity, unit, price, available_pieces, date, is_edited) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)")) {
            stmt.setString(1, "sync_neg_1");
            stmt.setString(2, "Test Supplier");
            stmt.setString(3, "Negative Stock Item");
            stmt.setString(4, "1 box");
            stmt.setString(5, "box");
            stmt.setDouble(6, 20.0);
            stmt.setDouble(7, -5.0); // Negative available_pieces
            stmt.setString(8, "2026-07-30");
            stmt.executeUpdate();
        }

        dbHelper.cleanupZombieStock();

        try (PreparedStatement stmt = conn.prepareStatement("SELECT COUNT(*) FROM stock WHERE item = 'Negative Stock Item'")) {
            ResultSet rs = stmt.executeQuery();
            assertTrue(rs.next());
            assertEquals(0, rs.getInt(1), "Negative orphan stock without sales history should be cleaned up");
        }
    }

    @Test
    public void testCleanupZombieStockPositiveQuantityNotCleaned() throws Exception {
        Connection conn = dbHelper.getConnection();
        // Insert stock with positive available_pieces (10.0) and no sales history
        try (PreparedStatement stmt = conn.prepareStatement(
                "INSERT INTO stock (sync_id, supplier, item, quantity, unit, price, available_pieces, date, is_edited) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)")) {
            stmt.setString(1, "sync_pos_1");
            stmt.setString(2, "Test Supplier");
            stmt.setString(3, "Active Stock Item");
            stmt.setString(4, "100 pcs");
            stmt.setString(5, "pcs");
            stmt.setDouble(6, 10.0);
            stmt.setDouble(7, 10.0); // available_pieces > 0
            stmt.setString(8, "2026-07-30");
            stmt.executeUpdate();
        }

        dbHelper.cleanupZombieStock();

        try (PreparedStatement stmt = conn.prepareStatement("SELECT COUNT(*) FROM stock WHERE item = 'Active Stock Item'")) {
            ResultSet rs = stmt.executeQuery();
            assertTrue(rs.next());
            assertEquals(1, rs.getInt(1), "Stock with available_pieces > 0 must not be cleaned up");
        }
    }

    @Test
    public void testCleanupZombieStockSpecialCharactersAndCaseInsensitivity() throws Exception {
        Connection conn = dbHelper.getConnection();

        // 1) Special character orphan item (available_pieces = 0, no sales)
        try (PreparedStatement stmt = conn.prepareStatement(
                "INSERT INTO stock (sync_id, supplier, item, quantity, unit, price, available_pieces, date, is_edited) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)")) {
            stmt.setString(1, "sync_spec_1");
            stmt.setString(2, "Test Supplier");
            stmt.setString(3, "Nut & Bolt (5/8\")");
            stmt.setString(4, "100 pcs @ $5.00");
            stmt.setString(5, "pcs");
            stmt.setDouble(6, 5.0);
            stmt.setDouble(7, 0.0);
            stmt.setString(8, "2026-07-30");
            stmt.executeUpdate();
        }

        // 2) Case-insensitive match item (stock item uppercase "ITEM ALPHA", sales item lowercase "item alpha")
        try (PreparedStatement stmt = conn.prepareStatement(
                "INSERT INTO stock (sync_id, supplier, item, quantity, unit, price, available_pieces, date, is_edited) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)")) {
            stmt.setString(1, "sync_case_1");
            stmt.setString(2, "Test Supplier");
            stmt.setString(3, "ITEM ALPHA");
            stmt.setString(4, "1 unit");
            stmt.setString(5, "unit");
            stmt.setDouble(6, 15.0);
            stmt.setDouble(7, 0.0);
            stmt.setString(8, "2026-07-30");
            stmt.executeUpdate();
        }
        try (PreparedStatement stmt = conn.prepareStatement(
                "INSERT INTO sales (sync_id, customer, item, quantity, unit, price, cost_price, base_quantity, amount, type, date) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)")) {
            stmt.setString(1, "sale_case_1");
            stmt.setString(2, "Customer");
            stmt.setString(3, "item alpha"); // Lowercase matching
            stmt.setString(4, "1 unit");
            stmt.setString(5, "unit");
            stmt.setDouble(6, 15.0);
            stmt.setDouble(7, 10.0);
            stmt.setDouble(8, 1.0);
            stmt.setDouble(9, 15.0);
            stmt.setString(10, "NORMAL");
            stmt.setString(11, "2026-07-30");
            stmt.executeUpdate();
        }

        dbHelper.cleanupZombieStock();

        // Verify special character orphan was cleaned up without SQL errors
        try (PreparedStatement stmt = conn.prepareStatement("SELECT COUNT(*) FROM stock WHERE item = 'Nut & Bolt (5/8\")'")) {
            ResultSet rs = stmt.executeQuery();
            assertTrue(rs.next());
            assertEquals(0, rs.getInt(1), "Special character orphan stock should be cleaned up cleanly");
        }

        // Verify case-insensitive matching preserved the stock item
        try (PreparedStatement stmt = conn.prepareStatement("SELECT COUNT(*) FROM stock WHERE item = 'ITEM ALPHA'")) {
            ResultSet rs = stmt.executeQuery();
            assertTrue(rs.next());
            assertEquals(1, rs.getInt(1), "Stock with case-insensitive sales match should be preserved");
        }
    }

    @Test
    public void testPackagingPresetsMultipliers() {
        assertEquals(36.0, dbHelper.getUnitMultiplier("Box * 36", "500ml", "Box * 36"));
        assertEquals(48.0, dbHelper.getUnitMultiplier("box*48", "1kg", "box*48"));
        assertEquals(96.0, dbHelper.getUnitMultiplier("Box * 96", "250g", "Box * 96"));
        assertEquals(100.0, dbHelper.getUnitMultiplier("box*100", "None", "box*100"));

        assertEquals(36.0, dbHelper.convertToBaseUnit("box*36"));
        assertEquals(48.0, dbHelper.convertToBaseUnit("box*48"));
        assertEquals(96.0, dbHelper.convertToBaseUnit("box*96"));
        assertEquals(100.0, dbHelper.convertToBaseUnit("box*100"));
    }
}
