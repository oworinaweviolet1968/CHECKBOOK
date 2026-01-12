package com.meto.inventory.controllers;

import javafx.fxml.FXML;
import javafx.fxml.FXMLLoader;
import javafx.scene.Node;
import javafx.scene.control.Button;
import javafx.scene.layout.StackPane;
import javafx.scene.layout.VBox;

import java.io.IOException;

public class MainController {

    @FXML private VBox leftNav;
    @FXML private Button navNewStock;
    @FXML private Button navRetail;
    @FXML private Button navHistory;
    @FXML private Button navInshock;

    @FXML private StackPane contentPane;

    private Node newStockView;
    private Node retailView;
    private Node historyView;
    private Node inShockView;

    @FXML
    public void initialize() throws IOException {
        // load views (separate FXML per section)
        newStockView = FXMLLoader.load(getClass().getResource("/com/meto/inventory/views/NewStock.fxml"));
        retailView = FXMLLoader.load(getClass().getResource("/com/meto/inventory/views/Retail.fxml"));
        historyView = FXMLLoader.load(getClass().getResource("/com/meto/inventory/views/History.fxml"));
        inShockView = FXMLLoader.load(getClass().getResource("/com/meto/inventory/views/Inshock.fxml"));

        // set default view
        contentPane.getChildren().add(newStockView);

        // wire nav actions
        navNewStock.setOnAction(e -> setView(newStockView));
        navRetail.setOnAction(e -> setView(retailView));
        navHistory.setOnAction(e -> setView(historyView));
        navInshock.setOnAction(e -> setView(inShockView));
    }

    private void setView(Node node) {
        contentPane.getChildren().clear();
        contentPane.getChildren().add(node);
    }
}
