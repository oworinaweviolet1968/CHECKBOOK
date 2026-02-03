package com.meto.inventory.controllers;

import com.meto.inventory.DataManager;
import com.meto.inventory.models.SaleItem;
import javafx.collections.FXCollections;
import javafx.collections.ObservableList;
import javafx.fxml.FXML;
import javafx.scene.control.*;
import javafx.scene.control.*;
import javafx.scene.layout.FlowPane;
import javafx.scene.layout.Pane;

import java.time.LocalDate;
import java.util.function.UnaryOperator;

public class SalesController implements DataManager.DataChangeListener {

    @FXML
    private TextField customerNameField;
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
    private Label unitErrorLabel;
    @FXML
    private FlowPane weightButtonsBox;
    @FXML
    private FlowPane unitButtonsBox;

    // Unit buttons
    @FXML
    private Button pcsBtn, halfDozenBtn, cartonBtn, dozenBtn, boxBtn, crateBtn;

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
        customerNameField.setTextFormatter(new TextFormatter<>(filter));

        // --- INPUT VALIDATION FIX ---

        // 1. Strict Numeric + Whitelist for Quantity/Unit
        // User Request: "allow only text from the quick-pill-buttons or specific words"
        // Strategy: Allow purely numeric/symbolic typing. Block typing letters
        // manually.
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
            // This blocks "2 pcsgarbage" because "pcsgarbage" is not a valid unit.
            // It blocks typing "p" because "p" is not a valid unit.
            // It allows "2 pcs" because "pcs" is valid.
            String textContent = newText.replaceAll("[0-9 ./-]", "").trim();

            if (textContent.isEmpty())
                return change; // Just numbers is fine

            if (isValidExactUnit(textContent)) {
                return change;
            }

            // Otherwise block (e.g. user typing 'a', 'd', 's' manually, or appending
            // garbage)
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

        customerNameField.textProperty().addListener((obs, oldVal, newVal) -> {
            if (newVal.trim().isEmpty()) {
                setFlowLevel(0);
                itemsComboBox.setValue(null);
            } else {
                setFlowLevel(1);
            }
        });

        itemsComboBox.valueProperty().addListener((obs, oldVal, newVal) -> {
            if (newVal == null) {
                if (!customerNameField.getText().trim().isEmpty())
                    setFlowLevel(1);
                qtyComboBox.setValue(null);
            } else {
                setFlowLevel(2);

                // NEW: Check if the Size is "None" -> Loop Logic
                // We need to wait for sizes to load. If the only size is "None", auto-skip.
                // refreshSizesDropdown handles the selection.
                // Here we just check if value became None immediately.
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
                    // Logic for NONE item:
                    // 1. Advance Flow to Level 3 (Enable Unit)
                    // 2. Disable this Qty box so they can't mess with it
                    setFlowLevel(3);
                    qtyComboBox.setDisable(true); // Visual Block
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
                setFlowLevel(4);
            }
        });

        // Add this inside initialize()
        priceField.textProperty().addListener((observable, oldValue, newValue) -> {
            if (newValue.isEmpty())
                return;

            // 1. Remove commas to get the raw number
            String cleanString = newValue.replaceAll(",", "");

            // 2. Try to format it
            try {
                double value = Double.parseDouble(cleanString);
                String formatted = String.format("%,.0f", value); // No decimals for UGX usually

                // 3. Update field only if it's different to avoid infinite loops
                if (!newValue.equals(formatted)) {
                    priceField.setText(formatted);
                    // Keep cursor at the end
                    priceField.positionCaret(formatted.length());
                }
            } catch (NumberFormatException e) {
                // Ignore if the user types something non-numeric
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
            // If nothing is selected, hide both to keep it clean
            setBoxVisible(weightButtonsBox, false);
            setBoxVisible(unitButtonsBox, false);
            return;
        }

        double sizeNum = dataManager.getDbHelper().extractNumericValue(selectedSize);
        boolean isBulkWeight = selectedSize.toLowerCase().contains("kg") && sizeNum >= 10.0;

        if (isBulkWeight) {
            // It's a sack (e.g., 50kg sugar) -> Show kg buttons
            setBoxVisible(weightButtonsBox, true);
            setBoxVisible(unitButtonsBox, false);
        } else {
            // It's a pack or piece (e.g., 1kg pack or Soda) -> Show unit buttons
            setBoxVisible(weightButtonsBox, false);
            setBoxVisible(unitButtonsBox, true);
        }
    }

    private void setFlowLevel(int level) {
        // Level 0: Start (Customer Name only)
        // Level 1: Customer entered -> Enable Items
        // Level 2: Item picked -> Enable Size (Qty)
        // Level 3: Size picked -> Enable Unit (Count)
        // Level 4: Unit entered -> Enable Price
        // Level 5: Price entered -> Enable Add Button

        itemsComboBox.setDisable(level < 1);
        qtyComboBox.setDisable(level < 2);

        boolean unitEnabled = level >= 3;
        unitField.setDisable(!unitEnabled);
        if (unitButtonsBox != null)
            unitButtonsBox.setDisable(!unitEnabled);
        if (weightButtonsBox != null)
            weightButtonsBox.setDisable(!unitEnabled);

        priceField.setDisable(level < 4);
        addButton.setDisable(level < 5);
    }

    // Helper to handle both Visibility and Managed state (removing the gap)
    private void setBoxVisible(Pane box, boolean visible) {
        // Add this null check to prevent the crash
        if (box != null) {
            box.setVisible(visible);
            box.setManaged(visible);
        } else {
            // This will print to your console so you know which one is missing
            System.out.println("Warning: A Button Box is null. Check fx:id in FXML.");
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
        // Refresh dropdowns when new items are added
        refreshDropdowns();
    }

    private void setupDropdowns() {
        refreshDropdowns();

        // When item is selected, load its available sizes
        itemsComboBox.setOnAction(e -> {
            String selectedItem = itemsComboBox.getValue();
            if (selectedItem != null) {
                refreshSizesDropdown(selectedItem);
            }
        });
    }

    private void refreshDropdowns() {
        // Refresh items dropdown
        ObservableList<String> availableItems = dataManager.getDbHelper().getAvailableItems();
        itemsComboBox.setItems(availableItems);

        // Clear sizes dropdown when items refresh
        qtyComboBox.setItems(FXCollections.observableArrayList());
    }

    private void refreshSizesDropdown(String itemName) {
        ObservableList<String> sizes = dataManager.getDbHelper().getItemSizes(itemName);
        qtyComboBox.setItems(sizes);

        // Auto-select first size if only one exists
        if (sizes.size() == 1) {
            qtyComboBox.setValue(sizes.get(0));
        } else if (sizes.contains("None")) {
            // If there are mixed sizes but one is None? Usually unlikely for same item
            // name.
            // But if specific request for "Pens", might just default select None.
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

        quarterKgBtn.setOnAction(e -> {
            String existingNumbers = unitField.getText().replaceAll("[^0-9.]", "").trim();
            // If there's a number, add a space before the fraction
            unitField.setText(existingNumbers.isEmpty() ? "1/4 kg" : existingNumbers + " 1/4 kg");
        });

        halfKgBtn.setOnAction(e -> {
            String existingNumbers = unitField.getText().replaceAll("[^0-9.]", "").trim();
            unitField.setText(existingNumbers.isEmpty() ? "1/2 kg" : existingNumbers + " 1/2 kg");
        });

        kgBtn.setOnAction(e -> {
            String existingNumbers = unitField.getText().replaceAll("[^0-9.]", "").trim();
            unitField.setText(existingNumbers.isEmpty() ? "1 kg" : existingNumbers + " kg");
        });

        sackBtn.setOnAction(e -> {
            String existingNumbers = unitField.getText().replaceAll("[^0-9.]", "").trim();
            unitField.setText(existingNumbers.isEmpty() ? "1 sack" : existingNumbers + " sack");
        });
        // UNIT buttons (packaging units)
        pcsBtn.setOnAction(e -> appendToUnit("pcs"));
        halfDozenBtn.setOnAction(e -> appendToUnit("half doz"));
        cartonBtn.setOnAction(e -> appendToUnit("carton"));
        dozenBtn.setOnAction(e -> appendToUnit("dozen"));
        boxBtn.setOnAction(e -> appendToUnit("box"));
        crateBtn.setOnAction(event -> appendToUnit("crate"));
    }

    private void appendToUnit(String unit) {
        String text = unitField.getText().trim();
        String numericValue = getUnitValue(unit);

        if (text.isEmpty()) {
            unitField.setText(numericValue + " " + unit);
        } else {
            // Extract the number part from the current text
            String existingNumbers = text.replaceAll("[^0-9.]", "").trim();
            if (existingNumbers.isEmpty()) {
                // If there was no number (e.g. "pcs"), replace with default number
                unitField.setText(numericValue + " " + unit);
            } else {
                // Keep the number, replace the unit
                unitField.setText(existingNumbers + " " + unit);
            }
        }
    }

    private String getUnitValue(String unit) {
        switch (unit.toLowerCase()) {
            case "pcs":
                return "1";
            case "half doz":
                return "1";
            case "carton":
                return "1";
            case "dozen":
                return "1";
            case "box":
                return "1";
            case "crate":
                return "1"; // Added consistency
            default:
                return "1";
        }
    }

    private void addItem() {
        String item = itemsComboBox.getValue();
        String size = qtyComboBox.getValue();
        String priceText = priceField.getText().replaceAll("[^0-9,.]", "").replace(",", "");
        String countUnit = unitField.getText().trim().toLowerCase();

        // --- VALIDATION ---
        unitErrorLabel.setVisible(false);
        unitErrorLabel.setManaged(false);

        String countPattern = ".*(\\d|/)+(.*)(pcs|doz|carton|box|sack|dozen|kg|ml|l|crate|half doz).*";

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

            // 1. MONEY: How many units are being sold?
            // Example: "2 half doz" -> moneyMultiplier = 2.0
            double moneyMultiplier = getMoneyMultiplier(countUnit);
            double totalAmount = moneyMultiplier * unitPrice;

            // 2. STOCK CALCULATION (Moved UP for Cost Logic):
            // This calculates the actual total weight/quantity (e.g., "2 1/4 kg" -> 0.5)
            double weightForStock = getStockWeight(countUnit, size);
            String weightStr = String.valueOf(weightForStock);

            // 3. COST CALCULATION (Fixed):
            // Cost should be based on the ACTUAL weight being deducted from stock, not the
            // generic multiplier.
            // Cost = Total Weight * Cost Per Base Unit (e.g., 0.5kg * 5000/kg = 2500)
            double costPerPiece = dataManager.getDbHelper().getLastRecordedPrice(item, size);
            // We don't need dbMultiplier here because weightForStock already handles the
            // conversion
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

            // 4. STOCK CHECK:
            // Now hasEnoughStock will check if you have enough available
            if (!dataManager.getDbHelper().hasEnoughStock(item, size, weightStr)) {
                showAlert("Not enough stock!\nAvailable: " + dataManager.getDbHelper().getAvailableStock(item, size));
                return;
            }

            items.add(new SaleItem(
                    item,
                    size,
                    countUnit,
                    String.format("%,.2f", unitPrice),
                    String.format("%,.2f", totalAmount)));

            clearFields();
            updateTotal();

        } catch (NumberFormatException e) {
            showAlert("Invalid price format");
        }
    }

    /**
     * Returns the count of items for Price calculation.
     * Example: "2 1/4 kg" -> returns 2.0
     * Example: "1/4 kg" -> returns 1.0 (default)
     */
    private double getMoneyMultiplier(String text) {
        if (text == null || text.isEmpty())
            return 1.0;
        String lower = text.toLowerCase().trim();

        // Split by common units to find the leading number
        String[] parts = lower.split("(1/4|1/2|kg|sack|pcs|half doz|dozen|box|carton|crate)");
        if (parts.length > 0) {
            // If the string starts with a fraction (e.g. "1/4 kg"), parts[0] is empty or
            // just the fraction
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

    /**
     * Returns the actual weight/quantity for Stock subtraction.
     * Example: "2 1/4 kg" -> returns 0.5 (2 * 0.25)
     * Example: "2 1/2 kg" -> returns 1.0 (2 * 0.5)
     * Example: "5 kg" -> returns 5.0 (no fraction found)
     */
    private double getStockWeight(String text, String sizeStr) {
        String lower = text.toLowerCase();
        double count = getMoneyMultiplier(lower);

        // --- WEIGHT FRACTIONS ---
        if (lower.contains("1/4")) {
            return count * 0.25;
        } else if (lower.contains("1/2")) {
            return count * 0.5;
        }

        // --- PACKAGING UNITS ---
        else if (lower.contains("half doz")) {
            return count * 6; // 2 half doz = 12 pcs
        } else if (lower.contains("dozen")) {
            return count * 12; // 2 dozen = 24 pcs
        } else if (lower.contains("box")) {
            return count * 20; // Standard soda/beer crate is 24
        } else if (lower.contains("carton")) {
            return count * 24;
        } else if (lower.contains("crate")) {
            return count * 25;
        }
        // --- SACK LOGIC (THE FIX) ---
        else if (lower.contains("sack")) {
            // We extract the numeric value from the dropdown size (e.g., "50kg" -> 50.0)
            double kgPerSack = dataManager.getDbHelper().extractNumericValue(sizeStr);
            return count * kgPerSack;
        }

        // --- DEFAULT (kg, pcs, sack) ---
        else {
            return count;
        }
    }

    private void saveSale() {
        String customer = customerNameField.getText().trim();
        if (customer.isEmpty() || items.isEmpty()) {
            showAlert("Customer name and items required");
            return;
        }

        // DOUBLE CHECK stock availability before final save
        for (SaleItem item : items) {
            if (!dataManager.getDbHelper().hasEnoughStock(item.getItems(), item.getQty(), item.getUnit())) {
                String availableStock = dataManager.getDbHelper().getAvailableStock(item.getItems(), item.getQty());
                showAlert("Cannot complete sale! Stock changed since items were added.\n\n" +
                        "Item: " + item.getItems() + " " + item.getQty() + "\n" +
                        "Trying to sell: " + item.getUnit() + "\n" +
                        "Available: " + availableStock);
                return;
            }
        }

        String saleType = determineSaleType();

        // Save all sales and update stock
        for (SaleItem item : items) {
            double price = Double.parseDouble(item.getPrice().replaceAll("[^0-9.]", ""));
            double amount = Double.parseDouble(item.getAmount().replaceAll("[^0-9.]", ""));

            // Save sale
            // NEW LOGIC (Triggers cost lookup and profit calculation)
            dataManager.getDbHelper().addSaleWithProfit(
                    customer,
                    item.getItems(),
                    item.getQty(),
                    item.getUnit(),
                    price,
                    amount, // Changed from totalAmount to amount (for this specific item)
                    saleType);

            // Update stock - subtract COUNT from same SIZE
            updateStock(item.getItems(), item.getQty(), item.getUnit());
        }

        showAlert("Sale saved successfully! Stock updated.");

        // Clear everything after successful save
        items.clear();
        customerNameField.clear();
        itemsComboBox.setValue(null);
        qtyComboBox.setValue(null);
        unitField.clear();
        priceField.clear();
        updateTotal();

        // Notify all listeners that data has changed
        dataManager.notifyDataChanged();
    }

    private void clearFields() {
        // Don't clear the item selection, just unit and price
        unitField.clear();
        priceField.clear();
        qtyComboBox.setValue(null);
    }

    private void updateStock(String itemName, String soldQty, String soldUnit) {
        // Calculate the actual multiplication (e.g., "2 1/4 kg" -> 0.5)
        double actualWeight = getStockWeight(soldUnit, soldQty);

        // Pass the calculated number as a string so the DB helper subtracts 0.5
        dataManager.getDbHelper().updateStockQuantity(itemName, soldQty, String.valueOf(actualWeight));
    }

    private String determineSaleType() {
        for (SaleItem item : items) {
            String unit = item.getUnit().toLowerCase();
            if (unit.contains("half doz") || unit.contains("carton") ||
                    unit.contains("dozen") || unit.contains("box") ||
                    unit.contains("crate")) { // Added crate here
                return "WHOLESALE";
            }
        }
        return "RETAIL";
    }

    private void updateTotal() {
        double total = items.stream()
                .mapToDouble(item -> {
                    try {
                        return Double.parseDouble(item.getAmount().replaceAll("[^0-9.]", ""));
                    } catch (Exception e) {
                        return 0;
                    }
                })
                .sum();
        totalAmountLabel.setText(String.format("TOTAL AMOUNT: UGX %,.2f", total));
    }

    private void showAlert(String message) {
        com.meto.inventory.utils.DialogHelper.showAlert(message);
    }

    private boolean isValidExactUnit(String text) {
        // We match against the 'stripped' version of the units (no spaces)
        // because we strip spaces from the input when checking.
        // "half doz" -> "halfdoz"
        String[] allowed = { "kg", "pcs", "sack", "doz", "dozen", "box", "carton", "crate", "ml", "l", "halfdoz" };
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