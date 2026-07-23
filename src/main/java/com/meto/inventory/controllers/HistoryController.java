package com.meto.inventory.controllers;

import com.meto.inventory.DataManager;
import com.meto.inventory.models.HistoryItem;
import com.meto.inventory.utils.DialogHelper;
import javafx.collections.ObservableList;
import javafx.fxml.FXML;
import javafx.scene.control.*;

public class HistoryController implements DataManager.DataChangeListener {

    @FXML
    private ComboBox<String> historyFilterCombo;
    @FXML
    private TextField searchField;
    @FXML
    private DatePicker datePicker;
    @FXML
    private Button clearDateBtn;
    @FXML
    private TableView<HistoryItem> historyTable;
    @FXML
    private TableColumn<HistoryItem, String> nameCol;
    @FXML
    private TableColumn<HistoryItem, String> itemCol;
    @FXML
    private TableColumn<HistoryItem, String> typeCol;
    @FXML
    private TableColumn<HistoryItem, String> amountCol;
    @FXML
    private TableColumn<HistoryItem, String> dateCol;
    @FXML
    private TableColumn<HistoryItem, String> actionsCol;

    private final DataManager dataManager = DataManager.getInstance();
    private javafx.collections.transformation.FilteredList<HistoryItem> filteredData;

    @FXML
    public void initialize() {
        // Register as listener for data changes
        dataManager.addDataChangeListener(this);

        historyFilterCombo.getItems().addAll("ALL", "NEW STOCK", "WHOLESALE", "RETAIL", "DEBTS");
        historyFilterCombo.setValue("ALL");
        setupTableColumns();
        loadHistory();

        // Listeners for real-time filtering
        historyFilterCombo.setOnAction(e -> applyFilters());
        searchField.textProperty().addListener((obs, oldVal, newVal) -> applyFilters());
        datePicker.valueProperty().addListener((obs, oldVal, newVal) -> applyFilters());
        clearDateBtn.setOnAction(e -> datePicker.setValue(null));
    }

    @Override
    public void onDataChanged() {
        // Refresh history when data changes
        loadHistory();
    }

    private void setupTableColumns() {
        nameCol.setCellValueFactory(data -> data.getValue().nameProperty());
        itemCol.setCellValueFactory(data -> data.getValue().itemProperty());
        itemCol.setCellFactory(tc -> {
            TableCell<HistoryItem, String> cell = new TableCell<>() {
                @Override
                protected void updateItem(String item, boolean empty) {
                    super.updateItem(item, empty);
                    if (empty || item == null) {
                        setGraphic(null);
                        setText(null);
                    } else {
                        javafx.scene.text.Text text = new javafx.scene.text.Text(item);
                        text.wrappingWidthProperty().bind(tc.widthProperty().subtract(20));
                        text.setFill(javafx.scene.paint.Color.web("#374151"));
                        text.setStyle("-fx-font-size: 12px;");
                        setGraphic(text);
                        setAlignment(javafx.geometry.Pos.CENTER_LEFT);
                    }
                }
            };
            return cell;
        });

        typeCol.setCellValueFactory(data -> data.getValue().typeUnitProperty());
        amountCol.setCellValueFactory(data -> data.getValue().amountProperty());
        amountCol.setCellFactory(col -> new TableCell<HistoryItem, String>() {
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
                    setAlignment(javafx.geometry.Pos.CENTER_RIGHT);
                }
            }
        });

        dateCol.setCellValueFactory(data -> data.getValue().dateProperty());

        // Actions Column (Print Receipt)
        actionsCol.setCellFactory(col -> new TableCell<HistoryItem, String>() {
            private final Button printBtn = new Button("Print");
            {
                printBtn.getStyleClass().add("pill");
                printBtn.setStyle("-fx-font-size: 11px; -fx-padding: 4 10; -fx-background-color: #2e7d32; -fx-text-fill: white;");
                printBtn.setOnAction(e -> {
                    HistoryItem item = getTableView().getItems().get(getIndex());
                    handlePrintReceipt(item);
                });
            }

            @Override
            protected void updateItem(String item, boolean empty) {
                super.updateItem(item, empty);
                if (empty) {
                    setGraphic(null);
                } else {
                    HistoryItem historyItem = getTableView().getItems().get(getIndex());
                    // Only show print for sales (Retail, Wholesale, Debt)
                    String type = historyItem.getTypeUnit();
                    if (type != null && !type.equalsIgnoreCase("NEW STOCK")) {
                        setGraphic(printBtn);
                    } else {
                        setGraphic(null);
                    }
                    setAlignment(javafx.geometry.Pos.CENTER);
                }
            }
        });

        // Apply alignment classes for CSS header/cell alignment
        nameCol.getStyleClass().add("col-left");
        itemCol.getStyleClass().add("col-left");
        amountCol.getStyleClass().add("col-right");
        dateCol.getStyleClass().add("col-right");

        // Align remaining columns' data
        leftAlignColumn(nameCol);
        rightAlignColumn(dateCol);

        // Custom Cell Factory for TYPE column (Badges + Centered)
        typeCol.getStyleClass().add("col-center");
        typeCol.setCellFactory(column -> new TableCell<HistoryItem, String>() {
            @Override
            protected void updateItem(String item, boolean empty) {
                super.updateItem(item, empty);
                HistoryItem historyItem = getTableRow() != null ? getTableRow().getItem() : null;
                
                if (empty || item == null) {
                    setGraphic(null);
                    setText(null);
                } else {
                    Label badge = new Label(item);
                    badge.getStyleClass().add("badge");

                    if (historyItem != null && historyItem.isIsDebt() && !historyItem.isIsPaid()) {
                        badge.setText("DEBT");
                        badge.getStyleClass().add("badge-debt");
                    } else if (item.equalsIgnoreCase("NEW STOCK")) {
                        badge.getStyleClass().add("badge-stock");
                    } else if (item.equalsIgnoreCase("WHOLESALE")) {
                        badge.getStyleClass().add("badge-wholesale");
                    } else {
                        badge.getStyleClass().add("badge-retail");
                    }
                    setGraphic(badge);
                    setText(null);
                    setAlignment(javafx.geometry.Pos.CENTER);
                }
            }
        });

        // Row Factory for background coloring and context menu
        historyTable.setRowFactory(tv -> {
            TableRow<HistoryItem> row = new TableRow<>() {
                @Override
                protected void updateItem(HistoryItem item, boolean empty) {
                    super.updateItem(item, empty);
                    if (item == null || empty) {
                        getStyleClass().removeAll("history-row-new-stock", "history-row-retail", "history-row-wholesale", "history-row-debt");
                        setContextMenu(null);
                    } else {
                        String type = item.getTypeUnit();
                        getStyleClass().removeAll("history-row-new-stock", "history-row-retail", "history-row-wholesale", "history-row-debt");
                        
                        if (item.isIsDebt() && !item.isIsPaid()) {
                            getStyleClass().add("history-row-debt");
                            
                            ContextMenu menu = new ContextMenu();
                            MenuItem settleItem = new MenuItem("Settle Debt");
                            settleItem.setOnAction(e -> showSettleDebtDialog(item));
                            menu.getItems().add(settleItem);
                            setContextMenu(menu);
                        } else {
                            setContextMenu(null);
                            if (type != null) {
                                if (type.equalsIgnoreCase("NEW STOCK")) {
                                    getStyleClass().add("history-row-new-stock");
                                } else if (type.equalsIgnoreCase("RETAIL")) {
                                    getStyleClass().add("history-row-retail");
                                } else if (type.equalsIgnoreCase("WHOLESALE")) {
                                    getStyleClass().add("history-row-wholesale");
                                }
                            }
                        }
                    }
                }
            };
            return row;
        });
    }

    private <T> void leftAlignColumn(TableColumn<HistoryItem, T> column) {
        column.setCellFactory(col -> new TableCell<>() {
            @Override
            protected void updateItem(T item, boolean empty) {
                super.updateItem(item, empty);
                if (empty || item == null) {
                    setText(null);
                } else {
                    setText(item.toString());
                    setAlignment(javafx.geometry.Pos.CENTER_LEFT);
                }
            }
        });
    }



    private <T> void rightAlignColumn(TableColumn<HistoryItem, T> column) {
        column.setCellFactory(col -> new TableCell<>() {
            @Override
            protected void updateItem(T item, boolean empty) {
                super.updateItem(item, empty);
                if (empty || item == null) {
                    setText(null);
                } else {
                    setText(item.toString());
                    setAlignment(javafx.geometry.Pos.CENTER_RIGHT);
                }
            }
        });
    }

    private void loadHistory() {
        String filter = historyFilterCombo.getValue();
        if ("ALL".equals(filter)) {
            filter = null;
        }
        ObservableList<HistoryItem> list = dataManager.getDbHelper().getHistory(filter);
        filteredData = new javafx.collections.transformation.FilteredList<>(list, p -> true);
        historyTable.setItems(filteredData);
        applyFilters();
    }

    private void applyFilters() {
        if (filteredData == null)
            return;

        String typeFilter = historyFilterCombo.getValue();
        String searchText = searchField.getText() == null ? "" : searchField.getText().toLowerCase().trim();
        java.time.LocalDate selectedDate = datePicker.getValue();

        filteredData.setPredicate(item -> {
            // 1. Type Filter
            if (typeFilter != null && !"ALL".equals(typeFilter) && !"DEBTS".equals(typeFilter)) {
                if (!item.getTypeUnit().equalsIgnoreCase(typeFilter))
                    return false;
            }

            // 2. Search Filter (Item or Customer)
            if (!searchText.isEmpty()) {
                boolean matchesItem = item.getItem() != null && item.getItem().toLowerCase().contains(searchText);
                boolean matchesCustomer = item.getName() != null && item.getName().toLowerCase().contains(searchText);
                if (!matchesItem && !matchesCustomer)
                    return false;
            }

            // 3. Date Filter
            if (selectedDate != null) {
                String itemDateStr = item.getDate();
                if (itemDateStr != null) {
                    try {
                        java.time.LocalDate itemDate = java.time.LocalDate.parse(itemDateStr);
                        if (!itemDate.equals(selectedDate))
                            return false;
                    } catch (Exception e) {
                        return false;
                    }
                } else {
                    return false;
                }
            }

            return true;
        });
    }

    private void showSettleDebtDialog(HistoryItem item) {
        TextInputDialog dialog = new TextInputDialog();
        dialog.setTitle("Settle Debt");
        dialog.setHeaderText("Settling debt for " + item.getName());
        dialog.setContentText("Enter amount paid (UGX):");

        String amountStrVal = item.getAmount() == null ? "0" : item.getAmount().replaceAll("[^0-9.]", "");
        String paidStrVal = item.getPaidAmount() == null ? "0" : item.getPaidAmount().replaceAll("[^0-9.]", "");
        
        double total = amountStrVal.isEmpty() ? 0 : Double.parseDouble(amountStrVal);
        double paid = paidStrVal.isEmpty() ? 0 : Double.parseDouble(paidStrVal);
        double remaining = total - paid;

        dialog.setHeaderText(String.format("Customer: %s\nItem: %s\nTotal: UGX %,.0f\nAlready Paid: UGX %,.0f\nRemaining: UGX %,.0f",
                item.getName(), item.getItem(), total, paid, remaining));

        dialog.showAndWait().ifPresent(amountStr -> {
            try {
                double amount = Double.parseDouble(amountStr.replaceAll("[^0-9.]", ""));
                if (amount <= 0) {
                    showAlert("Please enter a valid amount.");
                    return;
                }
                dataManager.getDbHelper().markDebtAsPaid(item.getName(), amount);
                dataManager.notifyDataChanged();
                showAlert("Payment recorded successfully!");
            } catch (NumberFormatException e) {
                showAlert("Invalid amount format.");
            }
        });
    }

    private void showAlert(String message) {
        DialogHelper.showAlert(message);
    }

    private void handlePrintReceipt(HistoryItem item) {
        java.util.List<com.meto.inventory.models.SaleItem> itemsList = dataManager.getDbHelper().getReceiptItems(item.getId());
        if (itemsList.isEmpty()) {
            showAlert("Could not retrieve items for this receipt.");
            return;
        }

        javafx.collections.ObservableList<com.meto.inventory.models.SaleItem> observableItems = javafx.collections.FXCollections.observableArrayList(itemsList);
        
        double total = itemsList.stream().mapToDouble(i -> {
            try {
                return Double.parseDouble(i.getAmount().replaceAll("[^0-9.]", ""));
            } catch (Exception e) {
                return 0;
            }
        }).sum();

        com.meto.inventory.services.ReceiptPrinterService.printReceipt(
            observableItems, 
            item.getName(), 
            String.format("%,.0f", total),
            item.getDate()
        );
        showAlert("Receipt sent to printer!");
    }

    // Clean up when controller is destroyed (optional but recommended)
    public void destroy() {
        dataManager.removeDataChangeListener(this);
    }
}