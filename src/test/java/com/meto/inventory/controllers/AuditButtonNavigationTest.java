package com.meto.inventory.controllers;

import javafx.application.Platform;
import javafx.fxml.FXMLLoader;
import javafx.scene.Node;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import java.io.IOException;

import static org.junit.jupiter.api.Assertions.*;

public class AuditButtonNavigationTest {

    @BeforeAll
    public static void initJFX() {
        try {
            Platform.startup(() -> {});
        } catch (IllegalStateException e) {
            // Toolkit already initialized
        }
    }

    @Test
    public void testNotificationsViewLoading() throws IOException {
        FXMLLoader loader = new FXMLLoader(getClass().getResource("/com/meto/inventory/views/Notifications.fxml"));
        Node node = loader.load();
        assertNotNull(node, "Notifications.fxml should load successfully");

        NotificationsController controller = loader.getController();
        assertNotNull(controller, "NotificationsController should be instantiated");

        boolean[] backClicked = {false};
        controller.setOnBackAction(() -> backClicked[0] = true);

        // Controller back button behavior
        assertFalse(backClicked[0], "Back callback should not be triggered initially");
    }
}
