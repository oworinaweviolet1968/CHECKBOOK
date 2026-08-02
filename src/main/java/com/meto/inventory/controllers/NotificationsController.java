package com.meto.inventory.controllers;

import com.meto.inventory.DataManager;
import com.meto.inventory.DatabaseHelper;
import javafx.application.Platform;
import javafx.fxml.FXML;
import javafx.geometry.Pos;
import javafx.scene.Node;
import javafx.scene.control.Button;
import javafx.scene.control.Label;
import javafx.scene.control.ListCell;
import javafx.scene.control.ListView;
import javafx.scene.layout.HBox;
import javafx.scene.layout.Priority;
import javafx.scene.layout.Region;
import javafx.scene.layout.VBox;
import javafx.scene.paint.Color;
import javafx.scene.shape.Circle;

import java.util.List;

public class NotificationsController implements DataManager.DataChangeListener {

    @FXML private Button backBtn;
    @FXML private ListView<DatabaseHelper.NotificationItem> notificationsList;
    private Runnable onBackAction;

    @FXML
    public void initialize() {
        backBtn.setOnAction(e -> {
            if (onBackAction != null) {
                onBackAction.run();
            }
        });

        notificationsList.setCellFactory(param -> new ListCell<>() {
            @Override
            protected void updateItem(DatabaseHelper.NotificationItem item, boolean empty) {
                super.updateItem(item, empty);
                if (empty || item == null) {
                    setText(null);
                    setGraphic(null);
                    setStyle("-fx-background-color: transparent; -fx-padding: 4 0;");
                } else {
                    setStyle("-fx-background-color: transparent; -fx-padding: 4 0;");
                    Node cardNode = createAuditCardNode(item);
                    setGraphic(cardNode);

                    if (!item.isRead()) {
                        DataManager.getInstance().getDbHelper().markNotificationAsRead(item.getId());
                        item.setRead(true);
                    }
                }
            }
        });

        DataManager.getInstance().addDataChangeListener(this);
        loadData();
    }

    public void setOnBackAction(Runnable action) {
        this.onBackAction = action;
    }

    private void loadData() {
        List<DatabaseHelper.NotificationItem> items = DataManager.getInstance().getDbHelper().getNotifications();
        Platform.runLater(() -> {
            notificationsList.getItems().setAll(items);
        });
    }

    @Override
    public void onDataChanged() {
        loadData();
    }

    public static String getCategory(String message) {
        if (message == null) return "OTHER";
        String lower = message.toLowerCase();
        if (lower.contains("sync") || lower.contains("cloud") || lower.contains("restore") || lower.contains("system") || lower.contains("migration") || lower.contains("zombie")) {
            return "SYSTEM";
        }
        if (lower.contains("stock") || lower.contains("added") || lower.contains("restock") || lower.contains("quantity")) {
            return "STOCK";
        }
        if (lower.contains("sale") || lower.contains("sold") || lower.contains("receipt") || lower.contains("profit")) {
            return "SALE";
        }
        if (lower.contains("debt") || lower.contains("payment") || lower.contains("paid") || lower.contains("settled")) {
            return "DEBT";
        }
        return "OTHER";
    }

    public static Node createAuditCardNode(DatabaseHelper.NotificationItem item) {
        VBox card = new VBox(6);
        card.getStyleClass().add("audit-log-card");

        String category = getCategory(item.getMessage());
        String catLower = category.toLowerCase();

        card.getStyleClass().add("audit-card-" + catLower);

        // Header Row (Category Tag + Source Tag + Unread Indicator)
        HBox headerRow = new HBox(8);
        headerRow.setAlignment(Pos.CENTER_LEFT);

        Label catBadge = new Label(category);
        catBadge.getStyleClass().addAll("audit-badge", "audit-badge-" + catLower);

        String sourceStr = item.getSource() != null && !item.getSource().trim().isEmpty() ? item.getSource() : "Desktop";
        Label sourceBadge = new Label(sourceStr);
        sourceBadge.getStyleClass().add("audit-badge-source");

        Region spacer = new Region();
        HBox.setHgrow(spacer, Priority.ALWAYS);

        headerRow.getChildren().addAll(catBadge, sourceBadge, spacer);

        if (!item.isRead()) {
            Circle unreadDot = new Circle(4, Color.web("#10B981"));
            headerRow.getChildren().add(unreadDot);
        }

        // Main Action Headline
        Label headline = new Label(item.getMessage() != null ? item.getMessage() : "");
        headline.getStyleClass().add("audit-headline");
        headline.setWrapText(true);

        // Secondary Metadata (Timestamp)
        Label timestampLabel = new Label(item.getCreatedAt() != null ? item.getCreatedAt() : "");
        timestampLabel.getStyleClass().add("audit-timestamp");

        card.getChildren().addAll(headerRow, headline, timestampLabel);
        return card;
    }
}
