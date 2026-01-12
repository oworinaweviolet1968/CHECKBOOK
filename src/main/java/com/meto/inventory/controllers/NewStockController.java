package com.meto.inventory.controllers;

import com.meto.inventory.DataManager;
import com.meto.inventory.models.StockItem;
import javafx.beans.binding.Bindings;
import javafx.collections.FXCollections;
import javafx.collections.ObservableList;
import javafx.fxml.FXML;
import javafx.scene.control.*;
import javafx.scene.input.KeyEvent;
import javafx.scene.layout.HBox;

import java.time.LocalDate;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class NewStockController {

    @FXML private TextField supplierNameField;
    @FXML private TextField unitField;
    @FXML private TextField priceField;
    @FXML private Button addButton;
    @FXML private Button saveButton;
    @FXML private TableView<StockItem> newStockTable;
    @FXML private TableColumn<StockItem, Void> actionColumn;
    @FXML private Label totalAmountLabel;
    @FXML private HBox qtyButtonsBox;
    @FXML private HBox unitButtonsBox;
    @FXML private Label supplierErrorLabel, itemErrorLabel, qtyErrorLabel, unitErrorLabel, priceErrorLabel;
    @FXML private ComboBox<String> itemsComboBox;
    @FXML private ComboBox<String> qtyComboBox;

    private final ObservableList<StockItem> items = FXCollections.observableArrayList();
    private final DataManager dataManager = DataManager.getInstance();

    @FXML
    public void initialize() {
        refreshDropdowns();

        // When an item is selected, load its existing sizes (e.g., 330ml, 500ml)
        itemsComboBox.setOnAction(e -> {
            String selectedItem = itemsComboBox.getValue();
            if (selectedItem != null) {
                ObservableList<String> sizes = dataManager.getDbHelper().getItemSizes(selectedItem);
                qtyComboBox.setItems(sizes);
            }
        });

        // AUTO-FILL PRICE: When size is selected, find the last recorded price
        qtyComboBox.setOnAction(e -> {
            String item = itemsComboBox.getValue();
            String size = qtyComboBox.getValue();
            if (item != null && size != null) {
                double lastPrice = dataManager.getDbHelper().getLastRecordedPrice(item, size);
                if (lastPrice > 0) {
                    priceField.setText(String.format("%.0f", lastPrice));
                    // We keep this price constant; the 'per' logic will handle the math
                }
            }
        });

        priceField.textProperty().addListener((obs, oldVal, newVal) -> {
            // If the user manually fixes the price, hide the error
            unitErrorLabel.setVisible(false);
            unitErrorLabel.setManaged(false);
        });

        // configure table columns in FXML (already defined there)
        newStockTable.setItems(items);

//        // sample data
//        items.add(new StockItem("Lugazi sugar", "1kg", "6 boxes", "50,000", "300,000"));

        // qty field: prevent typing letters manually; allow digits and dot only
        qtyComboBox.addEventFilter(KeyEvent.KEY_TYPED, this::filterQtyInput);
        // When user starts typing, hide the error labels
        qtyComboBox.getEditor().textProperty().addListener((obs, oldVal, newVal) -> {
            qtyErrorLabel.setVisible(false);
            qtyErrorLabel.setManaged(false);
        });

        unitField.textProperty().addListener((obs, oldVal, newVal) -> {
            unitErrorLabel.setVisible(false);
            unitErrorLabel.setManaged(false);
        });

        // create quick unit buttons (kg, ml, l)
        createQtyQuickButtons();

        // create unit quick buttons (pcs, half doz, carton, dozen, box)
        createUnitQuickButtons();

        addButton.setOnAction(e -> onAdd());
        saveButton.setOnAction(e -> onSave());

        // bind total
        totalAmountLabel.textProperty().bind(Bindings.createStringBinding(() -> {
            double sum = items.stream().mapToDouble(s -> {
                String amtStr = s.getAmount().replaceAll("[^0-9.]", "");
                if (amtStr.isEmpty()) return 0.0;
                try { return Double.parseDouble(amtStr); } catch (NumberFormatException ex) { return 0.0; }
            }).sum();
            if (sum == 0) return "TOTAL AMOUNT : ";
            return String.format("TOTAL AMOUNT : UGX %,d", Math.round(sum));
        }, items));

        actionColumn.setCellFactory(col -> new TableCell<>() {
            private final Button deleteButton = new Button("Delete");
            {
                deleteButton.getStyleClass().add("btn-red");
                deleteButton.setOnAction(e -> {
                    StockItem item = getTableView().getItems().get(getIndex());
                    // delete or edit logic here
                    items.remove(item);
                });
            }
            @Override
            protected void updateItem(Void item, boolean empty) {
                super.updateItem(item, empty);
                setGraphic(empty ? null : deleteButton);
            }
        });
    }

    private void refreshDropdowns() {
        ObservableList<String> availableItems = dataManager.getDbHelper().getAvailableItems();
        itemsComboBox.setItems(availableItems);
    }

    private void createQtyQuickButtons() {
        String[] quick = {"g","kg","ml","l"};
        for (String q : quick) {
            Button b = new Button(q);
            b.getStyleClass().add("pill");
            b.setOnAction(evt -> appendUnitToQty(q));
            qtyButtonsBox.getChildren().add(b);
        }
    }

    private void createUnitQuickButtons() {
        String[] quick = {"pcs / sack", "half doz", "carton", "dozen", "box"};
        for (String u : quick) {
            Button b = new Button(u);
            b.getStyleClass().add("pill");
            b.setOnAction(evt -> appendUnit(u));
            unitButtonsBox.getChildren().add(b);
        }
    }

    private void appendUnit(String unit) {
        String selectedItem = itemsComboBox.getEditor().getText();
        String selectedSize = qtyComboBox.getEditor().getText();

        // 1. Keep the number currently typed (e.g., "5")
        String currentText = unitField.getText().trim();
        String numberPart = currentText.replaceAll("[^0-9.]", "");
        if (numberPart.isEmpty()) numberPart = "1";

        // 2. Fetch the recorded piece price from DB
        java.util.Map<String, Object> stockInfo = dataManager.getDbHelper().getStockPriceInfo(selectedItem, selectedSize);

        if (stockInfo.isEmpty()) {
            unitField.setText(numberPart + " " + unit);
            return;
        }

        // Your DB now stores the 'Price Per Piece' (e.g., 2083)
        double pricePerPiece = (double) stockInfo.get("price");
        String clickedUnit = unit.toLowerCase().trim();

        // 3. AUTO-FILL LOGIC

        if (clickedUnit.contains("pcs")) {
            // If clicking PCS: Show the price exactly as it is in the DB
            unitField.setText(numberPart + " pcs");
            priceField.setText(String.format("%.0f", pricePerPiece));
            unitErrorLabel.setVisible(false);
        }
        else {
            // If clicking DOZEN / BOX / CARTON:
            // Multiply the piece price by the multiplier (e.g., 2083 * 12 = 25000)
            double multiplier = dataManager.getDbHelper().convertToBaseUnit(clickedUnit);

            if (multiplier > 1) {
                double bulkPrice = pricePerPiece * multiplier;
                unitField.setText(numberPart + " " + unit);
                priceField.setText(String.format("%.0f", bulkPrice));
                unitErrorLabel.setVisible(false);
            } else {
                // If the multiplier is 1 but it's not "pcs", it's an unrecognized unit
                unitField.setText(numberPart + " " + unit);
                priceField.clear();
                unitErrorLabel.setText("* Unrecognized unit for auto-pricing.");
                unitErrorLabel.setVisible(true);
            }
        }
    }

    private String getUnitValue(String unit) {
        switch (unit.toLowerCase()) {
            case "pcs": return "1";
            case "half doz": return "1";
            case "carton": return "1";
            case "dozen": return "1";
            case "box": return "1";
            default: return "1";
        }
    }

    private void filterQtyInput(KeyEvent evt) {
        String ch = evt.getCharacter();
        if (!ch.matches("[0-9\\.]")) {
            evt.consume();
        }
    }

    private void appendUnitToQty(String unit) {
        String currentQty = qtyComboBox.getEditor().getText().trim();

        // If the field is empty, do nothing
        if (currentQty.isEmpty()) {
            return;
        }

        // Check if the current input already has a unit (kg, ml, or l)
        if (currentQty.endsWith("kg") || currentQty.endsWith("ml") || currentQty.endsWith("l")) {
            // If it already has a unit, replace the existing unit
            qtyComboBox.getEditor().setText(currentQty.replaceAll("(g|kg|ml|l)$", "") + unit);
        } else {
            // If no unit exists, simply append the unit
            qtyComboBox.getEditor().setText(currentQty + unit);
        }
    }

    private void onAdd() {
        String supplier = supplierNameField.getText().trim();
        itemErrorLabel.setVisible(false);
        itemErrorLabel.setManaged(false);
        qtyErrorLabel.setVisible(false);
        qtyErrorLabel.setManaged(false);
        unitErrorLabel.setVisible(false);
        unitErrorLabel.setManaged(false);
        priceErrorLabel.setVisible(false);
        priceErrorLabel.setManaged(false);

        String itemName = itemsComboBox.getEditor().getText().trim();
        String qtyRaw = qtyComboBox.getEditor().getText().trim().toLowerCase();
        String unitText = unitField.getText().trim().toLowerCase();
        String priceRaw = priceField.getText().trim().replaceAll("[^0-9.]", "");

        // 2. Define allowed patterns
        // Matches numbers followed by g, kg, ml, or l (e.g., 500ml, 1.5l)
        String sizePattern = ".*\\d+(g|kg|ml|l)$";
        // Matches numbers followed by pcs, doz, carton, box, or sack
        String countPattern = ".*\\d+.*(pcs|doz|carton|box|sack|dozen).*";

        boolean hasError = false;

        if (itemName.isEmpty()) {
            itemErrorLabel.setVisible(true);
            itemErrorLabel.setManaged(true);
            hasError = true;
        }
        // 3. Validate QTY (Size)
        if (!qtyRaw.matches(sizePattern)) {
            qtyErrorLabel.setText("* Missing size unit (e.g., 500ml, 1kg)");
            qtyErrorLabel.setVisible(true);
            qtyErrorLabel.setManaged(true);
            hasError = true;
        }

        // 4. Validate UNIT (Count)
        if (!unitText.matches(countPattern)) {
            unitErrorLabel.setText("* Missing count unit (e.g., 10 pcs, 2 doz)");
            unitErrorLabel.setVisible(true);
            unitErrorLabel.setManaged(true);
            hasError = true;
        }
        if (priceRaw.isEmpty()) {
            priceErrorLabel.setVisible(true);
            priceErrorLabel.setManaged(true);
            hasError = true;
        }

        if (hasError) return;

        double price;
        try {
            price = Double.parseDouble(priceRaw);
        } catch (NumberFormatException ex) {
            showAlert("Invalid price.");
            return;
        }

        // Parse the unit quantity - this is what should be multiplied with price
        double unitQty = 1.0;
        try {
            // Try to parse the unit field as a number
            String unitNum = unitText.replaceAll("[^0-9.]", "");
            if (!unitNum.isEmpty()) {
                unitQty = Double.parseDouble(unitNum);
            }
        } catch (NumberFormatException ex) {
            // If unit field doesn't contain a number, default to 1
            unitQty = 1.0;
        }

        // Calculate amount: unit quantity * price
        double amount = unitQty * price;
        String amountStr = String.format("%,.0f", amount);
        String priceStr = String.format("%,.0f", price);

        StockItem si = new StockItem(itemName, qtyRaw, unitText, priceStr, amountStr);
        items.add(si);

        // clear fields (keep supplier)
        itemsComboBox.getEditor().clear();
        qtyComboBox.getEditor().clear();
        unitField.clear();
        priceField.clear();
    }

    private void onSave() {
        String supplier = supplierNameField.getText().trim();
        if (supplier.isEmpty()) {
            supplierErrorLabel.setVisible(true);
            supplierErrorLabel.setManaged(true);
            return;
        } else {
            supplierErrorLabel.setVisible(false);
            supplierErrorLabel.setManaged(false);
        }

        if (items.isEmpty()) {
            // You might still want an alert here just to say "No items in table"
            showAlert("Please Fill in item to continue!");
            return;
        }

        // Check for existing items and merge quantities
        for (StockItem s : newStockTable.getItems()) {
            String item = s.getItems();
            String qty = s.getQty();
            String unit = s.getUnit();
            double price = 0.0;
            try {
                price = Double.parseDouble(s.getPrice().replaceAll("[^0-9.]", ""));
            } catch (Exception ex) { /* ignore */ }

            // Check if this item with same size already exists
            if (dataManager.getDbHelper().itemExists(item, qty)) {
                // Merge with existing stock
                dataManager.getDbHelper().mergeStock(item, qty, unit, price, supplier);
            } else {
                // Add as new stock
                dataManager.getDbHelper().addStock(supplier, item, qty, unit, price, LocalDate.now().toString());
            }

            // RIGHT: Use the logic that handles profit columns correctly
            dataManager.getDbHelper().addSaleWithProfit(supplier, item, qty, unit, price, "NEW STOCK");
        }

        showAlert("Stock saved successfully!");
        newStockTable.getItems().clear();
        supplierNameField.clear();

        // Notify all listeners that data has changed - INCLUDING ITEMS
        dataManager.notifyDataChanged();
    }

    private void showAlert(String text) {
        Alert a = new Alert(Alert.AlertType.INFORMATION, text, ButtonType.OK);
        a.showAndWait();
    }
}