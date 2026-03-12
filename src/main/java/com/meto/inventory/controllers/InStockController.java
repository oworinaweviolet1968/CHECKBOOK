package com.meto.inventory.controllers;

import com.meto.inventory.DataManager;
import com.meto.inventory.models.HistoryItem;
import com.meto.inventory.models.StockItem;
import javafx.collections.ObservableList;
import javafx.fxml.FXML;
import javafx.scene.control.*;

public class InStockController implements DataManager.DataChangeListener {

    // InStock Table
    @FXML
    private TableView<StockItem> inStockTable;
    @FXML
    private TableColumn<StockItem, String> itemCol, qtyCol, unitCol;
    // Daily Sales Table
    @FXML
    private TableView<HistoryItem> dailySalesTable;
    @FXML
    private TableColumn<HistoryItem, String> salesItemCol, salesQtyCol, salesUnitCol, salesCustomerCol, salesAmountCol;
    @FXML
    private Button refreshBtn;
    @FXML
    private Label dailySaleLabel; // Make sure this matches your fx:id in Scene Builder

    private final DataManager dataManager = DataManager.getInstance();

    @FXML
    public void initialize() {
        dataManager.addDataChangeListener(this);
        setupInStockTable();
        setupDailySalesTable();
        loadInStock();
        loadDailySales();

        refreshBtn.setOnAction(e -> {
            loadInStock();
            loadDailySales();
        });
    }

    private void setupInStockTable() {
        itemCol.setCellValueFactory(data -> data.getValue().itemsProperty());
        qtyCol.setCellValueFactory(data -> data.getValue().qtyProperty()); // This is 'SIZE' in your UI
        unitCol.setCellValueFactory(data -> data.getValue().unitProperty()); // This is 'AVAILABLE' in UI
    }

    private void setupDailySalesTable() {
        salesItemCol.setCellValueFactory(data -> data.getValue().itemProperty());
        salesQtyCol.setCellValueFactory(data -> data.getValue().qtyProperty());
        salesUnitCol.setCellValueFactory(data -> data.getValue().unitProperty());
        salesCustomerCol.setCellValueFactory(data -> data.getValue().nameProperty());
        salesAmountCol.setCellValueFactory(data -> data.getValue().amountProperty());
    }

    @Override
    public void onDataChanged() {
        loadInStock();
        loadDailySales();
    }

    private void loadInStock() {
        ObservableList<StockItem> stock = dataManager.getDbHelper().getInStock();
        inStockTable.setItems(stock);
    }

    private void loadDailySales() {
        ObservableList<HistoryItem> todaySales = dataManager.getDbHelper().getTodaysSales();
        dailySalesTable.setItems(todaySales);

        double totalRevenue = 0;

        for (HistoryItem item : todaySales) {
            try {
                // Amount is the total money collected
                totalRevenue += Double.parseDouble(item.getAmount().replaceAll("[^0-9.]", ""));
            } catch (Exception e) {
                e.printStackTrace();
            }
        }

        // Ensure this fx:id matches exactly what you have in your FXML
        dailySaleLabel.setText(String.format("Today's Total Sales: UGX %,.0f", totalRevenue));
    }

    public void destroy() {
        dataManager.removeDataChangeListener(this);
    }
}