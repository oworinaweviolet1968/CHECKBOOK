package com.meto.inventory.utils;

import javafx.application.Platform;
import javafx.scene.Scene;
import javafx.scene.layout.VBox;
import javafx.stage.Stage;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import java.net.URL;

import static org.junit.jupiter.api.Assertions.*;

public class CssStyleSheetTest {

    @BeforeAll
    public static void initJFX() {
        try {
            Platform.startup(() -> {});
        } catch (IllegalStateException e) {
            // Toolkit already initialized
        }
    }

    @Test
    public void testStyleSheetExistsAndLoadsWithoutErrors() {
        URL cssUrl = getClass().getResource("/com/meto/inventory/views/styles/style.css");
        assertNotNull(cssUrl, "style.css should exist in resource path");

        Platform.runLater(() -> {
            try {
                VBox root = new VBox();
                Scene scene = new Scene(root, 400, 300);
                scene.getStylesheets().add(cssUrl.toExternalForm());
                Stage stage = new Stage();
                stage.setScene(scene);
                stage.show();
                stage.close();
            } catch (Exception e) {
                fail("CSS stylesheet loading threw exception: " + e.getMessage());
            }
        });
    }
}
