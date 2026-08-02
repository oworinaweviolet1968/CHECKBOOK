package com.meto.inventory.controllers;

import com.meto.inventory.DatabaseHelper;
import javafx.application.Platform;
import javafx.scene.Node;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

public class AuditTrailViewTest {

    @BeforeAll
    public static void initJFX() {
        try {
            Platform.startup(() -> {});
        } catch (IllegalStateException e) {
            // Toolkit already initialized
        }
    }

    @Test
    public void testCategoryClassification() {
        assertEquals("STOCK", NotificationsController.getCategory("Added 50 pcs of New Item to stock"));
        assertEquals("SALE", NotificationsController.getCategory("Sale completed for Customer UGX 25,000"));
        assertEquals("DEBT", NotificationsController.getCategory("Debt payment collected UGX 10,000"));
        assertEquals("SYSTEM", NotificationsController.getCategory("Cloud sync restored local stock data"));
        assertEquals("OTHER", NotificationsController.getCategory("General notification message"));
    }

    @Test
    public void testCreateAuditCardNode() {
        DatabaseHelper.NotificationItem item = new DatabaseHelper.NotificationItem(
                1,
                "Restocked 20 boxes of dove lotion",
                "Desktop",
                "2026-07-31 20:30",
                false
        );

        Node card = NotificationsController.createAuditCardNode(item);
        assertNotNull(card, "Audit card node should not be null");
        assertTrue(card.getStyleClass().contains("audit-log-card"), "Audit card should have audit-log-card style class");
        assertTrue(card.getStyleClass().contains("audit-card-stock"), "Audit card for stock restock should have audit-card-stock style class");
    }
}
