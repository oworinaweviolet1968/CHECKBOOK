package com.meto.inventory.controllers;

import com.meto.inventory.DataManager;
import com.meto.inventory.DatabaseHelper;
import javafx.application.Platform;
import javafx.fxml.FXML;
import javafx.scene.control.Button;
import javafx.scene.control.ListCell;
import javafx.scene.control.ListView;
import javafx.scene.layout.VBox;
import javafx.scene.text.Text;

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
                } else {
                    VBox container = new VBox(5);
                    Text msgText = new Text(item.getMessage());
                    msgText.setStyle("-fx-font-weight: " + (item.isRead() ? "normal" : "bold") + ";");
                    Text dateText = new Text(item.getCreatedAt() + " | " + item.getSource());
                    dateText.setStyle("-fx-fill: #888; -fx-font-size: 11px;");
                    container.getChildren().addAll(msgText, dateText);
                    setGraphic(container);

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
}
