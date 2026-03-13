package com.meto.inventory.controllers;

import com.meto.inventory.DataManager;
import com.meto.inventory.models.HistoryItem;
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
    private TableView<HistoryItem> historyTable;
    @FXML
    private TableColumn<HistoryItem, String> nameCol;
    @FXML
    private TableColumn<HistoryItem, String> itemCol;
    @FXML
    private TableColumn<HistoryItem, String> typeCol;
    @FXML
    private TableColumn<HistoryItem, String> qtyCol;
    @FXML
    private TableColumn<HistoryItem, String> unitCol;
    @FXML
    private TableColumn<HistoryItem, String> amountCol;
    @FXML
    private TableColumn<HistoryItem, String> dateCol;

    private final DataManager dataManager = DataManager.getInstance();
    private javafx.collections.transformation.FilteredList<HistoryItem> filteredData;

    @FXML
    public void initialize() {
        // Register as listener for data changes
        dataManager.addDataChangeListener(this);

        historyFilterCombo.getItems().addAll("ALL", "NEW STOCK", "WHOLESALE", "RETAIL");
        historyFilterCombo.setValue("ALL");
        setupTableColumns();
        loadHistory();

        // Listeners for real-time filtering
        historyFilterCombo.setOnAction(e -> applyFilters());
        searchField.textProperty().addListener((obs, oldVal, newVal) -> applyFilters());
        datePicker.valueProperty().addListener((obs, oldVal, newVal) -> applyFilters());
    }

    @Override
    public void onDataChanged() {
        // Refresh history when data changes
        loadHistory();
    }

    private void setupTableColumns() {
        nameCol.setCellValueFactory(data -> data.getValue().nameProperty());
        itemCol.setCellValueFactory(data -> data.getValue().itemProperty());
        itemCol.setCellFactory(col -> new TableCell<HistoryItem, String>() {
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

        typeCol.setCellValueFactory(data -> data.getValue().typeUnitProperty());
        qtyCol.setCellValueFactory(data -> data.getValue().qtyProperty());
        qtyCol.setCellFactory(col -> new TableCell<HistoryItem, String>() {
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

        unitCol.setCellValueFactory(data -> data.getValue().unitProperty());
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

        // Apply alignment classes for CSS header/cell alignment
        nameCol.getStyleClass().add("col-left");
        itemCol.getStyleClass().add("col-left");
        qtyCol.getStyleClass().add("col-right");
        unitCol.getStyleClass().add("col-center");
        amountCol.getStyleClass().add("col-right");
        dateCol.getStyleClass().add("col-right");

        // Align remaining columns' data
        leftAlignColumn(nameCol);
        centerColumn(unitCol);
        rightAlignColumn(dateCol);
        rightAlignColumn(qtyCol);

        // Custom Cell Factory for TYPE column (Badges + Centered)
        typeCol.getStyleClass().add("col-center");
        typeCol.setCellFactory(column -> new TableCell<>() {
            @Override
            protected void updateItem(String item, boolean empty) {
                super.updateItem(item, empty);
                if (empty || item == null) {
                    setGraphic(null);
                    setText(null);
                } else {
                    Label badge = new Label(item);
                    badge.getStyleClass().add("badge"); // Base if needed, or just specific

                    if (item.equalsIgnoreCase("NEW STOCK")) {
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

        // Row Factory for background coloring
        historyTable.setRowFactory(tv -> new TableRow<HistoryItem>() {
            @Override
            protected void updateItem(HistoryItem item, boolean empty) {
                super.updateItem(item, empty);
                if (item == null || empty) {
                    getStyleClass().removeAll("history-row-new-stock", "history-row-retail", "history-row-wholesale");
                } else {
                    String type = item.getTypeUnit();
                    getStyleClass().removeAll("history-row-new-stock", "history-row-retail", "history-row-wholesale");
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

    private <T> void centerColumn(TableColumn<HistoryItem, T> column) {
        column.setCellFactory(col -> new TableCell<>() {
            @Override
            protected void updateItem(T item, boolean empty) {
                super.updateItem(item, empty);
                if (empty || item == null) {
                    setText(null);
                } else {
                    setText(item.toString());
                    setAlignment(javafx.geometry.Pos.CENTER);
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
            if (typeFilter != null && !"ALL".equals(typeFilter)) {
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

    // Clean up when controller is destroyed (optional but recommended)
    public void destroy() {
        dataManager.removeDataChangeListener(this);
    }
}