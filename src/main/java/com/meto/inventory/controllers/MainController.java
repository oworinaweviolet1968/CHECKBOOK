package com.meto.inventory.controllers;

import javafx.fxml.FXML;
import javafx.fxml.FXMLLoader;
import javafx.scene.Node;
import javafx.scene.control.Button;
import javafx.scene.layout.StackPane;
import javafx.scene.layout.VBox;

import java.io.IOException;

public class MainController {

    @FXML private Button navNewStock, navRetail, navHistory, navInshock;
    @FXML private StackPane contentPane;

    private Node newStockView, retailView, historyView, inShockView;

    @FXML
    public void initialize() throws IOException {
        // Load views
        newStockView = FXMLLoader.load(getClass().getResource("/com/meto/inventory/views/NewStock.fxml"));
        retailView = FXMLLoader.load(getClass().getResource("/com/meto/inventory/views/Retail.fxml"));
        historyView = FXMLLoader.load(getClass().getResource("/com/meto/inventory/views/History.fxml"));
        inShockView = FXMLLoader.load(getClass().getResource("/com/meto/inventory/views/Inshock.fxml"));

        // Set default view and default active button style
        setView(newStockView, navNewStock);

        // Wire nav actions
        navNewStock.setOnAction(e -> setView(newStockView, navNewStock));
        navRetail.setOnAction(e -> setView(retailView, navRetail));
        navHistory.setOnAction(e -> setView(historyView, navHistory));
        navInshock.setOnAction(e -> setView(inShockView, navInshock));
    }

    private void setView(Node node, Button activeBtn) {
        contentPane.getChildren().clear();
        contentPane.getChildren().add(node);
        updateNavStyles(activeBtn);
    }

    private void updateNavStyles(Button selectedBtn) {
        // List of all your nav buttons
        Button[] navButtons = {navNewStock, navRetail, navHistory, navInshock};

        for (Button btn : navButtons) {
            // Remove the active class from everyone
            btn.getStyleClass().remove("nav-active");
        }
        // Add the active class to the selected one
        selectedBtn.getStyleClass().add("nav-active");
    }
}