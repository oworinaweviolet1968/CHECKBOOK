package com.meto.inventory.controllers;

import com.meto.inventory.DataManager;
import com.meto.inventory.models.SaleItem;
import com.meto.inventory.services.ReceiptPrinterService;
import com.meto.inventory.utils.DialogHelper;
import javafx.collections.FXCollections;
import javafx.collections.ObservableList;
import javafx.fxml.FXML;
import javafx.scene.control.*;
import javafx.scene.layout.FlowPane;

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
    private ComboBox<String> priceField;
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
    private Button pcsBtn, halfDozBtn, box10Btn, box12Btn, box20Btn, box24Btn, box72Btn, crateBtn;

    @FXML
    private TableView<SaleItem> salesTable;
    @FXML
    private TableColumn<SaleItem, String> itemCol, qtyCol, unitCol, priceCol, amountCol;
    @FXML
    private TableColumn<SaleItem, Void> deleteCol;

    @FXML
    private Label totalAmountLabel;
    @FXML
    private CheckBox debtCheckBox;

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
            // Allowed: 0-9, space, *, / (for 1/2)
            if (newText.matches("[0-9 /*]*")) {
                // APPLY 9 DIGIT LIMIT to the numbers only
                String numericOnly = newText.replaceAll("[^0-9]", "");
                if (numericOnly.length() > 9)
                    return null;
                return change;
            }

            // ... strict button logic continues ...

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

        // 2. Strict Numbers for Price + 9 Digit Limit + Comma Formatting
        // Replacing the crash-prone ChangeListener with a stable TextFormatter
        java.text.DecimalFormat priceDf = new java.text.DecimalFormat("#,###");
        priceField.getEditor().setTextFormatter(new TextFormatter<>(change -> {
            if (change.isContentChange()) {
                String newText = change.getControlNewText().replaceAll(",", "");

                // 1. Digit Limit (9 digits)
                if (newText.length() > 9)
                    return null;

                // 2. Allow only digits
                if (!newText.matches("\\d*"))
                    return null;

                // 3. Auto-format with commas while protecting the cursor
                if (!newText.isEmpty()) {
                    try {
                        long value = Long.parseLong(newText);
                        String formatted = priceDf.format(value);

                        // We must be careful not to trigger infinite loops
                        // The TextFormatter handles the 'change' object directly
                        change.setText(formatted);
                        change.setRange(0, change.getControlText().length());
                        change.setCaretPosition(formatted.length());
                        change.setAnchor(formatted.length());
                    } catch (NumberFormatException e) {
                        return null;
                    }
                }
            }
            return change;
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

                // --- PRICE HISTORY UPDATE ---
                refreshPriceHistory(itemsComboBox.getValue(), newVal);
            }
        });

        unitField.textProperty().addListener((obs, oldVal, newVal) -> {
            unitErrorLabel.setVisible(false);
            unitErrorLabel.setManaged(false);

            if (newVal.trim().isEmpty()) {
                if (qtyComboBox.getValue() != null)
                    setFlowLevel(3);
                priceField.getEditor().clear();
            } else {
                // Only downgrade level if price is empty
                if (priceField.getEditor().getText().trim().isEmpty()) {
                    setFlowLevel(4);
                } else {
                    setFlowLevel(5);
                }
            }
        });

        // --- DELETED CRASH-PRONE CHANGE LISTENER ---
        // The stability fix is now handled by the TextFormatter above.

        priceField.getEditor().textProperty().addListener((obs, oldVal, newVal) -> {
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
            setNodeVisible(weightButtonsBox, false);
            setNodeVisible(unitButtonsBox, false);
            return;
        }

        double sizeNum = dataManager.getDbHelper().extractNumericValue(selectedSize);
        boolean isBulkWeight = selectedSize.toLowerCase().contains("kg") && sizeNum >= 10.0;
        setNodeVisible(sackBtn, isBulkWeight);
        setNodeVisible(sackUnitBtn, isBulkWeight);

        if (isBulkWeight) {
            setNodeVisible(weightButtonsBox, true);
            setNodeVisible(unitButtonsBox, false);
        } else {
            setNodeVisible(weightButtonsBox, false);
            setNodeVisible(unitButtonsBox, true);
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

    private void setNodeVisible(javafx.scene.Node node, boolean visible) {
        if (node != null) {
            node.setVisible(visible);
            node.setManaged(visible);
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
                refreshPriceHistory(selectedItem, qtyComboBox.getValue());
            }
        });
    }

    private void refreshPriceHistory(String item, String size) {
        if (item == null || size == null) {
            priceField.setItems(FXCollections.observableArrayList());
            return;
        }
        priceField.setItems(dataManager.getDbHelper().getPriceHistory(item, size));
    }

    /**
     * Refreshes dropdowns while preserving the user's current input.
     * The background auto-sync calls onDataChanged() periodically which triggers
     * this.
     * Without preserving state, every refresh would clear the form mid-typing.
     */
    private void refreshDropdowns() {
        // --- Save current user state BEFORE touching any items ---
        String currentCustomerText = customerNameComboBox.getEditor().getText();
        String currentCustomerValue = customerNameComboBox.getValue();
        String currentItem = itemsComboBox.getValue();
        String currentSize = qtyComboBox.getValue();
        String currentUnit = unitField.getText();
        String currentPrice = priceField.getEditor().getText();

        // Check if the user is actively composing a sale
        boolean userIsWorking = !items.isEmpty()
                || (currentCustomerText != null && !currentCustomerText.trim().isEmpty())
                || currentItem != null
                || (currentUnit != null && !currentUnit.trim().isEmpty())
                || (currentPrice != null && !currentPrice.trim().isEmpty());

        // --- Update item list ---
        ObservableList<String> availableItems = dataManager.getDbHelper().getAvailableItems();
        itemsComboBox.setItems(availableItems);

        // --- Update customer list ---
        ObservableList<String> customers = FXCollections.observableArrayList();
        customers.add("Walk-in Customer");
        customers.addAll(dataManager.getDbHelper().getDistinctCustomers());
        customerNameComboBox.setItems(customers);

        // --- Restore selections if user was working ---
        if (userIsWorking) {
            // Restore customer name
            if (currentCustomerText != null && !currentCustomerText.trim().isEmpty()) {
                customerNameComboBox.getEditor().setText(currentCustomerText);
            } else if (currentCustomerValue != null) {
                customerNameComboBox.setValue(currentCustomerValue);
            }

            // Restore item selection
            if (currentItem != null && availableItems.contains(currentItem)) {
                itemsComboBox.setValue(currentItem);
                // Restore sizes for the selected item
                refreshSizesDropdown(currentItem);

                // Restore size selection
                if (currentSize != null) {
                    ObservableList<String> sizes = qtyComboBox.getItems();
                    if (sizes != null && sizes.contains(currentSize)) {
                        qtyComboBox.setValue(currentSize);
                    }
                }
            }

            // Restore unit field
            if (currentUnit != null && !currentUnit.trim().isEmpty()) {
                unitField.setText(currentUnit);
            }

            // Restore price field
            if (currentPrice != null && !currentPrice.trim().isEmpty()) {
                priceField.getEditor().setText(currentPrice);
            }
        } else {
            qtyComboBox.setItems(FXCollections.observableArrayList());
        }
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
        unitCol.setCellFactory(col -> new TableCell<>() {
            @Override
            protected void updateItem(String item, boolean empty) {
                super.updateItem(item, empty);
                if (empty || item == null) {
                    setText(null);
                    setStyle("");
                } else {
                    setText(item);
                    setStyle("-fx-text-fill: green; -fx-font-weight: bold;");
                }
            }
        });
        priceCol.setCellValueFactory(data -> data.getValue().priceProperty());
        amountCol.setCellValueFactory(data -> data.getValue().amountProperty());
        amountCol.setCellFactory(col -> new TableCell<>() {
            @Override
            protected void updateItem(String item, boolean empty) {
                super.updateItem(item, empty);
                if (empty || item == null) {
                    setText(null);
                    setStyle("");
                } else {
                    setText(item);
                    setStyle("-fx-text-fill: green; -fx-font-weight: bold;");
                }
            }
        });

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
        saveButton.setOnAction(e -> {
            ProgressIndicator spinner = new ProgressIndicator();
            spinner.setPrefSize(16, 16);
            spinner.setMaxSize(16, 16);
            saveButton.setGraphic(spinner);
            saveButton.setDisable(true);

            javafx.application.Platform.runLater(() -> {
                try {
                    showSaleSummaryDialog();
                } finally {
                    saveButton.setGraphic(null);
                    saveButton.setDisable(false);
                }
            });
        });

        // Collect all weight buttons and unit buttons for selection tracking
        java.util.List<Button> wBtns = java.util.List.of(quarterKgBtn, halfKgBtn, kgBtn, sackBtn);
        java.util.List<Button> uBtns = java.util.List.of(pcsBtn, halfDozBtn, box10Btn, box12Btn, box20Btn, box24Btn,
                box72Btn, crateBtn, sackUnitBtn);

        quarterKgBtn.setOnAction(e -> {
            selectQuickBtn(quarterKgBtn, wBtns);
            String n = extractBaseQuantity(unitField.getText());
            unitField.setText(n + " 1/4 kg");
        });

        halfKgBtn.setOnAction(e -> {
            selectQuickBtn(halfKgBtn, wBtns);
            String n = extractBaseQuantity(unitField.getText());
            unitField.setText(n + " 1/2 kg");
        });

        kgBtn.setOnAction(e -> {
            selectQuickBtn(kgBtn, wBtns);
            String n = extractBaseQuantity(unitField.getText());
            unitField.setText(n + " kg");
        });

        sackBtn.setOnAction(e -> {
            selectQuickBtn(sackBtn, wBtns);
            String n = extractBaseQuantity(unitField.getText());
            unitField.setText(n + " sack");
        });

        // UNIT buttons (packaging units)
        pcsBtn.setOnAction(e -> {
            selectQuickBtn(pcsBtn, uBtns);
            appendToUnit("pcs");
        });
        halfDozBtn.setOnAction(e -> {
            selectQuickBtn(halfDozBtn, uBtns);
            appendToUnit("Half Doz * 6");
        });
        box10Btn.setOnAction(e -> {
            selectQuickBtn(box10Btn, uBtns);
            appendToUnit("Box * 10");
        });
        box12Btn.setOnAction(e -> {
            selectQuickBtn(box12Btn, uBtns);
            appendToUnit("Dozen");
        });
        box20Btn.setOnAction(e -> {
            selectQuickBtn(box20Btn, uBtns);
            appendToUnit("Box * 20");
        });
        box24Btn.setOnAction(e -> {
            selectQuickBtn(box24Btn, uBtns);
            appendToUnit("Box * 24");
        });
        box72Btn.setOnAction(e -> {
            selectQuickBtn(box72Btn, uBtns);
            appendToUnit("Box * 72");
        });
        crateBtn.setOnAction(e -> {
            selectQuickBtn(crateBtn, uBtns);
            appendToUnit("Crate * 25");
        });
        sackUnitBtn.setOnAction(e -> {
            selectQuickBtn(sackUnitBtn, uBtns);
            appendToUnit("Sack");
        });
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
        String existingQty = extractBaseQuantity(unitField.getText());
        unitField.setText(existingQty + " " + unit);
    }

    /**
     * Extracts ONLY the leading numeric quantity from the unit field.
     * e.g. "1 Box * 72" -> "1"
     * e.g. "2.5 pcs" -> "2.5"
     * e.g. "" -> "1"
     */
    private String extractBaseQuantity(String text) {
        if (text == null || text.trim().isEmpty())
            return "1";

        // Match numbers, dots, or fractions at the VERY START of the string
        java.util.regex.Pattern p = java.util.regex.Pattern.compile("^([0-9./]+)");
        java.util.regex.Matcher m = p.matcher(text.trim());

        if (m.find()) {
            return m.group(1);
        }
        return "1";
    }

    private void addItem() {
        String item = itemsComboBox.getValue();
        String size = qtyComboBox.getValue();
        String priceText = priceField.getEditor().getText().replaceAll("[^0-9,.]", "").replace(",", "");
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
            double totalAmount = dataManager.getDbHelper().extractNumericValue(countUnit) * unitPrice;

            double totalCost = 0;
            double piecesForStock = 0;

            // Retrieve bulk unit from stock to ensure correct multiplier detection
            String bulkUnit = "";
            try (java.sql.PreparedStatement pstmt = dataManager.getDbHelper().getConnection()
                    .prepareStatement("SELECT unit FROM stock WHERE item = ? AND quantity = ? LIMIT 1")) {
                pstmt.setString(1, item);
                pstmt.setString(2, size);
                java.sql.ResultSet rs = pstmt.executeQuery();
                if (rs.next())
                    bulkUnit = rs.getString("unit");
            } catch (java.sql.SQLException e) {
                e.printStackTrace();
            }

            double quantityCount = dataManager.getDbHelper().extractNumericValue(countUnit);
            double multiplier = dataManager.getDbHelper().getUnitMultiplier(countUnit, size, bulkUnit);
            piecesForStock = quantityCount * multiplier;

            double costPerPiece = dataManager.getDbHelper().getLastRecordedPrice(item, size);
            totalCost = piecesForStock * costPerPiece;

            if (totalCost > 0 && totalAmount < totalCost) {
                String content = String.format(
                        "Warning: Potential Loss!\nSelling Price: UGX %,.2f\nActual Cost: UGX %,.2f\n\nProceed anyway?",
                        totalAmount, totalCost);
                if (!DialogHelper.showConfirm("Profit Warning", "Selling Below Cost",
                        content)) {
                    return;
                }
            }

            if (!dataManager.getDbHelper().hasEnoughStock(item, size, countUnit)) {
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

    private void showSaleSummaryDialog() {
        String customer = customerNameComboBox.getEditor().getText().trim();
        if (customer.isEmpty() && customerNameComboBox.getValue() != null)
            customer = customerNameComboBox.getValue().trim();

        if (customer.isEmpty() || items.isEmpty()) {
            showAlert("Customer name and items required");
            return;
        }

        Dialog<ButtonType> dialog = new Dialog<>();
        dialog.setTitle("Receipt Preview");
        dialog.setHeaderText(null);

        // --- Custom Styling ---
        DialogPane dialogPane = dialog.getDialogPane();
        dialogPane.setStyle("-fx-background-color: white;");

        // Header
        Label headerLabel = new Label("CHECKBOOK APP");
        headerLabel.setStyle(
                "-fx-background-color: #2e7d32; -fx-text-fill: white; -fx-font-weight: bold; -fx-font-size: 18px; -fx-padding: 15; -fx-alignment: center;");
        headerLabel.setMaxWidth(Double.MAX_VALUE);

        String shopName = dataManager.getDbHelper().getSetting("receipt_shop_name");
        Label shopNameLabel = null;
        if (shopName != null && !shopName.trim().isEmpty()) {
            shopNameLabel = new Label(shopName.toUpperCase());
            shopNameLabel
                    .setStyle("-fx-text-fill: #2e7d32; -fx-font-weight: bold; -fx-font-size: 14px; -fx-padding: 5 0;");
        }

        Label subHeaderLabel = new Label("Receipt Summary");
        subHeaderLabel.setStyle("-fx-text-fill: #666; -fx-font-size: 12px; -fx-padding: 5 0 10 0;");

        // Customer Info
        Label customerLabel = new Label("Customer: " + customer);
        customerLabel.setStyle("-fx-font-weight: bold; -fx-font-size: 14px; -fx-padding: 10 0;");

        // Item List (Simplified View)
        javafx.scene.layout.VBox itemBox = new javafx.scene.layout.VBox(5);
        itemBox.setStyle(
                "-fx-padding: 10; -fx-background-color: #f9f9f9; -fx-border-color: #eee; -fx-border-radius: 5; -fx-background-radius: 5;");
        for (SaleItem item : items) {
            javafx.scene.layout.HBox row = new javafx.scene.layout.HBox(10);

            // Format item title including size if valid, exactly like mobile
            String itemName = item.getItems();
            String size = item.getQty();
            if (size != null && !size.trim().isEmpty() && !size.trim().equalsIgnoreCase("none")) {
                itemName += " (" + size + ")";
            }
            Label name = new Label(itemName);
            name.setStyle("-fx-font-weight: bold; -fx-font-size: 13px;");

            // Format quantity and unit details exactly like mobile
            Label details = new Label(item.getUnit());
            details.setStyle("-fx-text-fill: #777; -fx-font-size: 11px;");

            javafx.scene.layout.Region spacer = new javafx.scene.layout.Region();
            javafx.scene.layout.HBox.setHgrow(spacer, javafx.scene.layout.Priority.ALWAYS);

            Label price = new Label("UGX " + item.getAmount());
            price.setStyle("-fx-font-weight: bold; -fx-font-size: 13px;");

            row.getChildren().addAll(new javafx.scene.layout.VBox(name, details), spacer, price);
            itemBox.getChildren().add(row);
        }

        // Total
        Label totalLabel = new Label(totalAmountLabel.getText());
        totalLabel.setStyle("-fx-font-weight: 900; -fx-font-size: 16px; -fx-text-fill: #2e7d32; -fx-padding: 15 0;");

        Label questionLabel = new Label("Do you want to print an invoice?");
        questionLabel.setStyle("-fx-font-weight: bold; -fx-text-fill: #555;");

        javafx.scene.layout.VBox content;
        if (shopNameLabel != null) {
            content = new javafx.scene.layout.VBox(5, headerLabel, shopNameLabel, subHeaderLabel, customerLabel,
                    itemBox, totalLabel, questionLabel);
        } else {
            content = new javafx.scene.layout.VBox(5, headerLabel, subHeaderLabel, customerLabel, itemBox, totalLabel,
                    questionLabel);
        }
        content.setPrefWidth(400);
        content.setAlignment(javafx.geometry.Pos.TOP_CENTER);
        dialogPane.setContent(content);

        // Buttons
        ButtonType printBtn = new ButtonType("Yes, Print & Finish", ButtonBar.ButtonData.OK_DONE);
        ButtonType saveBtn = new ButtonType("No, Just Save", ButtonBar.ButtonData.OTHER);
        ButtonType cancelBtn = new ButtonType("Cancel", ButtonBar.ButtonData.CANCEL_CLOSE);

        dialogPane.getButtonTypes().addAll(printBtn, saveBtn, cancelBtn);

        // Style and add loading spinners on click
        Button printNode = (Button) dialogPane.lookupButton(printBtn);
        Button saveNode = (Button) dialogPane.lookupButton(saveBtn);
        printNode.setStyle("-fx-background-color: #2e7d32; -fx-text-fill: white; -fx-font-weight: bold;");

        printNode.addEventFilter(javafx.event.ActionEvent.ACTION, event -> {
            event.consume(); // Prevent closing before save finishes
            ProgressIndicator spinner = new ProgressIndicator();
            spinner.setPrefSize(16, 16);
            spinner.setMaxSize(16, 16);
            printNode.setGraphic(spinner);
            printNode.setDisable(true);
            saveNode.setDisable(true);

            javafx.application.Platform.runLater(() -> {
                try {
                    saveSale(true);
                } finally {
                    dialog.setResult(printBtn);
                    dialog.close();
                }
            });
        });

        saveNode.addEventFilter(javafx.event.ActionEvent.ACTION, event -> {
            event.consume(); // Prevent closing before save finishes
            ProgressIndicator spinner = new ProgressIndicator();
            spinner.setPrefSize(16, 16);
            spinner.setMaxSize(16, 16);
            saveNode.setGraphic(spinner);
            saveNode.setDisable(true);
            printNode.setDisable(true);

            javafx.application.Platform.runLater(() -> {
                try {
                    saveSale(false);
                } finally {
                    dialog.setResult(saveBtn);
                    dialog.close();
                }
            });
        });

        dialog.showAndWait();
    }

    private void saveSale(boolean shouldPrint) {
        if (shouldPrint) {
            ReceiptPrinterService.printReceipt(items,
                    customerNameComboBox.getEditor().getText().trim(),
                    totalAmountLabel.getText());
        }

        String customer = customerNameComboBox.getEditor().getText().trim();
        if (customer.isEmpty() && customerNameComboBox.getValue() != null)
            customer = customerNameComboBox.getValue().trim();

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
        boolean isDebt = debtCheckBox.isSelected();
        String receiptId = java.util.UUID.randomUUID().toString();

        double profitPeakBefore = dataManager.getDbHelper().getProfitPeak();
        double todaysProfitBefore = dataManager.getDbHelper().getTodaysProfit();

        for (SaleItem item : items) {
            double price = Double.parseDouble(item.getPrice().replaceAll("[^0-9.]", ""));
            double amount = Double.parseDouble(item.getAmount().replaceAll("[^0-9.]", ""));
            dataManager.getDbHelper().addSaleWithProfit(customer, item.getItems(), item.getQty(), item.getUnit(), price,
                    amount, saleType, isDebt, receiptId);
            updateStock(item.getItems(), item.getQty(), item.getUnit());

            // Check Low Stock
            double piecesLeft = dataManager.getDbHelper().getAvailablePieces(item.getItems(), item.getQty());
            if (piecesLeft < 12) {
                com.meto.inventory.services.NotificationService.getInstance().sendDesktopActionNotification("Low Stock",
                        item.getItems() + " is running low [" + String.format("%.0f", piecesLeft) + " pcs left]");
            }
        }

        double todaysProfitAfter = dataManager.getDbHelper().getTodaysProfit();
        if (todaysProfitAfter > profitPeakBefore && todaysProfitBefore <= profitPeakBefore) {
            com.meto.inventory.services.NotificationService.getInstance().sendDesktopActionNotification(
                    "🎉New profit Record", "you have surpassed your previous profit peak");
        }

        if (!items.isEmpty()) {
            java.util.List<String> itemNames = new java.util.ArrayList<>();
            for (SaleItem item : items) {
                itemNames.add(item.getItems());
            }
            String itemsStr = String.join(", ", itemNames);
            String action = isDebt ? "Debt recorded" : "Sale made";
            dataManager.getDbHelper().addNotification(action + " for " + customer + ": " + itemsStr, "Desktop");

            if (isDebt) {
                double totalDebt = dataManager.getDbHelper().getCustomerDebt(customer);
                com.meto.inventory.services.NotificationService.getInstance().sendDesktopActionNotification(
                        "New Credit Sale",
                        customer + " now owes UGX " + String.format("%,.0f", totalDebt) + ". Tap to view the invoice.");
            } else {
                com.meto.inventory.services.NotificationService.getInstance().sendDesktopActionNotification(
                        "New Sale Recorded", customer + " just completed a order. Tap to view what was bought.");
            }
        }

        items.clear();
        customerNameComboBox.getEditor().clear();
        customerNameComboBox.setValue(null);
        itemsComboBox.setValue(null);
        qtyComboBox.setValue(null);
        unitField.clear();
        priceField.getEditor().clear();
        debtCheckBox.setSelected(false);
        updateTotal();
        dataManager.notifyDataChanged();

        if (!shouldPrint) {
            showAlert("Sale saved successfully! Stock updated.");
        } else {
            showAlert("Sale Finalized! (Invoice processing logic placeholder triggered)");
        }
    }

    private void clearFields() {
        unitField.clear();
        priceField.getEditor().clear();
        priceField.setValue(null);
        qtyComboBox.setValue(null);
    }

    private void updateStock(String itemName, String soldQty, String soldUnit) {
        dataManager.getDbHelper().updateStockQuantity(itemName, soldQty, soldUnit);
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
        DialogHelper.showAlert(message);
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