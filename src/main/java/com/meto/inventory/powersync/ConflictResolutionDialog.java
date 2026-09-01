package com.meto.inventory.powersync;

import javafx.application.Platform;
import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.Scene;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.control.Separator;
import javafx.scene.layout.HBox;
import javafx.scene.layout.VBox;
import javafx.scene.paint.Color;
import javafx.scene.text.Font;
import javafx.scene.text.FontWeight;
import javafx.stage.Modality;
import javafx.stage.Stage;

import java.sql.Connection;

/**
 * User Conflict Resolution Dialog (User Request #3).
 *
 * Displays clear comparison:
 * - "Cloud Value: X" vs "Local Value: Y"
 * Allows the user to choose:
 * - Keep Cloud Version (Overwrites local)
 * - Keep Local Version (Re-enqueues local write)
 * Builds user trust in offline-first multi-device system.
 */
public class ConflictResolutionDialog {

    public enum ResolutionChoice {
        KEEP_CLOUD,
        KEEP_LOCAL,
        CANCEL
    }

    public static void showConflictDialog(
            String itemName,
            String conflictType,
            String cloudValue,
            String localValue,
            java.util.function.Consumer<ResolutionChoice> onResolved) {

        if (!Platform.isFxApplicationThread()) {
            Platform.runLater(() -> showConflictDialog(itemName, conflictType, cloudValue, localValue, onResolved));
            return;
        }

        Stage stage = new Stage();
        stage.initModality(Modality.APPLICATION_MODAL);
        stage.setTitle("Sync Conflict Resolution — " + itemName);
        stage.setResizable(false);

        VBox root = new VBox(15);
        root.setPadding(new Insets(20));
        root.setStyle("-fx-background-color: #ffffff; -fx-border-color: #e0e0e0; -fx-border-width: 1;");

        // Header
        Label headerLabel = new Label("Sync Conflict Detected");
        headerLabel.setFont(Font.font("System", FontWeight.BOLD, 18));
        headerLabel.setTextFill(Color.web("#d32f2f"));

        Label subtitleLabel = new Label("Changes were made on another device while offline. Please choose which version to keep for: " + itemName);
        subtitleLabel.setWrapText(true);
        subtitleLabel.setStyle("-fx-font-size: 13px; -fx-text-fill: #555555;");

        Separator sep1 = new Separator();

        // Comparison Box
        HBox comparisonBox = new HBox(20);
        comparisonBox.setAlignment(Pos.CENTER);
        comparisonBox.setPadding(new Insets(10));

        // Cloud Card
        VBox cloudCard = createValueCard("Cloud Value (Server)", cloudValue, "#e3f2fd", "#1976d2");

        // VS Label
        Label vsLabel = new Label("VS");
        vsLabel.setFont(Font.font("System", FontWeight.BOLD, 16));
        vsLabel.setTextFill(Color.web("#757575"));

        // Local Card
        VBox localCard = createValueCard("Local Value (This Device)", localValue, "#fff3e0", "#e65100");

        comparisonBox.getChildren().addAll(cloudCard, vsLabel, localCard);

        Separator sep2 = new Separator();

        // Action Buttons
        HBox buttonBox = new HBox(12);
        buttonBox.setAlignment(Pos.CENTER_RIGHT);

        Button keepCloudBtn = new Button("Use Cloud Version");
        keepCloudBtn.setStyle("-fx-background-color: #1976d2; -fx-text-fill: white; -fx-font-weight: bold; -fx-padding: 8 16;");
        keepCloudBtn.setOnAction(e -> {
            stage.close();
            if (onResolved != null) onResolved.accept(ResolutionChoice.KEEP_CLOUD);
        });

        Button keepLocalBtn = new Button("Use Local Version");
        keepLocalBtn.setStyle("-fx-background-color: #e65100; -fx-text-fill: white; -fx-font-weight: bold; -fx-padding: 8 16;");
        keepLocalBtn.setOnAction(e -> {
            stage.close();
            if (onResolved != null) onResolved.accept(ResolutionChoice.KEEP_LOCAL);
        });

        Button cancelBtn = new Button("Dismiss");
        cancelBtn.setStyle("-fx-background-color: #e0e0e0; -fx-text-fill: #333333; -fx-padding: 8 16;");
        cancelBtn.setOnAction(e -> {
            stage.close();
            if (onResolved != null) onResolved.accept(ResolutionChoice.CANCEL);
        });

        buttonBox.getChildren().addAll(cancelBtn, keepCloudBtn, keepLocalBtn);

        root.getChildren().addAll(headerLabel, subtitleLabel, sep1, comparisonBox, sep2, buttonBox);

        Scene scene = new Scene(root, 520, 360);
        stage.setScene(scene);
        stage.show();
    }

    private static VBox createValueCard(String title, String value, String bgColor, String textColor) {
        VBox card = new VBox(8);
        card.setPadding(new Insets(15));
        card.setPrefWidth(210);
        card.setStyle("-fx-background-color: " + bgColor + "; -fx-background-radius: 8; -fx-border-color: " + textColor + "; -fx-border-radius: 8; -fx-border-width: 1;");
        card.setAlignment(Pos.CENTER);

        Label titleLbl = new Label(title);
        titleLbl.setStyle("-fx-font-size: 12px; -fx-font-weight: bold; -fx-text-fill: " + textColor + ";");

        Label valLbl = new Label(value != null ? value : "N/A");
        valLbl.setFont(Font.font("System", FontWeight.BOLD, 20));
        valLbl.setStyle("-fx-text-fill: #212121;");

        card.getChildren().addAll(titleLbl, valLbl);
        return card;
    }
}
