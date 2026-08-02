package com.meto.inventory.utils;

import javafx.scene.Node;
import javafx.scene.layout.VBox;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

public class ToastServiceTest {

    @BeforeAll
    public static void initJFX() {
        try {
            javafx.application.Platform.startup(() -> {});
        } catch (IllegalStateException e) {
            // Toolkit already initialized
        }
    }

    @Test
    public void testCreateToastCardNodeSuccess() {
        Node node = ToastService.createToastCardNode(
                ToastService.ToastType.SUCCESS,
                "Connection Restored",
                "App is back online.",
                4.0,
                () -> {}
        );

        assertNotNull(node, "Toast card node should not be null");
        assertTrue(node instanceof VBox, "Toast card node should be a VBox container");
        assertTrue(node.getStyleClass().contains("modern-toast-card"), "Toast node should have modern-toast-card style class");
        assertTrue(node.getStyleClass().contains("toast-accent-success"), "Toast node should have toast-accent-success style class");
    }

    @Test
    public void testCreateToastCardNodeWarning() {
        Node node = ToastService.createToastCardNode(
                ToastService.ToastType.WARNING,
                "Connection Lost",
                "App is offline.",
                4.5,
                () -> {}
        );

        assertNotNull(node, "Toast card node should not be null");
        assertTrue(node.getStyleClass().contains("toast-accent-warning"), "Toast node should have toast-accent-warning style class");
    }

    @Test
    public void testCreateToastCardNodeError() {
        Node node = ToastService.createToastCardNode(
                ToastService.ToastType.ERROR,
                "Error Occurred",
                "Failed to sync.",
                5.0,
                () -> {}
        );

        assertNotNull(node, "Toast card node should not be null");
        assertTrue(node.getStyleClass().contains("toast-accent-error"), "Toast node should have toast-accent-error style class");
    }

    @Test
    public void testCreateToastCardNodeInfo() {
        Node node = ToastService.createToastCardNode(
                ToastService.ToastType.INFO,
                "Mobile Input",
                "New item synced.",
                4.0,
                () -> {}
        );

        assertNotNull(node, "Toast card node should not be null");
        assertTrue(node.getStyleClass().contains("toast-accent-info"), "Toast node should have toast-accent-info style class");
    }
}
