package com.meto.inventory.utils;

import javafx.animation.KeyFrame;
import javafx.animation.KeyValue;
import javafx.animation.Timeline;
import javafx.application.Platform;
import javafx.geometry.Insets;
import javafx.geometry.Pos;
import javafx.scene.Node;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.effect.BlurType;
import javafx.scene.effect.DropShadow;
import javafx.scene.layout.*;
import javafx.scene.paint.Color;
import javafx.scene.shape.Circle;
import javafx.scene.shape.SVGPath;
import javafx.util.Duration;
import org.controlsfx.control.Notifications;

public class ToastService {

    public enum ToastType {
        SUCCESS,
        WARNING,
        ERROR,
        INFO
    }

    private static final String CSS_PATH = "/com/meto/inventory/views/styles/style.css";

    public static void showSuccess(String title, String message) {
        showToast(ToastType.SUCCESS, title, message, Pos.TOP_RIGHT, Duration.seconds(4));
    }

    public static void showWarning(String title, String message) {
        showToast(ToastType.WARNING, title, message, Pos.TOP_RIGHT, Duration.seconds(4.5));
    }

    public static void showError(String title, String message) {
        showToast(ToastType.ERROR, title, message, Pos.TOP_RIGHT, Duration.seconds(5));
    }

    public static void showInfo(String title, String message) {
        showToast(ToastType.INFO, title, message, Pos.TOP_RIGHT, Duration.seconds(4));
    }

    public static void showToast(ToastType type, String title, String message, Pos position, Duration duration) {
        if (!Platform.isFxApplicationThread()) {
            Platform.runLater(() -> showToast(type, title, message, position, duration));
            return;
        }

        Notifications notification = Notifications.create()
                .position(position != null ? position : Pos.TOP_RIGHT)
                .hideAfter(duration != null ? duration : Duration.seconds(4));

        final double durationSec = duration != null ? duration.toSeconds() : 4.0;

        Node card = createToastCardNode(type, title, message, durationSec, () -> {
            try {
                // Hide popup graphics safely
                notification.hideAfter(Duration.millis(10));
            } catch (Exception ignore) {}
        });

        notification.graphic(card);
        notification.show();
    }

    public static Node createToastCardNode(ToastType type, String title, String message, double durationSeconds, Runnable onClose) {
        VBox cardContainer = new VBox();
        cardContainer.getStyleClass().add("modern-toast-card");

        // Load stylesheet if available
        try {
            var cssUrl = ToastService.class.getResource(CSS_PATH);
            if (cssUrl != null) {
                cardContainer.getStylesheets().add(cssUrl.toExternalForm());
            }
        } catch (Exception ignore) {}

        // Accent class based on type
        String accentClass;
        String badgeColorHex;
        String accentColorHex;
        String svgPathContent;

        switch (type) {
            case SUCCESS:
                accentClass = "toast-accent-success";
                accentColorHex = "#10B981"; // Emerald
                badgeColorHex = "#D1FAE5";
                // SVG Checkmark
                svgPathContent = "M9 16.17L4.83 12l-1.42 1.41L9 19 21 7l-1.41-1.41z";
                break;
            case WARNING:
                accentClass = "toast-accent-warning";
                accentColorHex = "#F59E0B"; // Amber
                badgeColorHex = "#FEF3C7";
                // SVG Warning Exclamation Triangle
                svgPathContent = "M1 21h22L12 2 1 21zm12-3h-2v-2h2v2zm0-4h-2v-4h2v4z";
                break;
            case ERROR:
                accentClass = "toast-accent-error";
                accentColorHex = "#EF4444"; // Crimson
                badgeColorHex = "#FEE2E2";
                // SVG Error Shield / Cross
                svgPathContent = "M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-2h2v2zm0-4h-2V7h2v6z";
                break;
            case INFO:
            default:
                accentClass = "toast-accent-info";
                accentColorHex = "#3B82F6"; // Royal Blue
                badgeColorHex = "#DBEAFE";
                // SVG Info Circle 'i'
                svgPathContent = "M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm1 15h-2v-6h2v6zm0-8h-2V7h2v2z";
                break;
        }

        cardContainer.getStyleClass().add(accentClass);
        cardContainer.setPrefWidth(350);
        cardContainer.setMaxWidth(380);
        cardContainer.setPadding(new Insets(12, 14, 10, 14));
        cardContainer.setSpacing(10);

        // Styling via JavaFX properties as baseline, CSS classes enhance
        cardContainer.setStyle(
                "-fx-background-color: #FFFFFF; " +
                "-fx-background-radius: 12px; " +
                "-fx-border-radius: 12px 0 0 12px; " +
                "-fx-border-color: transparent transparent transparent " + accentColorHex + "; " +
                "-fx-border-width: 0 0 0 4px;"
        );

        DropShadow softShadow = new DropShadow();
        softShadow.setBlurType(BlurType.GAUSSIAN);
        softShadow.setColor(Color.rgb(15, 23, 42, 0.12));
        softShadow.setRadius(16);
        softShadow.setOffsetX(0);
        softShadow.setOffsetY(4);
        cardContainer.setEffect(softShadow);

        // Top Row Content (Icon + Text + Close button)
        HBox topRow = new HBox(12);
        topRow.setAlignment(Pos.TOP_LEFT);

        // 1. Icon Badge
        StackPane iconBadge = new StackPane();
        iconBadge.setMinSize(34, 34);
        iconBadge.setMaxSize(34, 34);

        Circle badgeBg = new Circle(17);
        badgeBg.setFill(Color.web(badgeColorHex));

        SVGPath iconPath = new SVGPath();
        iconPath.setContent(svgPathContent);
        iconPath.setFill(Color.web(accentColorHex));
        iconPath.setScaleX(0.85);
        iconPath.setScaleY(0.85);

        iconBadge.getChildren().addAll(badgeBg, iconPath);

        // 2. Text Box (Title + Message)
        VBox textBox = new VBox(3);
        HBox.setHgrow(textBox, Priority.ALWAYS);

        Label titleLabel = new Label(title != null ? title : "");
        titleLabel.getStyleClass().add("toast-title");
        titleLabel.setStyle("-fx-font-weight: 800; -fx-font-size: 13px; -fx-text-fill: #0F172A;");

        Label messageLabel = new Label(message != null ? message : "");
        messageLabel.getStyleClass().add("toast-description");
        messageLabel.setStyle("-fx-font-size: 12px; -fx-text-fill: #475569; -fx-line-spacing: 2px;");
        messageLabel.setWrapText(true);
        messageLabel.setMaxWidth(250);

        textBox.getChildren().addAll(titleLabel, messageLabel);

        // 3. Close 'X' Button
        Button closeBtn = new Button("×");
        closeBtn.getStyleClass().add("toast-close-btn");
        closeBtn.setStyle(
                "-fx-background-color: transparent; " +
                "-fx-text-fill: #94A3B8; " +
                "-fx-font-size: 16px; " +
                "-fx-font-weight: bold; " +
                "-fx-padding: 0 4 2 4; " +
                "-fx-cursor: hand; " +
                "-fx-background-radius: 6px;"
        );
        closeBtn.setOnMouseEntered(e -> closeBtn.setStyle(
                "-fx-background-color: #F1F5F9; " +
                "-fx-text-fill: #0F172A; " +
                "-fx-font-size: 16px; " +
                "-fx-font-weight: bold; " +
                "-fx-padding: 0 4 2 4; " +
                "-fx-cursor: hand; " +
                "-fx-background-radius: 6px;"
        ));
        closeBtn.setOnMouseExited(e -> closeBtn.setStyle(
                "-fx-background-color: transparent; " +
                "-fx-text-fill: #94A3B8; " +
                "-fx-font-size: 16px; " +
                "-fx-font-weight: bold; " +
                "-fx-padding: 0 4 2 4; " +
                "-fx-cursor: hand; " +
                "-fx-background-radius: 6px;"
        ));
        if (onClose != null) {
            closeBtn.setOnAction(e -> onClose.run());
        }

        topRow.getChildren().addAll(iconBadge, textBox, closeBtn);

        // Auto-dismiss Progress Bar Line
        Region progressBarLine = new Region();
        progressBarLine.getStyleClass().add("toast-progress-bar");
        progressBarLine.setPrefHeight(3);
        progressBarLine.setMaxHeight(3);
        progressBarLine.setStyle("-fx-background-color: " + accentColorHex + "; -fx-background-radius: 2px;");

        cardContainer.getChildren().addAll(topRow, progressBarLine);

        // Animate progress bar emptying from 100% to 0% width over durationSeconds
        if (durationSeconds > 0) {
            progressBarLine.setMinWidth(350);
            Timeline progressTimeline = new Timeline(
                new KeyFrame(Duration.ZERO, new KeyValue(progressBarLine.minWidthProperty(), 350)),
                new KeyFrame(Duration.seconds(durationSeconds), new KeyValue(progressBarLine.minWidthProperty(), 0))
            );
            progressTimeline.setCycleCount(1);
            progressTimeline.play();
        }

        return cardContainer;
    }
}
