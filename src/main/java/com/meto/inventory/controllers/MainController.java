package com.meto.inventory.controllers;

import javafx.fxml.FXML;
import javafx.fxml.FXMLLoader;
import javafx.scene.Node;
import javafx.scene.control.Button;
import javafx.scene.layout.StackPane;

import java.io.IOException;

public class MainController {

    private static MainController instance;

    @FXML
    private Button navRetail, navHistory, navInshock, navMore, navLogout;
    @FXML
    private StackPane contentPane;

    public static MainController getInstance() {
        return instance;
    }

    private Node newStockView, retailView, historyView, inShockView, debtHistoryView;

    @FXML
    private javafx.scene.control.Label backupStatusLabel;
    
    @FXML
    private com.meto.inventory.components.LoadingBar syncLoadingBar;

    @FXML
    public void initialize() throws IOException {
        instance = this;
        // Load views
        newStockView = FXMLLoader.load(getClass().getResource("/com/meto/inventory/views/NewStock.fxml"));
        retailView = FXMLLoader.load(getClass().getResource("/com/meto/inventory/views/Retail.fxml"));
        historyView = FXMLLoader.load(getClass().getResource("/com/meto/inventory/views/History.fxml"));
        inShockView = FXMLLoader.load(getClass().getResource("/com/meto/inventory/views/Inshock.fxml"));
        debtHistoryView = FXMLLoader.load(getClass().getResource("/com/meto/inventory/views/DebtHistory.fxml"));

        // Set default view and default active button style
        setView(inShockView, navInshock);

        // Wire nav actions
        // navNewStock button removed
        navRetail.setOnAction(e -> setView(retailView, navRetail));
        navHistory.setOnAction(e -> setView(historyView, navHistory));
        navInshock.setOnAction(e -> setView(inShockView, navInshock));
        navMore.setOnAction(e -> setView(debtHistoryView, navMore));
        navLogout.setOnAction(e -> handleLogout());

        // Listen for Backup Status
        com.meto.inventory.services.SupabaseService.getInstance().addStatusListener(status -> {
            javafx.application.Platform.runLater(() -> {
                if (backupStatusLabel != null && syncLoadingBar != null) {
                    if (status.contains("Syncing") || status.contains("Downloading")) {
                        syncLoadingBar.start();
                        backupStatusLabel.setText("Syncing...");
                        backupStatusLabel.setStyle("-fx-text-fill: #2196F3; -fx-font-size: 11px; -fx-font-weight: normal;");
                    } else if (status.contains("Error") || status.contains("Offline")) {
                        syncLoadingBar.stop();
                        backupStatusLabel.setText("Cloud: Offline");
                        backupStatusLabel.setStyle("-fx-text-fill: #F44336; -fx-font-size: 11px; -fx-font-weight: bold;");
                    } else {
                        // Success state (Synced, Integrated, or timestamp)
                        syncLoadingBar.stop();
                        backupStatusLabel.setText("Cloud: Connected");
                        backupStatusLabel.setStyle("-fx-text-fill: #4CAF50; -fx-font-size: 11px; -fx-font-weight: normal;");
                    }
                }
            });
        });
    }

    public void setView(Node node, Button activeBtn) {
        contentPane.getChildren().clear();
        contentPane.getChildren().add(node);
        updateNavStyles(activeBtn);
    }
    
    public void setView(Node node) {
        setView(node, null);
    }

    private void handleLogout() {
        try {
            com.meto.inventory.services.SupabaseService.getInstance().logout();
            FXMLLoader loader = new FXMLLoader(getClass().getResource("/com/meto/inventory/views/Login.fxml"));
            javafx.scene.Parent root = loader.load();
            javafx.stage.Stage stage = (javafx.stage.Stage) navLogout.getScene().getWindow();
            stage.setScene(new javafx.scene.Scene(root));
        } catch (IOException ex) {
            ex.printStackTrace();
        }
    }

    public void navigateTo(String viewName) {
        switch (viewName.toLowerCase()) {
            case "newstock":
                setView(newStockView, null);
                break;
            case "retail":
                setView(retailView, navRetail);
                break;
            case "history":
                setView(historyView, navHistory);
                break;
            case "inshock":
                setView(inShockView, navInshock);
                break;
            case "debthistory":
                setView(debtHistoryView, navMore);
                break;
        }
    }

    private void updateNavStyles(Button selectedBtn) {
        // List of all your nav buttons
        Button[] navButtons = { navRetail, navHistory, navInshock, navMore };

        for (Button btn : navButtons) {
            // Remove the active class from everyone
            btn.getStyleClass().remove("nav-active");
        }
        // Add the active class to the selected one (if not null)
        if (selectedBtn != null) {
            selectedBtn.getStyleClass().add("nav-active");
        }
    }
}