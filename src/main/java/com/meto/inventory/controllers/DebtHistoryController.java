package com.meto.inventory.controllers;

import com.meto.inventory.DataManager;
import com.meto.inventory.models.DebtPaymentLog;
import com.meto.inventory.models.HistoryItem;
import javafx.collections.ObservableList;
import javafx.fxml.FXML;
import javafx.scene.control.*;
import javafx.beans.property.SimpleStringProperty;
import java.time.LocalDate;

public class DebtHistoryController implements DataManager.DataChangeListener {

    @FXML private Label totalDebtLabel, debtorCountLabel, collectedTodayLabel;
    @FXML private TableView<HistoryItem> unsettledTable;
    @FXML private TableColumn<HistoryItem, String> customerCol, itemCol, totalCol, paidCol, remainingCol, dateCol, actionsCol;
    @FXML private TableView<DebtPaymentLog> paymentLogsTable;
    @FXML private TableColumn<DebtPaymentLog, String> logCustomerCol, logAmountCol, logDateCol;
    @FXML private TableView<HistoryItem> settledTable;
    @FXML private TableColumn<HistoryItem, String> settledCustomerCol, settledItemCol, settledAmountCol, settledDateCol;
    @FXML private Button refreshBtn;

    private DataManager dataManager;

    @FXML
    public void initialize() {
        dataManager = DataManager.getInstance();
        dataManager.addDataChangeListener(this);

        setupTableColumns();
        loadData();

        refreshBtn.setOnAction(e -> loadData());
    }

    private void setupTableColumns() {
        // Unsettled Table
        customerCol.setCellValueFactory(cellData -> cellData.getValue().nameProperty());
        itemCol.setCellValueFactory(cellData -> cellData.getValue().itemProperty());
        totalCol.setCellValueFactory(cellData -> cellData.getValue().amountProperty());
        paidCol.setCellValueFactory(cellData -> cellData.getValue().paidAmountProperty());
        remainingCol.setCellValueFactory(cellData -> {
            try {
                double total = Double.parseDouble(cellData.getValue().getAmount().replaceAll("[^0-9.]", ""));
                double paid = Double.parseDouble(cellData.getValue().getPaidAmount().replaceAll("[^0-9.]", ""));
                return new SimpleStringProperty(String.format("%,.0f", total - paid));
            } catch (Exception e) {
                return new SimpleStringProperty("0");
            }
        });
        dateCol.setCellValueFactory(cellData -> cellData.getValue().dateProperty());

        // Color coding and formatting
        totalCol.setCellFactory(column -> new TableCell<HistoryItem, String>() {
            @Override protected void updateItem(String item, boolean empty) {
                super.updateItem(item, empty);
                if (item == null || empty) { setText(null); setStyle(""); }
                else { setText(item); setStyle("-fx-text-fill: #111827; -fx-font-weight: bold;"); }
            }
        });

        paidCol.setCellFactory(column -> new TableCell<HistoryItem, String>() {
            @Override protected void updateItem(String item, boolean empty) {
                super.updateItem(item, empty);
                if (item == null || empty) { setText(null); setStyle(""); }
                else { setText(item); setStyle("-fx-text-fill: #10B981; -fx-font-weight: bold;"); }
            }
        });

        remainingCol.setCellFactory(column -> new TableCell<HistoryItem, String>() {
            @Override protected void updateItem(String item, boolean empty) {
                super.updateItem(item, empty);
                if (item == null || empty) { setText(null); setStyle(""); }
                else { setText(item); setStyle("-fx-text-fill: #EF4444; -fx-font-weight: bold;"); }
            }
        });

        // Pay Button Column
        actionsCol.setCellFactory(column -> new TableCell<HistoryItem, String>() {
            private final Button payBtn = new Button("Pay Debt");
            {
                payBtn.getStyleClass().add("btn-success");
                payBtn.setStyle("-fx-font-size: 11px; -fx-padding: 4 10;");
                payBtn.setOnAction(e -> {
                    HistoryItem item = getTableView().getItems().get(getIndex());
                    showSettleDebtDialog(item);
                });
            }

            @Override protected void updateItem(String item, boolean empty) {
                super.updateItem(item, empty);
                if (empty) setGraphic(null);
                else setGraphic(payBtn);
            }
        });

        // Payment Logs Table
        logCustomerCol.setCellValueFactory(cellData -> cellData.getValue().customerProperty());
        logAmountCol.setCellValueFactory(cellData -> new SimpleStringProperty(String.format("%,.0f", cellData.getValue().getAmountPaid())));
        logDateCol.setCellValueFactory(cellData -> cellData.getValue().dateProperty());

        // Settled Table
        settledCustomerCol.setCellValueFactory(cellData -> cellData.getValue().nameProperty());
        settledItemCol.setCellValueFactory(cellData -> cellData.getValue().itemProperty());
        settledAmountCol.setCellValueFactory(cellData -> cellData.getValue().amountProperty());
        settledDateCol.setCellValueFactory(cellData -> cellData.getValue().dateProperty());
    }

    private void loadData() {
        // Summary Cards
        double totalDebt = dataManager.getDbHelper().getTotalOutstandingDebt();
        int debtorCount = dataManager.getDbHelper().getDebtorCount();
        double collectedToday = dataManager.getDbHelper().getDebtCollectedToday();

        totalDebtLabel.setText(String.format("UGX %,.0f", totalDebt));
        debtorCountLabel.setText(String.valueOf(debtorCount));
        collectedTodayLabel.setText(String.format("UGX %,.0f", collectedToday));

        // Tables
        unsettledTable.setItems(dataManager.getDbHelper().getHistory("DEBTS"));
        paymentLogsTable.setItems(dataManager.getDbHelper().getRecentDebtPayments());
        settledTable.setItems(dataManager.getDbHelper().getSettledDebts());
    }

    @Override
    public void onDataChanged() {
        javafx.application.Platform.runLater(this::loadData);
    }

    private void showSettleDebtDialog(HistoryItem item) {
        TextInputDialog dialog = new TextInputDialog("");
        dialog.setTitle("Settle Debt");
        dialog.setHeaderText("Settling debt for: " + item.getName());
        dialog.setContentText("Enter amount to pay (Total: " + item.getAmount() + ", Paid: " + item.getPaidAmount() + "):");

        // Styling the dialog
        DialogPane dialogPane = dialog.getDialogPane();
        dialogPane.getStylesheets().add(getClass().getResource("/com/meto/inventory/views/styles/style.css").toExternalForm());
        dialogPane.getStyleClass().add("modern-alert");

        java.util.Optional<String> result = dialog.showAndWait();
        result.ifPresent(amountStr -> {
            try {
                double amount = Double.parseDouble(amountStr);
                dataManager.getDbHelper().markSaleAsPaid(item.getId(), amount);
                loadData(); 
            } catch (NumberFormatException e) {
                com.meto.inventory.utils.DialogHelper.showAlert("Invalid input. Please enter a number.");
            }
        });
    }
}
