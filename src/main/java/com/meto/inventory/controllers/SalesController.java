package com.meto.inventory.controllers;

import com.meto.inventory.DataManager;
import com.meto.inventory.models.SaleItem;
import javafx.collections.FXCollections;
import javafx.collections.ObservableList;
import javafx.fxml.FXML;
import javafx.scene.control.*;
import javafx.scene.layout.HBox;

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
    private HBox weightButtonsBox;
    @FXML
    private HBox unitButtonsBox;

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
        // We also want to protect the unit field slightly, though it needs flexibility
        unitField.setTextFormatter(new TextFormatter<>(change -> {
            if (change.getText().matches("[a-zA-Z0-9 .\\-,/]*"))
                return change;
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
    private void setBoxVisible(HBox box, boolean visible) {
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
        unitField.setText("1/4 kg");
        // Leave priceField alone so the user can type the "Whole Thing" price
    }

    @FXML
    private void handleHalfKg() {
        unitField.setText("1/2 kg");
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
                deleteBtn.setStyle("-fx-background-color: red; -fx-text-fill: white;");
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

        // Use "1/4" and "1/2" labels so the money logic knows these are special packets
        quarterKgBtn.setOnAction(e -> {
            unitField.setText("1/4 kg");
        });

        halfKgBtn.setOnAction(e -> {
            unitField.setText("1/2 kg");
        });

        kgBtn.setOnAction(e -> {
            String current = unitField.getText().replaceAll("[^0-9.]", "");
            unitField.setText(current.isEmpty() ? "1 kg" : current + " kg");
        });
        // New Sack Button Logic
        sackBtn.setOnAction(e -> {
            // Just set the text to "1 sack"
            // DatabaseHelper.getUnitMultiplier already knows that "sack"
            // for a 50kg item equals 50.
            unitField.setText("1 sack");
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
            String existingNumbers = text.replaceAll("[^0-9.]", "").trim();
            if (existingNumbers.isEmpty()) {
                unitField.setText(numericValue + " " + unit);
            } else {
                unitField.setText(text + " " + unit);
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
        // String countUnit = unitField.getText().trim();
        // Allow dot in regex
        String priceText = priceField.getText().replaceAll("[^0-9,.]", "").replace(",", "");

        unitErrorLabel.setVisible(false);
        unitErrorLabel.setManaged(false);

        String countUnit = unitField.getText().trim().toLowerCase();
        // Allow fractions (1/4, 1/2) or whole numbers + standard units
        // Added "crate" to this pattern as well
        String countPattern = ".*(\\d|/)+(.*)(pcs|doz|carton|box|sack|dozen|kg|ml|l|crate).*";

        if (countUnit.isEmpty() || !countUnit.matches(countPattern)) {
            unitErrorLabel.setVisible(true);
            unitErrorLabel.setManaged(true);
            return;
        } else {
            unitErrorLabel.setVisible(false);
            unitErrorLabel.setManaged(false);
        }
        if (item == null || size == null || countUnit.isEmpty() || priceText.isEmpty()) {
            showAlert("Please fill all fields");
            return;
        }

        try {
            double price = Double.parseDouble(priceText);

            // --- NEW CALCULATION LOGIC ---
            double moneyMultiplier;

            // If it's a pre-priced packet (1/4 or 1/2), the price is for the "Whole Thing"
            if (countUnit.contains("1/4") || countUnit.contains("1/2")) {
                // If user types "2 1/4 kg", extract the '2' as the multiplier.
                // If they just click the button ("1/4 kg"), multiplier is 1.
                double leadingNumber = extractLeadingNumber(countUnit);
                moneyMultiplier = (leadingNumber == 0) ? 1.0 : leadingNumber;
            } else {
                // For "5 kg" or "2 dozen", multiply price by the number
                moneyMultiplier = extractNumber(countUnit);
            }

            double amount = moneyMultiplier * price;
            // ------------------------------

            // --- PROFIT CHECK ---
            double costPerPiece = dataManager.getDbHelper().getLastRecordedPrice(item, size);
            double dbUnitCount = dataManager.getDbHelper().extractNumericValue(countUnit);
            double dbMultiplier = dataManager.getDbHelper().getUnitMultiplier(countUnit, size);
            double totalCost = dbUnitCount * dbMultiplier * costPerPiece;

            if (totalCost > 0 && amount < totalCost) {
                Alert alert = new Alert(Alert.AlertType.CONFIRMATION);
                alert.setTitle("Negative Profit Warning");
                alert.setHeaderText("Selling Below Cost Price!");
                alert.setContentText(String.format(
                        "You are selling this item for UGX %,.2f\nBut the cost price is UGX %,.2f\n\nThis will result in a LOSS.\n\nDo you want to proceed?",
                        amount, totalCost));

                if (alert.showAndWait().get() != ButtonType.OK) {
                    return; // Cancel addition
                }
            }
            // --------------------

            if (!dataManager.getDbHelper().hasEnoughStock(item, size, countUnit)) {
                showAlert("Not enough stock!\nAvailable: " + dataManager.getDbHelper().getAvailableStock(item, size));
                return;
            }

            items.add(new SaleItem(
                    item,
                    size,
                    countUnit,
                    String.format("%,.2f", price),
                    String.format("%,.2f", amount)));

            clearFields();
            updateTotal();

        } catch (NumberFormatException e) {
            showAlert("Invalid price format");
        }
    }

    private double extractLeadingNumber(String text) {
        // Looks for a number before the fraction (e.g., "2 1/4 kg" -> 2)
        String firstPart = text.split(" ")[0];
        try {
            if (firstPart.contains("/"))
                return 1.0; // It's just the fraction, so count as 1
            return Double.parseDouble(firstPart.replaceAll("[^0-9.]", ""));
        } catch (Exception e) {
            return 1.0;
        }
    }

    private double extractNumber(String text) {
        if (text.toLowerCase().contains("1/4") || text.contains("0.25"))
            return 0.25;
        if (text.toLowerCase().contains("1/2") || text.contains("0.5"))
            return 0.5;

        if (text.toLowerCase().contains("sack"))
            return 1.0;
        String numbers = text.replaceAll("[^0-9.]", "");
        return numbers.isEmpty() ? 1.0 : Double.parseDouble(numbers);
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
        // This method will subtract the sold quantity from stock
        dataManager.getDbHelper().updateStockQuantity(itemName, soldQty, soldUnit);
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
        new Alert(Alert.AlertType.INFORMATION, message, ButtonType.OK).showAndWait();
    }

    public void destroy() {
        dataManager.removeDataChangeListener(this);
    }
}