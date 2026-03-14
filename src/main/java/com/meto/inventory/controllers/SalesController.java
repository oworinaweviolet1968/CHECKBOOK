package com.meto.inventory.controllers;

import com.meto.inventory.DataManager;
import com.meto.inventory.models.SaleItem;
import javafx.collections.FXCollections;
import javafx.collections.ObservableList;
import javafx.fxml.FXML;
import javafx.scene.control.*;
import javafx.scene.layout.FlowPane;
import javafx.scene.layout.Pane;

import java.util.function.UnaryOperator;

public class SalesController implements DataManager.DataChangeListener {

    @FXML
    private ComboBox<String> customerNameComboBox;
    @FXML
    private ComboBox<String> itemsComboBox;
    @FXML
    private ComboBox<String> qtyComboBox;
    @FXML
    private TextField unitField;
    @FXML
    private TextField qtyField;
    @FXML
    private TextField priceField;
    @FXML
    private Button addButton;
    @FXML
    private Button saveButton;
    @FXML
    private Button quarterKgBtn;
    @FXML
    private Button halfKgBtn;
    @FXML
    private Button kgBtn;
    @FXML
    private Button sackBtn;
    @FXML
    private Button sackUnitBtn;
    @FXML
    private Label unitErrorLabel;
    @FXML
    private FlowPane weightButtonsBox;
    @FXML
    private FlowPane unitButtonsBox;

    // Unit buttons
    @FXML
    private Button pcsBtn, box10Btn, box12Btn, box20Btn, box24Btn, box72Btn, crateBtn;

    @FXML
    private TableView<SaleItem> salesTable;
    @FXML
    private TableColumn<SaleItem, String> itemCol, qtyCol, unitCol, priceCol, amountCol;
    @FXML
    private TableColumn<SaleItem, Void> deleteCol;

    @FXML
    private Label totalAmountLabel;

    private final ObservableList<SaleItem> items = FXCollections.observableArrayList();
    private final DataManager dataManager = DataManager.getInstance();

    @FXML
    public void initialize() {
        // Register as listener for data changes
        dataManager.addDataChangeListener(this);
        setupTable();
        setupButtons();
        setupDropdowns();
        updateTotal();

        // --- SECURITY: BLOCK FORBIDDEN CHARACTERS & LIMIT LENGTH ---
        UnaryOperator<TextFormatter.Change> filter = change -> {
            String newText = change.getControlNewText();

            // 1. Length Limit (45 chars)
            if (newText.length() > 45)
                return null;

            // 2. Block forbidden patterns in the FULL text (e.g., // or ..)
            if (newText.contains("//") || newText.contains("..") || newText.contains(";;") || newText.contains("@@")) {
                return null;
            }

            // 3. Allow only specific characters in the CHANGED text (typing)
            // Allow A-Z, 0-9, space, dot, dash, comma, slash
            String text = change.getText();
            if (text.matches("[a-zA-Z0-9 .\\-,/]*")) {
                return change;
            }
            return null; // Block otherwise
        };
        customerNameComboBox.getEditor().setTextFormatter(new TextFormatter<>(filter));

        // --- INPUT VALIDATION FIX ---

        // 1. Strict Numeric + Whitelist for Quantity/Unit
        // Strategy: Allow purely numeric/symbolic typing.
        // Allow the result ONLY if it matches the button-generated patterns
        // (Whitelisted units).
        unitField.setTextFormatter(new TextFormatter<>(change -> {
            String newText = change.getControlNewText().toLowerCase();

            // 1. empty allowed
            if (newText.isEmpty())
                return change;

            // 2. Allow pure numbers and symbols (typing quantity)
            // Allowed: 0-9, space, /, .
            if (newText.matches("[0-9 ./]*")) {
                return change;
            }

            // 3. Strict Button-Only Logic:
            // We strip out all allowed numeric/symbol chars.
            // The remaining text (if any) MUST be one of the known units EXACTLY.
            // Note: including '*' in removal so 'Box * 10' becomes 'box'
            String textContent = newText.replaceAll("[0-9 ./*-]", "").trim();

            if (textContent.isEmpty())
                return change; // Just numbers is fine

            if (isValidExactUnit(textContent)) {
                return change;
            }

            // Otherwise block
            return null;
        }));

        // 2. Strict Numbers for Price
        priceField.setTextFormatter(new TextFormatter<>(change -> {
            String newText = change.getControlNewText().replaceAll(",", "");
            if (newText.matches("\\d*")) { // Only digits allowed
                return change;
            }
            return null;
        }));

        // --- STEP 0: START LOCKED ---
        setFlowLevel(0);

        // --- FLOW CONTROL LISTENERS ---

        customerNameComboBox.getEditor().textProperty().addListener((obs, oldVal, newVal) -> {
            if (newVal.trim().isEmpty()) {
                setFlowLevel(0);
                itemsComboBox.setValue(null);
            } else {
                setFlowLevel(1);
            }
        });
        // Also react if user picks from the dropdown
        customerNameComboBox.valueProperty().addListener((obs, old, newVal) -> {
            if (newVal != null && !newVal.trim().isEmpty()) {
                setFlowLevel(1);
            }
        });

        itemsComboBox.valueProperty().addListener((obs, oldVal, newVal) -> {
            if (newVal == null) {
                if (!customerNameComboBox.getEditor().getText().trim().isEmpty())
                    setFlowLevel(1);
                qtyComboBox.setValue(null);
            } else {
                setFlowLevel(2);
            }
        });

        qtyComboBox.valueProperty().addListener((obs, oldVal, newVal) -> {
            updateButtonVisibility(newVal);
            if (newVal == null) {
                if (itemsComboBox.getValue() != null)
                    setFlowLevel(2);
                unitField.clear();
            } else {
                if (newVal.equalsIgnoreCase("None")) {
                    setFlowLevel(3);
                    qtyComboBox.setDisable(true);
                } else {
                    setFlowLevel(3);
                }
            }
        });

        unitField.textProperty().addListener((obs, oldVal, newVal) -> {
            unitErrorLabel.setVisible(false);
            unitErrorLabel.setManaged(false);

            if (newVal.trim().isEmpty()) {
                if (qtyComboBox.getValue() != null)
                    setFlowLevel(3);
                priceField.clear();
            } else {
                // Only downgrade level if price is empty
                if (priceField.getText().trim().isEmpty()) {
                    setFlowLevel(4);
                } else {
                    setFlowLevel(5);
                }
            }
        });

        priceField.textProperty().addListener((observable, oldValue, newValue) -> {
            if (newValue.isEmpty())
                return;

            String cleanString = newValue.replaceAll(",", "");

            try {
                double value = Double.parseDouble(cleanString);
                String formatted = String.format("%,.0f", value);

                if (!newValue.equals(formatted)) {
                    priceField.setText(formatted);
                    priceField.positionCaret(formatted.length());
                }
            } catch (NumberFormatException e) {
                // Ignore
            }
        });

        priceField.textProperty().addListener((obs, oldVal, newVal) -> {
            if (newVal.trim().isEmpty()) {
                if (!unitField.getText().trim().isEmpty())
                    setFlowLevel(4);
                addButton.setDisable(true);
            } else {
                setFlowLevel(5);
            }
        });

        // Initialize visibility
        if (weightButtonsBox != null && unitButtonsBox != null) {
            updateButtonVisibility(null);
        }
    }

    private void updateButtonVisibility(String selectedSize) {
        if (selectedSize == null) {
            setBoxVisible(weightButtonsBox, false);
            setBoxVisible(unitButtonsBox, false);
            return;
        }

        double sizeNum = dataManager.getDbHelper().extractNumericValue(selectedSize);
        boolean isBulkWeight = selectedSize.toLowerCase().contains("kg") && sizeNum >= 10.0;

        if (isBulkWeight) {
            setBoxVisible(weightButtonsBox, true);
            setBoxVisible(unitButtonsBox, false);
        } else {
            setBoxVisible(weightButtonsBox, false);
            setBoxVisible(unitButtonsBox, true);
        }
    }

    private void setFlowLevel(int level) {
        itemsComboBox.setDisable(level < 1);
        qtyComboBox.setDisable(level < 2);

        boolean unitEnabled = level >= 3;
        unitField.setDisable(!unitEnabled);
        if (unitButtonsBox != null)
            unitButtonsBox.setDisable(!unitEnabled);
        if (weightButtonsBox != null)
            weightButtonsBox.setDisable(!unitEnabled);

        priceField.setDisable(level < 3);
        addButton.setDisable(level < 5);
    }

    private void setBoxVisible(Pane box, boolean visible) {
        if (box != null) {
            box.setVisible(visible);
            box.setManaged(visible);
        }
    }

    @FXML
    private void handleQuarterKg() {
        String existingNumbers = unitField.getText().replaceAll("[^0-9.]", "").trim();
        unitField.setText(existingNumbers.isEmpty() ? "1/4 kg" : existingNumbers + " 1/4 kg");
    }

    @FXML
    private void handleHalfKg() {
        String existingNumbers = unitField.getText().replaceAll("[^0-9.]", "").trim();
        unitField.setText(existingNumbers.isEmpty() ? "1/2 kg" : existingNumbers + " 1/2 kg");
    }

    @Override
    public void onDataChanged() {
        javafx.application.Platform.runLater(this::refreshDropdowns);
    }

    private void setupDropdowns() {
        refreshDropdowns();
        itemsComboBox.setOnAction(e -> {
            String selectedItem = itemsComboBox.getValue();
            if (selectedItem != null) {
                refreshSizesDropdown(selectedItem);
            }
        });
    }

    private void refreshDropdowns() {
        ObservableList<String> availableItems = dataManager.getDbHelper().getAvailableItems();
        itemsComboBox.setItems(availableItems);
        qtyComboBox.setItems(FXCollections.observableArrayList());

        // Populate customer dropdown: Walk-in Customer first, then past customers
        ObservableList<String> customers = FXCollections.observableArrayList();
        customers.add("Walk-in Customer");
        customers.addAll(dataManager.getDbHelper().getDistinctCustomers());
        customerNameComboBox.setItems(customers);
    }

    private void refreshSizesDropdown(String itemName) {
        ObservableList<String> sizes = dataManager.getDbHelper().getItemSizes(itemName);
        qtyComboBox.setItems(sizes);

        if (sizes.size() == 1) {
            qtyComboBox.setValue(sizes.get(0));
        } else if (sizes.contains("None")) {
            qtyComboBox.setValue("None");
        }
    }

    private void setupTable() {
        salesTable.setItems(items);
        itemCol.setCellValueFactory(data -> data.getValue().itemsProperty());
        qtyCol.setCellValueFactory(data -> data.getValue().qtyProperty());
        unitCol.setCellValueFactory(data -> data.getValue().unitProperty());
        priceCol.setCellValueFactory(data -> data.getValue().priceProperty());
        amountCol.setCellValueFactory(data -> data.getValue().amountProperty());

        deleteCol.setCellFactory(param -> new TableCell<>() {
            private final Button deleteBtn = new Button("Delete");
            {
                deleteBtn.setStyle(
                        "-fx-background-color: red; -fx-text-fill: white; -fx-font-size: 10px; -fx-padding: 2 6;");
                deleteBtn.setOnAction(event -> {
                    SaleItem item = getTableView().getItems().get(getIndex());
                    items.remove(item);
                    updateTotal();
                });
            }

            @Override
            protected void updateItem(Void item, boolean empty) {
                super.updateItem(item, empty);
                setGraphic(empty ? null : deleteBtn);
            }
        });
    }

    private void setupButtons() {
        addButton.setOnAction(e -> addItem());
        saveButton.setOnAction(e -> saveSale());

        // Collect all weight buttons and unit buttons for selection tracking
        java.util.List<Button> wBtns = java.util.List.of(quarterKgBtn, halfKgBtn, kgBtn, sackBtn);
        java.util.List<Button> uBtns = java.util.List.of(pcsBtn, box10Btn, box12Btn, box20Btn, box24Btn, box72Btn, crateBtn, sackUnitBtn);

        quarterKgBtn.setOnAction(e -> {
            selectQuickBtn(quarterKgBtn, wBtns);
            String n = unitField.getText().replaceAll("[^0-9.]", "").trim();
            unitField.setText(n.isEmpty() ? "1/4 kg" : n + " 1/4 kg");
        });

        halfKgBtn.setOnAction(e -> {
            selectQuickBtn(halfKgBtn, wBtns);
            String n = unitField.getText().replaceAll("[^0-9.]", "").trim();
            unitField.setText(n.isEmpty() ? "1/2 kg" : n + " 1/2 kg");
        });

        kgBtn.setOnAction(e -> {
            selectQuickBtn(kgBtn, wBtns);
            String n = unitField.getText().replaceAll("[^0-9.]", "").trim();
            unitField.setText(n.isEmpty() ? "1 kg" : n + " kg");
        });

        sackBtn.setOnAction(e -> {
            selectQuickBtn(sackBtn, wBtns);
            String n = unitField.getText().replaceAll("[^0-9.]", "").trim();
            unitField.setText(n.isEmpty() ? "1 sack" : n + " sack");
        });

        // UNIT buttons (packaging units)
        pcsBtn.setOnAction(e    -> { selectQuickBtn(pcsBtn,    uBtns); appendToUnit("pcs"); });
        box10Btn.setOnAction(e  -> { selectQuickBtn(box10Btn,  uBtns); appendToUnit("Box * 10"); });
        box12Btn.setOnAction(e  -> { selectQuickBtn(box12Btn,  uBtns); appendToUnit("Box * 12"); });
        box20Btn.setOnAction(e  -> { selectQuickBtn(box20Btn,  uBtns); appendToUnit("Box * 20"); });
        box24Btn.setOnAction(e  -> { selectQuickBtn(box24Btn,  uBtns); appendToUnit("Box * 24"); });
        box72Btn.setOnAction(e  -> { selectQuickBtn(box72Btn,  uBtns); appendToUnit("Box * 72"); });
        crateBtn.setOnAction(e  -> { selectQuickBtn(crateBtn,  uBtns); appendToUnit("Crate * 25"); });
        sackUnitBtn.setOnAction(e -> { selectQuickBtn(sackUnitBtn, uBtns); appendToUnit("Sack"); });
    }

    /** Marks btn as selected (green fill) and deselects all others in the group. */
    private void selectQuickBtn(Button btn, java.util.List<Button> group) {
        for (Button b : group) {
            b.getStyleClass().remove("pill-quick-selected");
            if (!b.getStyleClass().contains("pill-quick"))
                b.getStyleClass().add("pill-quick");
        }
        btn.getStyleClass().remove("pill-quick");
        if (!btn.getStyleClass().contains("pill-quick-selected"))
            btn.getStyleClass().add("pill-quick-selected");
    }

    private void appendToUnit(String unit) {
        String text = unitField.getText().trim();
        String numericValue = getUnitValue(unit);

        if (text.isEmpty()) {
            unitField.setText(numericValue + " " + unit);
        } else {
            String existingNumbers = text.replaceAll("[^0-9.]", "").trim();
            if (existingNumbers.isEmpty()) {
                unitField.setText(numericValue + " " + unit);
            } else {
                unitField.setText(existingNumbers + " " + unit);
            }
        }
    }

    private String getUnitValue(String unit) {
        return "1";
    }

    private void addItem() {
        String item = itemsComboBox.getValue();
        String size = qtyComboBox.getValue();
        String priceText = priceField.getText().replaceAll("[^0-9,.]", "").replace(",", "");
        String countUnit = unitField.getText().trim().toLowerCase();

        unitErrorLabel.setVisible(false);
        unitErrorLabel.setManaged(false);

        String countPattern = ".*(\\d|/)+(.*)(pcs|doz|carton|box|sack|dozen|kg|ml|l|crate|half doz|box\\*10|box\\*12|box\\*20|box\\*24|box\\*72).*";

        if (countUnit.isEmpty() || !countUnit.matches(countPattern)) {
            unitErrorLabel.setVisible(true);
            unitErrorLabel.setManaged(true);
            return;
        }

        if (item == null || size == null || priceText.isEmpty()) {
            showAlert("Please fill all fields");
            return;
        }

        try {
            double unitPrice = Double.parseDouble(priceText);
            double moneyMultiplier = getMoneyMultiplier(countUnit);
            double totalAmount = moneyMultiplier * unitPrice;

            double weightForStock = getStockWeight(countUnit, size);
            String weightStr = String.valueOf(weightForStock);

            double costPerPiece = dataManager.getDbHelper().getLastRecordedPrice(item, size);
            double totalCost = weightForStock * costPerPiece;

            if (totalCost > 0 && totalAmount < totalCost) {
                String content = String.format(
                        "Warning: Potential Loss!\nSelling Price: UGX %,.2f\nActual Cost: UGX %,.2f\n\nProceed anyway?",
                        totalAmount, totalCost);
                if (!com.meto.inventory.utils.DialogHelper.showConfirm("Profit Warning", "Selling Below Cost",
                        content)) {
                    return;
                }
            }

            if (!dataManager.getDbHelper().hasEnoughStock(item, size, weightStr)) {
                showAlert("Not enough stock!\nAvailable: " + dataManager.getDbHelper().getAvailableStock(item, size));
                return;
            }

            items.add(new SaleItem(item, size, countUnit, String.format("%,.2f", unitPrice),
                    String.format("%,.2f", totalAmount)));
            clearFields();
            updateTotal();

        } catch (NumberFormatException e) {
            showAlert("Invalid price format");
        }
    }

    private double getMoneyMultiplier(String text) {
        if (text == null || text.isEmpty())
            return 1.0;
        String lower = text.toLowerCase().trim();
        String[] parts = lower.split("(1/4|1/2|kg|sack|pcs|half doz|dozen|box|carton|crate)");
        if (parts.length > 0) {
            if (lower.startsWith("1/4") || lower.startsWith("1/2"))
                return 1.0;
            String numeric = parts[0].replaceAll("[^0-9.]", "").trim();
            if (!numeric.isEmpty()) {
                try {
                    return Double.parseDouble(numeric);
                } catch (Exception e) {
                    return 1.0;
                }
            }
        }
        return 1.0;
    }

    private double getStockWeight(String text, String sizeStr) {
        String lower = text.toLowerCase();
        double count = getMoneyMultiplier(lower);

        if (lower.contains("1/4"))
            return count * 0.25;
        if (lower.contains("1/2"))
            return count * 0.5;

        if (lower.contains("box*12") || lower.contains("dozen") || lower.contains("doz")
                || lower.contains("half doz")) {
            double multiplier = 12.0;
            if (lower.contains("half"))
                multiplier = 6.0;
            return count * multiplier;
        } else if (lower.contains("box*10")) {
            return count * 10;
        } else if (lower.contains("box*20") || lower.equals("box")) {
            return count * 20;
        } else if (lower.contains("box*24") || lower.contains("carton")) {
            return count * 24;
        } else if (lower.contains("box*72")) {
            return count * 72;
        } else if (lower.contains("crate")) {
            return count * 25;
        } else if (lower.contains("sack")) {
            double kgPerSack = dataManager.getDbHelper().extractNumericValue(sizeStr);
            return count * kgPerSack;
        }
        return count;
    }

    private void saveSale() {
        String customer = customerNameComboBox.getEditor().getText().trim();
        if (customer.isEmpty() && customerNameComboBox.getValue() != null)
            customer = customerNameComboBox.getValue().trim();
        if (customer.isEmpty() || items.isEmpty()) {
            showAlert("Customer name and items required");
            return;
        }

        for (SaleItem item : items) {
            if (!dataManager.getDbHelper().hasEnoughStock(item.getItems(), item.getQty(), item.getUnit())) {
                String availableStock = dataManager.getDbHelper().getAvailableStock(item.getItems(), item.getQty());
                showAlert("Cannot complete sale! Stock changed since items were added.\n\nItem: " + item.getItems()
                        + " " + item.getQty() + "\nTrying to sell: " + item.getUnit() + "\nAvailable: "
                        + availableStock);
                return;
            }
        }

        String saleType = determineSaleType();
        for (SaleItem item : items) {
            double price = Double.parseDouble(item.getPrice().replaceAll("[^0-9.]", ""));
            double amount = Double.parseDouble(item.getAmount().replaceAll("[^0-9.]", ""));
            dataManager.getDbHelper().addSaleWithProfit(customer, item.getItems(), item.getQty(), item.getUnit(), price,
                    amount, saleType);
            updateStock(item.getItems(), item.getQty(), item.getUnit());
        }

        showAlert("Sale saved successfully! Stock updated.");
        items.clear();
        customerNameComboBox.getEditor().clear();
        customerNameComboBox.setValue(null);
        itemsComboBox.setValue(null);
        qtyComboBox.setValue(null);
        unitField.clear();
        priceField.clear();
        updateTotal();
        dataManager.notifyDataChanged();
    }

    private void clearFields() {
        unitField.clear();
        priceField.clear();
        qtyComboBox.setValue(null);
    }

    private void updateStock(String itemName, String soldQty, String soldUnit) {
        double actualWeight = getStockWeight(soldUnit, soldQty);
        dataManager.getDbHelper().updateStockQuantity(itemName, soldQty, String.valueOf(actualWeight));
    }

    private String determineSaleType() {
        for (SaleItem item : items) {
            String unit = item.getUnit().toLowerCase();
            if (unit.contains("half doz") || unit.contains("carton") || unit.contains("dozen") || unit.contains("box")
                    || unit.contains("crate")) {
                return "WHOLESALE";
            }
        }
        return "RETAIL";
    }

    private void updateTotal() {
        double total = items.stream().mapToDouble(item -> {
            try {
                return Double.parseDouble(item.getAmount().replaceAll("[^0-9.]", ""));
            } catch (Exception e) {
                return 0;
            }
        }).sum();
        totalAmountLabel.setText(String.format("TOTAL AMOUNT: UGX %,.2f", total));
    }

    private void showAlert(String message) {
        com.meto.inventory.utils.DialogHelper.showAlert(message);
    }

    private boolean isValidExactUnit(String text) {
        String[] allowed = { "kg", "pcs", "sack", "doz", "dozen", "box",
                "carton", "crate", "ml", "l", "halfdoz", "inch" };
        for (String unit : allowed) {
            if (text.equals(unit))
                return true;
        }
        return false;
    }

    public void destroy() {
        dataManager.removeDataChangeListener(this);
    }
}