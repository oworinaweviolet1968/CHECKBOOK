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
import java.util.Map;
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
        setupAutoPriceCalculation();
    }

    // Inside NewStockController.java
    private void setupAutoPriceCalculation() {
        unitField.textProperty().addListener((obs, oldVal, newVal) -> {
            String item = itemsComboBox.getValue();
            String size = qtyComboBox.getValue();

            if (item != null && size != null && !newVal.isEmpty()) {
                double costPerPiece = dataManager.getDbHelper().getExistingPrice(item, size);
                double multiplier = dataManager.getDbHelper().getUnitMultiplier(newVal, size);
                double count = extractNumericValue(newVal); // Get the "4" from "4 sacks"

                if (costPerPiece > 0) {
                    double totalAmount = count * multiplier * costPerPiece;
                    priceField.setText(String.format("%.0f", totalAmount));
                }
            }
        });
    }

    private double extractNumericValue(String text) {
        if (text == null || text.isEmpty()) return 1.0;
        try {
            // This regex finds the first number in the string (e.g. "4 sacks" -> 4)
            Pattern p = Pattern.compile("(\\d+(\\.\\d+)?)");
            Matcher m = p.matcher(text);
            if (m.find()) {
                return Double.parseDouble(m.group(1));
            }
        } catch (Exception e) {
            return 1.0;
        }
        return 1.0;
    }

    private void calculateRestockPrice() {
        String item = itemsComboBox.getValue();
        String size = qtyComboBox.getValue(); // e.g., "50kg"
        String unit = unitField.getText();    // e.g., "4 sacks"

        if (item == null || size == null || unit.isEmpty()) return;

        // 1. Get the cost per KG from DB
        double costPerKg = dataManager.getDbHelper().getExistingPrice(item, size);

        if (costPerKg > 0) {
            // 2. Get the multiplier (e.g., "sack" = 50)
            double multiplier = dataManager.getDbHelper().getUnitMultiplier(unit, size);

            // 3. Get the count (e.g., "4")
            double count = 1.0;
            String numOnly = unit.replaceAll("[^0-9.]", "");
            if (!numOnly.isEmpty()) count = Double.parseDouble(numOnly);

            // 4. Calculate Total Cost for this entry
            // 4 (sacks) * 50 (kg) * 3,000 (cost) = 600,000
            double totalRestockPrice = count * multiplier * costPerKg;

            // 5. Update the price field automatically
            priceField.setText(String.format("%.0f", totalRestockPrice));

            // Visual cue that this is an auto-calculated price
            priceField.setStyle("-fx-control-inner-background: #e1f5fe;");
        }
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
        // 1. Create the data using Map.of (supports up to 10 pairs)
        Map<String, Integer> unitData = Map.of(
                "pcs",1,
                "sack", 1,
                "half doz", 6,
                "carton", 24,
                "dozen", 12,
                "box", 20,
                "crate", 25
        );

        // 2. If order matters (left-to-right), sort them or use a List of names
        // Inside createUnitQuickButtons
        String[] order = {"pcs", "sack", "half doz", "dozen", "box", "carton", "crate"};

        for (String unitName : order) {
            Integer val = unitData.get(unitName);
            Button b = new Button(unitName);

            // Special styling for "sack" to stand out as a bulk item
            if (unitName.equals("sack")) {
                b.setStyle("-fx-background-color: #2196F3; -fx-text-fill: white;");
            } else {
                Label valLabel = new Label("*" + val);
                valLabel.setStyle("-fx-text-fill: red; -fx-font-weight: bold; -fx-padding: 0 0 0 5;");
                b.setGraphic(valLabel);
                b.setContentDisplay(ContentDisplay.RIGHT);
            }

            b.getStyleClass().add("pill");
            b.setOnAction(evt -> appendUnit(unitName));
            unitButtonsBox.getChildren().add(b);
        }
    }

    private void appendUnit(String unit) {
        String selectedItem = itemsComboBox.getEditor().getText();
        String selectedSize = qtyComboBox.getEditor().getText();

        if (selectedItem.isEmpty() || selectedSize.isEmpty()) {
            unitErrorLabel.setText("* Select Item and Size first");
            unitErrorLabel.setVisible(true);
            return;
        }

        String currentText = unitField.getText().trim();
        String numberPart = currentText.replaceAll("[^0-9.]", "");
        if (numberPart.isEmpty()) numberPart = "1";

        unitField.setText(numberPart + " " + unit);

        // 1. Get the price of 1 base unit (e.g., 1kg of Posho = 4,444)
        double basePrice = dataManager.getDbHelper().getExistingPrice(selectedItem, selectedSize);

        if (basePrice > 0) {
            // 2. Get the multiplier (e.g., Sack = 45)
            double multiplier = dataManager.getDbHelper().getUnitMultiplier(unit, selectedSize);

            // 3. Fill the price field with the price of ONE UNIT (e.g., 1 Sack = 200,000)
            double unitPrice = basePrice * multiplier;
            priceField.setText(String.format("%.0f", unitPrice));
            unitErrorLabel.setVisible(false);
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
        // Added "crate" to the regex pattern
        // Update the regex to accept 'pc' (without the s)
        String countPattern = ".*\\d+.*(pc|pcs|doz|carton|box|sack|dozen|crate).*";

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

        double inputPrice;
        try {
            inputPrice = Double.parseDouble(priceRaw);
        } catch (NumberFormatException ex) {
            showAlert("Invalid price.");
            return;
        }

        // 1. Get the count (e.g., the "2" from "2 sacks")
        double count = extractNumericValue(unitText);

        // 2. THE CALCULATION
        // If you enter 2 sacks at 200,000 per sack, total is 400,000.
        // This assumes the price you type in the box is the price for the unit shown (pc, sack, box, etc.)
        double totalAmount = count * inputPrice;

        String amountStr = String.format("%,.0f", totalAmount);
        String priceStr = String.format("%,.0f", inputPrice);

        StockItem si = new StockItem(itemName, qtyRaw, unitText, priceStr, amountStr);
        items.add(si);

        // clear fields
        itemsComboBox.getEditor().clear();
        qtyComboBox.getEditor().clear();
        unitField.clear();
        priceField.clear();
    }

    @FXML
    private void onSave() {
        String supplier = supplierNameField.getText().trim();
        if (supplier.isEmpty()) {
            supplierErrorLabel.setVisible(true);
            supplierErrorLabel.setManaged(true);
            return;
        }

        if (items.isEmpty()) {
            showAlert("Please Fill in item to continue!");
            return;
        }

        for (StockItem s : items) { // Iterating through the table items
            String item = s.getItems();
            String qty = s.getQty();
            String unit = s.getUnit();
            double price = Double.parseDouble(s.getPrice().replaceAll("[^0-9.]", ""));

            if (dataManager.getDbHelper().itemExists(item, qty)) {
                // 1. Try to merge normally (forceSave = false)
                boolean success = dataManager.getDbHelper().mergeStock(item, qty, unit, price, supplier, false);

                if (!success) {
                    // 2. If it fails, show the Alert
                    Alert alert = new Alert(Alert.AlertType.CONFIRMATION);
                    alert.setTitle("Price Variance Warning");
                    alert.setHeaderText("Price mismatch for " + item + " (" + qty + ")");
                    alert.setContentText("The price for " + unit + " makes the unit price very different from current stock.\n\n" +
                            "Do you want to save this anyway?");

                    if (alert.showAndWait().get() == ButtonType.OK) {
                        // 3. If user says OK, merge with forceSave = true
                        dataManager.getDbHelper().mergeStock(item, qty, unit, price, supplier, true);
                    } else {
                        continue; // Skip this item and move to next, or 'return' to stop everything
                    }
                }
            } else {
                dataManager.getDbHelper().addStock(supplier, item, qty, unit, price, LocalDate.now().toString());
            }

            dataManager.getDbHelper().addSaleWithProfit(supplier, item, qty, unit, price, "NEW STOCK");
        }

        showAlert("Stock saved successfully!");
        items.clear(); // Clear the ObservableList
        supplierNameField.clear();
        dataManager.notifyDataChanged();
    }

    private void showAlert(String text) {
        Alert a = new Alert(Alert.AlertType.INFORMATION, text, ButtonType.OK);
        a.showAndWait();
    }
}