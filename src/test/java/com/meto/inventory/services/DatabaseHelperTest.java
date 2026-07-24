package com.meto.inventory.services;

import com.meto.inventory.DatabaseHelper;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import java.io.File;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.Statement;

import static org.junit.jupiter.api.Assertions.*;

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
}
