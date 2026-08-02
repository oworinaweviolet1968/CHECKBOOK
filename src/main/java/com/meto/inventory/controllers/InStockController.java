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
    private VBox dailySalesListContainer;
    @FXML
    private TableColumn<HistoryItem, String> salesItemCol, salesQtyCol, salesCustomerCol, salesAmountCol;
    @FXML
    private Button refreshBtn, addItemBtn, viewAllBtn;
    @FXML
    private Label dailySaleLabel, dailyDebtLabel, stockCountLabel, transactionCountLabel, lowStockNoticeLabel, inventorySublabel,
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
                com.meto.inventory.services.SupabaseService service = com.meto.inventory.services.SupabaseService.getInstance();
                String dbName = dataManager.getCurrentDbName();
                boolean hasData = dataManager.getDbHelper().hasData();

                // 1. Try to push local changes
                service.uploadDatabase(dbName);
                
                // 2. Pull remote changes (merges if cloud is newer)
                service.syncOnLogin(dbName, hasData, true);

                javafx.application.Platform.runLater(() -> {
                    dataManager.notifyDataChanged(false);
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
                    Label label = new Label(com.meto.inventory.DatabaseHelper.cleanPackagingString(item));
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
                    javafx.scene.layout.HBox box = new javafx.scene.layout.HBox(6);
                    box.setAlignment(javafx.geometry.Pos.CENTER_LEFT);

                    String mainText = item != null ? item.trim() : "";
                    Label mainL = new Label(mainText);
                    mainL.setStyle("-fx-font-weight: 800; -fx-text-fill: #0F172A; -fx-font-size: 12px;");
                    box.getChildren().add(mainL);

                    if (getTableRow() != null && getTableRow().getItem() != null) {
                        StockItem stockItem = getTableRow().getItem();
                        String rawBulk = stockItem.getBulkUnit();
                        if (rawBulk == null || rawBulk.isEmpty()) {
                            rawBulk = dataManager.getDbHelper().getRawStockUnit(stockItem.getItems(), stockItem.getQty());
                        }
                        String cleanPkg = com.meto.inventory.DatabaseHelper.cleanPackagingString(rawBulk);
                        if (cleanPkg != null && !cleanPkg.isEmpty() && !"Standard".equalsIgnoreCase(cleanPkg)) {
                            Label pkgBadge = new Label(cleanPkg);
                            pkgBadge.getStyleClass().add("dash-pkg-badge");
                            box.getChildren().add(pkgBadge);
                        }
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
        if (dailySalesTable != null && salesItemCol != null) {
            dailySalesTable.setItems(dataManager.getDbHelper().getTodaysSales());
        }
        if (salesItemCol != null) {
            salesItemCol.setCellValueFactory(data -> data.getValue().itemProperty());
        }
        if (salesQtyCol != null) {
            salesQtyCol.setCellValueFactory(data -> data.getValue().unitProperty());
        }
        if (salesCustomerCol != null) {
            salesCustomerCol.setCellValueFactory(data -> data.getValue().nameProperty());
        }
        if (salesAmountCol != null) {
            salesAmountCol.setCellValueFactory(data -> data.getValue().amountProperty());
        }
    }

    @Override
    public void onDataChanged() {
        System.out.println("DASHBOARD: onDataChanged triggered!");
        javafx.application.Platform.runLater(() -> {
            loadInStock();
            loadDailySales();
        });
    }

    private void loadInStock() {
        ObservableList<StockItem> stock = dataManager.getDbHelper().getInStock();
        System.out.println("DASHBOARD: loadInStock count = " + stock.size() + " from DB: " + dataManager.getCurrentDbName());
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
        System.out.println("DASHBOARD: loadDailySales count = " + todaySales.size());
        if (dailySalesTable != null) {
            dailySalesTable.setItems(todaySales);
        }
        renderDailySalesList(todaySales);

        transactionCountLabel.setText(String.valueOf(todaySales.size()));

        double totalRevenue = 0;
        double totalDebt = 0;

        for (HistoryItem item : todaySales) {
            try {
                // Amount is the total money collected
                double amount = Double.parseDouble(item.getAmount().replaceAll("[^0-9.]", ""));
                if (item.isIsDebt()) {
                    totalDebt += amount;
                } else {
                    totalRevenue += amount;
                }
            } catch (Exception e) {
                e.printStackTrace();
            }
        }

        // Ensure this fx:id matches exactly what you have in your FXML
        dailySaleLabel.setText(String.format("UGX %,.0f", totalRevenue));
        if (dailyDebtLabel != null) {
            dailyDebtLabel.setText(String.format("Debt: UGX %,.0f", totalDebt));
        }
        salesSublabel.setText(todaySales.size() + " transactions • UGX " + String.format("%,.0f", totalRevenue));
    }

    private void renderDailySalesList(ObservableList<HistoryItem> todaySales) {
        if (dailySalesListContainer == null) return;
        dailySalesListContainer.getChildren().clear();

        if (todaySales == null || todaySales.isEmpty()) {
            VBox emptyBox = new VBox(6);
            emptyBox.setStyle("-fx-padding: 20; -fx-alignment: center;");
            Label title = new Label("No Sales Recorded Today");
            title.setStyle("-fx-font-weight: 800; -fx-font-size: 13px; -fx-text-fill: #64748B;");
            Label sub = new Label("Completed transactions will appear here in real-time.");
            sub.setStyle("-fx-font-size: 11px; -fx-text-fill: #94A3B8;");
            emptyBox.getChildren().addAll(title, sub);
            dailySalesListContainer.getChildren().add(emptyBox);
            return;
        }

        for (HistoryItem item : todaySales) {
            dailySalesListContainer.getChildren().add(createDailySaleCard(item));
        }
    }

    private javafx.scene.layout.HBox createDailySaleCard(HistoryItem item) {
        javafx.scene.layout.HBox card = new javafx.scene.layout.HBox(10);
        card.setAlignment(javafx.geometry.Pos.CENTER_LEFT);
        card.getStyleClass().add("dashboard-sale-card");

        // Left info block
        VBox leftBox = new VBox(2);
        javafx.scene.layout.HBox.setHgrow(leftBox, javafx.scene.layout.Priority.ALWAYS);

        // Customer name + Debt indicator
        javafx.scene.layout.HBox topRow = new javafx.scene.layout.HBox(6);
        topRow.setAlignment(javafx.geometry.Pos.CENTER_LEFT);
        Label custLabel = new Label(item.getName() == null || item.getName().isEmpty() ? "Walk-in Customer" : item.getName());
        custLabel.setStyle("-fx-font-weight: 800; -fx-text-fill: #0F172A; -fx-font-size: 12px;");
        topRow.getChildren().add(custLabel);

        if (item.isIsDebt()) {
            Label debtBadge = new Label("DEBT");
            debtBadge.setStyle("-fx-background-color: #FEF2F2; -fx-text-fill: #DC2626; -fx-font-size: 9px; -fx-font-weight: 900; -fx-padding: 1 6; -fx-background-radius: 4; -fx-border-color: #FCA5A5; -fx-border-radius: 4;");
            topRow.getChildren().add(debtBadge);
        }

        // Item details: Item Name + Size badge + Unit
        javafx.scene.layout.HBox subRow = new javafx.scene.layout.HBox(6);
        subRow.setAlignment(javafx.geometry.Pos.CENTER_LEFT);
        Label itemLabel = new Label(item.getItem());
        itemLabel.setStyle("-fx-font-size: 11px; -fx-text-fill: #475569; -fx-font-weight: 600;");

        Label qtyBadge = new Label(item.getUnit() == null ? "" : item.getUnit());
        qtyBadge.getStyleClass().addAll("badge", "badge-stock");
        qtyBadge.setStyle("-fx-font-size: 10px; -fx-padding: 1 5;");

        subRow.getChildren().addAll(itemLabel, qtyBadge);
        leftBox.getChildren().addAll(topRow, subRow);

        // Right amount block
        VBox rightBox = new VBox();
        rightBox.setAlignment(javafx.geometry.Pos.CENTER_RIGHT);
        Label amountLabel = new Label("UGX " + item.getAmount());
        if (item.isIsDebt()) {
            amountLabel.setStyle("-fx-font-weight: 900; -fx-font-size: 13px; -fx-text-fill: #DC2626;");
        } else {
            amountLabel.setStyle("-fx-font-weight: 900; -fx-font-size: 13px; -fx-text-fill: #10B981;");
        }
        rightBox.getChildren().add(amountLabel);

        card.getChildren().addAll(leftBox, rightBox);
        return card;
    }

    public void destroy() {
        dataManager.removeDataChangeListener(this);
    }
}