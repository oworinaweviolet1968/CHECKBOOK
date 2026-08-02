package com.meto.inventory.utils;

import javafx.scene.control.Alert;
import javafx.scene.control.ButtonType;
import javafx.scene.control.DialogPane;

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

    public static void showError(String title, String userFriendlyMessage) {
        Alert alert = new Alert(Alert.AlertType.ERROR);
        styleAlert(alert);
        alert.setTitle(title != null ? title : "Error");
        alert.setHeaderText(null);
        // Clean error message: strip internal stack trace or raw SQL exception lines
        String cleanMessage = userFriendlyMessage;
        if (cleanMessage != null && (cleanMessage.contains("SQLException") || cleanMessage.contains("java.") || cleanMessage.contains("at com."))) {
            cleanMessage = "An unexpected system error occurred. Please check your inputs and try again.";
        }
        alert.setContentText(cleanMessage != null ? cleanMessage : "An error occurred.");
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
        // Remove default blue question mark/info graphic
        alert.setGraphic(null);

        DialogPane dialogPane = alert.getDialogPane();
        try {
            var cssUrl = DialogHelper.class.getResource(CSS_PATH);
            if (cssUrl != null) {
                dialogPane.getStylesheets().add(cssUrl.toExternalForm());
            }
        } catch (Exception ignore) {}

        dialogPane.getStyleClass().add("modern-alert");

        if (alert.getAlertType() == Alert.AlertType.ERROR) {
            dialogPane.getStyleClass().add("modern-alert-error");
        } else if (alert.getAlertType() == Alert.AlertType.WARNING || alert.getAlertType() == Alert.AlertType.CONFIRMATION) {
            dialogPane.getStyleClass().add("modern-alert-warning");
        } else {
            dialogPane.getStyleClass().add("modern-alert-success");
        }

        // Style OK and Cancel buttons cleanly
        javafx.scene.Node okButton = dialogPane.lookupButton(ButtonType.OK);
        if (okButton != null) {
            okButton.getStyleClass().add("btn-dialog-ok");
        }
        javafx.scene.Node cancelButton = dialogPane.lookupButton(ButtonType.CANCEL);
        if (cancelButton != null) {
            cancelButton.getStyleClass().add("btn-dialog-cancel");
        }
    }
}
