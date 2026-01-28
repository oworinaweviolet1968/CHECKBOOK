package com.meto.inventory.utils;

import javafx.scene.control.Alert;
import javafx.scene.control.ButtonType;
import javafx.scene.control.DialogPane;
import javafx.stage.Stage;
import javafx.stage.StageStyle;

import java.util.Optional;

public class DialogHelper {

    private static final String CSS_PATH = "/com/meto/inventory/views/styles/style.css";

    public static void showAlert(String message) {
        showAlert("Information", message);
    }

    public static void showAlert(String title, String message) {
        Alert alert = new Alert(Alert.AlertType.INFORMATION);
        styleAlert(alert);
        alert.setTitle(title);
        alert.setHeaderText(null);
        alert.setContentText(message);
        alert.showAndWait();
    }

    public static boolean showConfirm(String title, String header, String content) {
        Alert alert = new Alert(Alert.AlertType.CONFIRMATION);
        styleAlert(alert);
        alert.setTitle(title);
        alert.setHeaderText(header);
        alert.setContentText(content);

        Optional<ButtonType> result = alert.showAndWait();
        return result.isPresent() && result.get() == ButtonType.OK;
    }

    private static void styleAlert(Alert alert) {
        DialogPane dialogPane = alert.getDialogPane();
        dialogPane.getStylesheets().add(DialogHelper.class.getResource(CSS_PATH).toExternalForm());
        dialogPane.getStyleClass().add("modern-alert");

        // Optional: Remove default header icon if desired, or style it
        // alert.initStyle(StageStyle.UNDECORATED); // Uncomment for frameless look
    }
}
