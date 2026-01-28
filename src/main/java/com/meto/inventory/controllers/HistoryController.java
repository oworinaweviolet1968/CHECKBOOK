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
    private TableColumn<HistoryItem, String> priceCol;
    @FXML
    private TableColumn<HistoryItem, String> amountCol;
    @FXML
    private TableColumn<HistoryItem, String> dateCol;

    private final DataManager dataManager = DataManager.getInstance();

    @FXML
    public void initialize() {
        // Register as listener for data changes
        dataManager.addDataChangeListener(this);

        historyFilterCombo.getItems().addAll("ALL", "NEW STOCK", "WHOLESALE", "RETAIL");
        historyFilterCombo.setValue("ALL");
        setupTableColumns();
        loadHistory();
        historyFilterCombo.setOnAction(e -> loadHistory());
    }

    @Override
    public void onDataChanged() {
        // Refresh history when data changes
        loadHistory();
    }

    private void setupTableColumns() {
        nameCol.setCellValueFactory(data -> data.getValue().nameProperty());
        itemCol.setCellValueFactory(data -> data.getValue().itemProperty());
        typeCol.setCellValueFactory(data -> data.getValue().typeUnitProperty());
        qtyCol.setCellValueFactory(data -> data.getValue().qtyProperty());
        unitCol.setCellValueFactory(data -> data.getValue().unitProperty());
        priceCol.setCellValueFactory(data -> data.getValue().priceProperty());
        amountCol.setCellValueFactory(data -> data.getValue().amountProperty());
        dateCol.setCellValueFactory(data -> data.getValue().dateProperty());

        // Center all columns
        centerColumn(nameCol);
        centerColumn(itemCol);
        centerColumn(qtyCol);
        centerColumn(unitCol);
        centerColumn(priceCol);
        centerColumn(amountCol);
        centerColumn(dateCol);

        // Custom Cell Factory for TYPE column (Badges + Centered)
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

    private void loadHistory() {
        String filter = historyFilterCombo.getValue();
        if ("ALL".equals(filter)) {
            filter = null;
        }
        ObservableList<HistoryItem> list = dataManager.getDbHelper().getHistory(filter);
        historyTable.setItems(list);
    }

    // Clean up when controller is destroyed (optional but recommended)
    public void destroy() {
        dataManager.removeDataChangeListener(this);
    }
}