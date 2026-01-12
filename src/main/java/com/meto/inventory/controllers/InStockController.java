package com.meto.inventory.controllers;

import com.meto.inventory.DataManager;
import com.meto.inventory.models.HistoryItem;
import com.meto.inventory.models.StockItem;
import javafx.collections.ObservableList;
import javafx.fxml.FXML;
import javafx.scene.control.*;

import java.time.LocalDate;

public class InStockController implements DataManager.DataChangeListener {

    // InStock Table
    @FXML private TableView<StockItem> inStockTable;
    @FXML private TableColumn<StockItem, String> itemCol, qtyCol, unitCol, priceCol, totalValueCol;
    @FXML private Label stockTotalLabel;
    // Daily Sales Table
    @FXML private TableView<HistoryItem> dailySalesTable;
    @FXML private TableColumn<HistoryItem, String> salesItemCol, salesQtyCol, salesUnitCol, salesCustomerCol, salesAmountCol;
    @FXML private TableColumn<HistoryItem, String> salesProfitCol; // Add this FXML link
    @FXML private Label yearlyProfitLabel; // Add a label in your FXML for this
    @FXML private Button refreshBtn;
    @FXML private Label dailyTotalLabel;
    @FXML private Label dailySaleLabel; // Make sure this matches your fx:id in Scene Builder

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

        // Change this to use the price directly loaded from DB
        priceCol.setCellValueFactory(data -> data.getValue().priceProperty());

        // Use amountProperty which now contains (total * dbPrice)
        totalValueCol.setCellValueFactory(data -> data.getValue().amountProperty());
    }

    private void setupDailySalesTable() {
        salesItemCol.setCellValueFactory(data -> data.getValue().itemProperty());
        salesQtyCol.setCellValueFactory(data -> data.getValue().qtyProperty());
        salesUnitCol.setCellValueFactory(data -> data.getValue().unitProperty());
        salesCustomerCol.setCellValueFactory(data -> data.getValue().nameProperty());
        salesAmountCol.setCellValueFactory(data -> data.getValue().amountProperty());
        // Add the Profit Column
        salesProfitCol.setCellValueFactory(data -> data.getValue().profitProperty());
    }

    @Override
    public void onDataChanged() {
        loadInStock();
        loadDailySales();
    }

    private void loadInStock() {
        ObservableList<StockItem> stock = dataManager.getDbHelper().getInStock();
        inStockTable.setItems(stock);

        double grandTotal = stock.stream()
                .mapToDouble(item -> {
                    try {
                        // Pull the pre-calculated amount from the StockItem
                        return Double.parseDouble(item.getAmount().replaceAll("[^0-9.]", ""));
                    } catch (Exception e) {
                        return 0.0;
                    }
                })
                .sum();

        stockTotalLabel.setText(String.format("Total Stock Value: UGX %,.0f", grandTotal));
    }

    private void loadDailySales() {
        ObservableList<HistoryItem> todaySales = dataManager.getDbHelper().getTodaysSales();
        dailySalesTable.setItems(todaySales);

        double totalRevenue = 0;
        double totalProfit = 0;

        for (HistoryItem item : todaySales) {
            try {
                // Amount is the total money collected
                totalRevenue += Double.parseDouble(item.getAmount().replaceAll("[^0-9.]", ""));
                // Profit is what you actually earned after cost
                totalProfit += Double.parseDouble(item.getProfit().replaceAll("[^0-9.]", ""));
            } catch (Exception e) {
                e.printStackTrace();
            }
        }

        // FIX: Update the dailySaleLabel with the total revenue
        dailyTotalLabel.setText(String.format("Today's Profit: UGX %,.0f", totalProfit));

        // Ensure this fx:id matches exactly what you have in your FXML
        dailySaleLabel.setText(String.format("Today's Sales: UGX %,.0f", totalRevenue));

        // Get the current year dynamically
        int currentYear = LocalDate.now().getYear();

        double ytdProfit = dataManager.getDbHelper().getCurrentYearProfit();

// Use the variable in the string format instead of hardcoded "2026"
        yearlyProfitLabel.setText(String.format("%d Profit (YTD): UGX %,.0f", currentYear, ytdProfit));
    }

    public void destroy() {
        dataManager.removeDataChangeListener(this);
    }
}