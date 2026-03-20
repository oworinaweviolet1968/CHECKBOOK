package com.meto.inventory.controllers;

import com.meto.inventory.DataManager;
import com.meto.inventory.models.HistoryItem;
import com.meto.inventory.models.StockItem;
import javafx.collections.ObservableList;
import javafx.fxml.FXML;
import javafx.scene.control.*;
import javafx.scene.layout.VBox;

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
    private TableColumn<HistoryItem, String> salesItemCol, salesQtyCol, salesCustomerCol, salesAmountCol;
    @FXML
    private Button refreshBtn, addItemBtn, viewAllBtn;
    @FXML
    private Label dailySaleLabel, stockCountLabel, transactionCountLabel, lowStockNoticeLabel, inventorySublabel,
            salesSublabel;
    @FXML
    private TextField searchField;
    @FXML
    private TableColumn<StockItem, String> statusCol;

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
            
            Thread syncThread = new Thread(() -> {
                String dbName = dataManager.getCurrentDbName();
                boolean hasData = dataManager.getDbHelper().hasData();
                com.meto.inventory.services.SupabaseService.getInstance().syncOnLogin(dbName, hasData);
                javafx.application.Platform.runLater(() -> {
                    dataManager.notifyDataChanged();
                });
            });
            syncThread.setDaemon(true);
            syncThread.start();
        });

        searchField.textProperty().addListener((obs, oldVal, newVal) -> {
            filterInventory(newVal);
        });

        addItemBtn.setOnAction(e -> {
            if (MainController.getInstance() != null) {
                MainController.getInstance().navigateTo("newstock");
            }
        });

        viewAllBtn.setOnAction(e -> {
            if (MainController.getInstance() != null) {
                MainController.getInstance().navigateTo("history");
            }
        });
    }

    private void filterInventory(String query) {
        if (query == null || query.isEmpty()) {
            loadInStock();
            return;
        }

        String lowerQuery = query.toLowerCase();
        ObservableList<StockItem> allStock = dataManager.getDbHelper().getInStock();
        ObservableList<StockItem> filtered = allStock
                .filtered(item -> item.getItems().toLowerCase().contains(lowerQuery));
        inStockTable.setItems(filtered);
    }

    private void setupInStockTable() {
        itemCol.setCellValueFactory(data -> data.getValue().itemsProperty());
        itemCol.getStyleClass().add("col-left");
        itemCol.setCellFactory(col -> new TableCell<StockItem, String>() {
            @Override
            protected void updateItem(String item, boolean empty) {
                super.updateItem(item, empty);
                if (empty || item == null) {
                    setGraphic(null);
                    setText(null);
                } else {
                    Label label = new Label(item);
                    label.getStyleClass().add("bold-label");
                    setGraphic(label);
                    setAlignment(javafx.geometry.Pos.CENTER_LEFT);
                }
            }
        });

        qtyCol.getStyleClass().add("col-left");
        qtyCol.setCellValueFactory(data -> data.getValue().qtyProperty());
        qtyCol.setCellFactory(col -> new TableCell<StockItem, String>() {
            @Override
            protected void updateItem(String item, boolean empty) {
                super.updateItem(item, empty);
                if (empty || item == null) {
                    setGraphic(null);
                    setText(null);
                } else {
                    Label label = new Label(item);
                    label.getStyleClass().add("size-pill");
                    setGraphic(label);
                    setAlignment(javafx.geometry.Pos.CENTER_LEFT);
                }
            }
        });

        unitCol.getStyleClass().add("col-left");
        unitCol.setCellValueFactory(data -> data.getValue().unitProperty());
        unitCol.setCellFactory(col -> new TableCell<StockItem, String>() {
            @Override
            protected void updateItem(String item, boolean empty) {
                super.updateItem(item, empty);
                if (empty || item == null) {
                    setGraphic(null);
                    setText(null);
                } else {
                    javafx.scene.layout.HBox box = new javafx.scene.layout.HBox(4);
                    box.setAlignment(javafx.geometry.Pos.CENTER_LEFT);
                    if (item.contains("(")) {
                        int idx = item.indexOf("(");
                        String mainStr = item.substring(0, idx).trim();
                        String subStr = item.substring(idx).trim();
                        Label mainL = new Label(mainStr);
                        mainL.setStyle("-fx-font-weight: bold; -fx-text-fill: -fx-text-main;");
                        Label subL = new Label(subStr);
                        subL.setStyle("-fx-text-fill: -fx-text-muted;");
                        box.getChildren().addAll(mainL, subL);
                    } else {
                        Label mainL = new Label(item);
                        mainL.setStyle("-fx-font-weight: bold; -fx-text-fill: -fx-text-main;");
                        box.getChildren().add(mainL);
                    }
                    setGraphic(box);
                    setAlignment(javafx.geometry.Pos.CENTER_LEFT);
                }
            }
        });

        statusCol.setCellFactory(col -> new TableCell<StockItem, String>() {
            @Override
            protected void updateItem(String item, boolean empty) {
                super.updateItem(item, empty);
                if (empty || getTableRow() == null || getTableRow().getItem() == null) {
                    setGraphic(null);
                    setText(null);
                } else {
                    StockItem stockItem = getTableRow().getItem();
                    String avail = stockItem.getUnit().toLowerCase();
                    Label badge = new Label();
                    badge.getStyleClass().add("status-badge");

                    if (avail.contains("low") || avail.contains("0 pc")) {
                        badge.setText("Low Stock");
                        badge.getStyleClass().add("status-low");
                    } else if (avail.contains("sacks") || avail.contains("boxes") || avail.contains("pcs")) {
                        badge.setText("In Stock");
                        badge.getStyleClass().add("status-in-stock");
                    } else {
                        badge.setText("Medium");
                        badge.getStyleClass().add("status-medium");
                    }
                    setGraphic(badge);
                    setAlignment(javafx.geometry.Pos.CENTER);
                }
            }
        });
    }

    private void setupDailySalesTable() {
        salesItemCol.setCellValueFactory(data -> data.getValue().itemProperty());
        salesItemCol.setCellFactory(col -> new TableCell<HistoryItem, String>() {
            @Override
            protected void updateItem(String item, boolean empty) {
                super.updateItem(item, empty);
                if (empty || item == null || getTableRow() == null || getTableRow().getItem() == null) {
                    setGraphic(null);
                    setText(null);
                } else {
                    HistoryItem hi = getTableRow().getItem();
                    VBox box = new VBox(2);
                    
                    javafx.scene.layout.HBox nameBox = new javafx.scene.layout.HBox(6);
                    nameBox.setAlignment(javafx.geometry.Pos.BOTTOM_LEFT);
                    
                    Label nameLabel = new Label(item);
                    nameLabel.getStyleClass().add("bold-label");
                    
                    Label sizeLabel = new Label(hi.getQty() != null ? hi.getQty() : "");
                    sizeLabel.setStyle("-fx-text-fill: -fx-text-muted; -fx-font-size: 11px;");
                    
                    nameBox.getChildren().addAll(nameLabel, sizeLabel);

                    Label timeLabel = new Label(hi.getDate()); // For now use date, ideally extract time
                    timeLabel.getStyleClass().add("sub-detail");

                    box.getChildren().addAll(nameBox, timeLabel);
                    box.setAlignment(javafx.geometry.Pos.CENTER_LEFT);
                    setGraphic(box);
                    setAlignment(javafx.geometry.Pos.CENTER_LEFT);
                }
            }
        });

        salesQtyCol.setCellValueFactory(data -> data.getValue().unitProperty()); // Use unit property for the sales quantity column (e.g. 2 pcs)
        salesQtyCol.setCellFactory(col -> new TableCell<HistoryItem, String>() {
            @Override
            protected void updateItem(String item, boolean empty) {
                super.updateItem(item, empty);
                if (empty || item == null) {
                    setGraphic(null);
                    setText(null);
                } else {
                    Label label = new Label(item);
                    label.setStyle("-fx-font-weight: 800; -fx-text-fill: -fx-text-main;");
                    setGraphic(label);
                    setAlignment(javafx.geometry.Pos.CENTER_LEFT);
                }
            }
        });
        salesCustomerCol.setCellValueFactory(data -> data.getValue().nameProperty());
        salesCustomerCol.setCellFactory(col -> new TableCell<HistoryItem, String>() {
            @Override
            protected void updateItem(String item, boolean empty) {
                super.updateItem(item, empty);
                if (empty || item == null) {
                    setText(null);
                } else {
                    setText(item);
                    setStyle("-fx-text-fill: -fx-text-muted;"); // Match mocked lightness for customer
                    setAlignment(javafx.geometry.Pos.CENTER_LEFT);
                }
            }
        });

        salesAmountCol.setCellValueFactory(data -> data.getValue().amountProperty());
        salesAmountCol.setCellFactory(col -> new TableCell<HistoryItem, String>() {
            @Override
            protected void updateItem(String item, boolean empty) {
                super.updateItem(item, empty);
                if (empty || item == null) {
                    setGraphic(null);
                    setText(null);
                } else {
                    Label label = new Label("UGX " + item);
                    label.getStyleClass().add("amount-vibrant");
                    setGraphic(label);
                    setAlignment(javafx.geometry.Pos.CENTER_LEFT);
                }
            }
        });
    }

    @Override
    public void onDataChanged() {
        javafx.application.Platform.runLater(() -> {
            loadInStock();
            loadDailySales();
        });
    }

    private void loadInStock() {
        ObservableList<StockItem> stock = dataManager.getDbHelper().getInStock();
        inStockTable.setItems(stock);

        stockCountLabel.setText(String.valueOf(stock.size()));
        inventorySublabel.setText("Smart Units • " + stock.size() + " items");

        long lowStockCount = stock.stream()
                .filter(s -> s.getUnit().toLowerCase().contains("low") || s.getUnit().toLowerCase().contains("0 pc"))
                .count();
        lowStockNoticeLabel.setText(lowStockCount + " items running low");
    }

    private void loadDailySales() {
        ObservableList<HistoryItem> todaySales = dataManager.getDbHelper().getTodaysSales();
        dailySalesTable.setItems(todaySales);

        transactionCountLabel.setText(String.valueOf(todaySales.size()));

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
        dailySaleLabel.setText(String.format("UGX %,.0f", totalRevenue));
        salesSublabel.setText(todaySales.size() + " transactions • UGX " + String.format("%,.0f", totalRevenue));
    }

    public void destroy() {
        dataManager.removeDataChangeListener(this);
    }
}