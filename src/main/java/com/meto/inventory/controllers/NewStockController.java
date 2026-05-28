package com.meto.inventory.controllers;

import com.meto.inventory.DataManager;
import com.meto.inventory.models.StockItem;
import javafx.beans.binding.Bindings;
import javafx.collections.FXCollections;
import javafx.collections.ObservableList;
import javafx.fxml.FXML;
import javafx.scene.control.*;
import javafx.scene.input.KeyEvent;
import javafx.scene.layout.FlowPane;
import java.time.LocalDate;
import java.util.Map;

public class NewStockController implements DataManager.DataChangeListener {

    @FXML
    private ComboBox<String> supplierNameComboBox;
    @FXML
    private TextField unitField;
    @FXML
    private TextField priceField;
    @FXML
    private Button addButton;
    @FXML
    private Button saveButton;
    @FXML
    private TableView<StockItem> newStockTable;
    @FXML
    private TableColumn<StockItem, Void> actionColumn;
    @FXML
    private TableColumn<StockItem, String> previewItemCol, previewTotalCol;
    @FXML
    private Label totalAmountLabel;
    @FXML
    private Button clearButton;
    @FXML
    private FlowPane qtyButtonsBox;
    @FXML
    private FlowPane unitButtonsBox;
    @FXML
    private Label supplierErrorLabel, itemErrorLabel, qtyErrorLabel, unitErrorLabel, priceErrorLabel;
    @FXML
    private ComboBox<String> itemsComboBox;
    @FXML
    private ComboBox<String> qtyComboBox;

    private final ObservableList<StockItem> items = FXCollections.observableArrayList();
    private final DataManager dataManager = DataManager.getInstance();
    private final java.util.Map<String, Button> unitButtonsMap = new java.util.HashMap<>();
    private final java.util.Map<String, Button> qtyButtonsMap = new java.util.HashMap<>();

    @FXML
    public void initialize() {
        refreshDropdowns();
        createQtyQuickButtons();
        createUnitQuickButtons();
        setupTableColumns();
        setupAutoPriceCalculation();

        // Register for data changes (sync/updates)
        dataManager.addDataChangeListener(this);

        // --- SECURITY: BLOCK FORBIDDEN CHARACTERS & LIMIT LENGTH ---
        java.util.function.UnaryOperator<TextFormatter.Change> filter = change -> {
            String newText = change.getControlNewText();
            // 1. Length Limit (45 chars)
            if (newText.length() > 45)
                return null;

            // 2. Block forbidden patterns
            if (newText.contains("//") || newText.contains("..") || newText.contains(";;") || newText.contains("@@")) {
                return null;
            }

            // 3. Allow only specific characters
            // Same as SalesController: A-Z, 0-9, space, dot, dash, comma, slash
            if (change.getText().matches("[a-zA-Z0-9 .\\-,/]*")) {
                return change;
            }
            return null;
        };
        supplierNameComboBox.getEditor().setTextFormatter(new TextFormatter<>(filter));
        itemsComboBox.getEditor().setTextFormatter(new TextFormatter<>(filter));
        // --- STEP 0: QUANTITY INPUT (9-Digit Limit) ---
        unitField.setTextFormatter(new TextFormatter<>(change -> {
            String newText = change.getControlNewText().toLowerCase();
            if (newText.isEmpty()) return change;
            
            // Allow numbers, spaces, and stars (for Box * 10 etc)
            if (newText.matches("[0-9 /*]*")) {
                String numericOnly = newText.replaceAll("[^0-9]", "");
                if (numericOnly.length() > 9) return null;
                return change;
            }
            return change; // Allow button-based text updates
        }));

        // --- STEP 0: START LOCKED ---
        setFlowLevel(0);

        // --- STEP 1: ITEM SELECTION ---
        itemsComboBox.getEditor().textProperty().addListener((obs, old, newVal) -> {
            qtyComboBox.getEditor().clear();
            unitField.clear();
            priceField.clear();
            qtyErrorLabel.setVisible(false);

            if (newVal != null && !newVal.trim().isEmpty()) {
                setFlowLevel(1); // This enables the buttons by default

                // CHECK IF ITEM EXISTS IN DB
                boolean itemExists = itemsComboBox.getItems().contains(newVal);
                updateQtyButtonsLockState(itemExists);

                ObservableList<String> sizes = dataManager.getDbHelper().getItemSizes(newVal);
                qtyComboBox.setItems(sizes);

                if (!sizes.isEmpty()) {
                    qtyErrorLabel.setText("* Use dropdown for existing sizes");
                    qtyErrorLabel.setStyle("-fx-text-fill: #ffa000;");
                    qtyErrorLabel.setVisible(true);
                }
            } else {
                setFlowLevel(0);
                updateQtyButtonsLockState(false); // Reset to default state
            }
        });

        // --- STEP 2: QTY VALIDATION (The Enforcer) ---
        qtyComboBox.getEditor().textProperty().addListener((obs, old, newVal) -> {
            // 1. Basic Flow Logic
            String sizePattern = ".*\\d+(g|kg|ml|l|inch)$|^none$";
            if (newVal != null && newVal.toLowerCase().matches(sizePattern)) {
                filterUnitButtons(newVal);
                setFlowLevel(2);
            } else {
                // We don't call setFlowLevel(1) here because it would reset the buttons
                unitField.setDisable(true);
                unitButtonsBox.setDisable(true);
            }

            // 2. THE LOCK ENFORCER:
            // This runs AFTER setFlowLevel to ensure it has the final say.
            boolean isExistingSize = qtyComboBox.getItems().contains(newVal);
            if (isExistingSize) {
                // If it matches a DB record, we FORCE the buttons to stay off
                qtyButtonsBox.setDisable(true);
                qtyButtonsBox.setOpacity(0.4);
                qtyErrorLabel.setText("* Record Found: Buttons Locked");
                qtyErrorLabel.setStyle("-fx-text-fill: #2e7d32;");
                qtyErrorLabel.setVisible(true);
            } else {
                // Only enable buttons if we are at the right flow level AND it's a new size
                qtyButtonsBox.setDisable(false);
                qtyButtonsBox.setOpacity(1.0);
                // If it's not a match, show the standard unit warning
                if (!newVal.toLowerCase().matches(sizePattern)) {
                    qtyErrorLabel.setText("* Missing size unit (e.g., 500ml, 1kg)");
                    qtyErrorLabel.setStyle("-fx-text-fill: red;");
                    qtyErrorLabel.setVisible(true);
                }
            }
        });

        // --- STEP 3: UNIT VALIDATION ---
        unitField.textProperty().addListener((obs, old, newVal) -> {
            String countPattern = ".*\\d+.*(pc|pcs|doz|carton|box|sack|dozen|crate|box\\*10|box\\*12|box\\*20|box\\*24|box\\*72).*";
            if (newVal.toLowerCase().matches(countPattern)) {
                setFlowLevel(3);
            } else {
                addButton.setDisable(true);
            }
        });

        // --- PRICE FIELD: COMMA FORMATTING & TEXT BLOCKING ---
        priceField.setTextFormatter(new TextFormatter<>(change -> {
            if (change.isContentChange()) {
                String newText = change.getControlNewText();
                
                // 1. Allow dot and digits ONLY
                if (!newText.matches("[0-9., ]*")) {
                    return null;
                }

                // 2. Prevent multiple dots OR more than 9 digits (excluding dot/commas)
                String numericOnly = newText.replaceAll("[^0-9]", "");
                if (numericOnly.length() > 9) return null;

                if (newText.chars().filter(ch -> ch == '.').count() > 1) {
                    return null;
                }

                // 3. Format with commas if it doesn't end with a dot
                // We do this by sanitizing and then re-formatting
                String clean = newText.replaceAll("[^0-9.]", "");
                if (clean.isEmpty()) return change;

                try {
                    if (clean.contains(".") || clean.isEmpty()) {
                        return change; // Don't format decimals or empty while typing
                    } else {
                        long val = Long.parseLong(clean);
                        String formatted = String.format("%,d", val);
                        
                        // To avoid cursor jumping or infinite loop, only apply if change is different
                        if (!change.getControlNewText().equals(formatted)) {
                            change.setText(formatted);
                            change.setRange(0, change.getControlText().length());
                        }
                    }
                } catch (Exception e) {}
            }
            return change;
        }));

        // PRICE field: allow digits and a single dot only
        priceField.addEventFilter(KeyEvent.KEY_TYPED, event -> {
            String character = event.getCharacter();
            // Allow digits and only allow one decimal point
            if (!character.matches("[0-9]") && !(character.equals(".") && !priceField.getText().contains("."))) {
                event.consume(); // Block the key press if it's a letter or second dot
            }
        });

        // PRICE LOCK LOGIC
        qtyComboBox.setOnAction(e -> handleQtySelection());

        // CONFIGURE TABLE
        newStockTable.setItems(items);
        setupTableColumns();
        setupAutoPriceCalculation();
        // EVENT HANDLERS
        qtyComboBox.setOnAction(e -> handleQtySelection());
        addButton.setOnAction(e -> onAdd());
        saveButton.setOnAction(e -> onSave());

        // BIND TOTAL LABEL
        totalAmountLabel.textProperty().bind(Bindings.createStringBinding(() -> {
            double sum = items.stream().mapToDouble(s -> {
                String amtStr = s.getAmount().replaceAll("[^0-9.]", "");
                return amtStr.isEmpty() ? 0.0 : Double.parseDouble(amtStr);
            }).sum();
            return sum == 0 ? "TOTAL AMOUNT : " : String.format("TOTAL AMOUNT : UGX %,.2f", sum);
        }, items));

        // QTY INPUT FILTER (Numbers only)
        qtyComboBox.addEventFilter(KeyEvent.KEY_TYPED, this::filterQtyInput);
    }

    // --- HELPER FOR FLOW CONTROL ---
    private void setFlowLevel(int level) {
        // level 0: Supplier/Item only
        // level 1: Item picked -> Enable Qty
        // level 2: Qty picked -> Enable Unit
        // level 3: Unit picked -> Enable Price/Add

        qtyComboBox.setDisable(level < 1);
        qtyButtonsBox.setDisable(level < 1);

        unitField.setDisable(level < 2);
        unitButtonsBox.setDisable(level < 2);

        priceField.setDisable(level < 2);
        addButton.setDisable(level < 3);
    }

    /**
     * Extracts ONLY the leading numeric quantity from the text field.
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
    private void handleQtySelection() {
        String item = itemsComboBox.getValue();
        String size = qtyComboBox.getEditor().getText();

        if (item != null && size != null && !size.isEmpty()) {
            double lastPrice = dataManager.getDbHelper().getLastRecordedPrice(item, size);

            if (lastPrice > 0) {
                priceField.setText(String.format("%.2f", lastPrice));

                // LOCK FIELD TO PREVENT EDITS ON RECORDS
                priceField.setEditable(false);
                priceField.setMouseTransparent(true);
                priceField.setStyle("-fx-background-color: #F3F4F6; -fx-text-fill: #6B7280;"); // Greyed out look

                // KEEP QUICK BUTTONS ENABLED
                qtyButtonsBox.setDisable(false);
                qtyButtonsBox.setOpacity(1.0);

                qtyErrorLabel.setText("* Record found: Auto-filled price");
                qtyErrorLabel.setVisible(true);
                qtyErrorLabel.setStyle("-fx-text-fill: #2e7d32;"); // Success green
            } else {
                // UNLOCK IF IT'S A NEW SIZE
                priceField.setEditable(true);
                priceField.setMouseTransparent(false);
                priceField.setStyle("");

                qtyButtonsBox.setDisable(false);
                qtyButtonsBox.setOpacity(1.0);
                qtyErrorLabel.setVisible(false);
            }
        }
    }

    private void setupTableColumns() {
        // Item column: same VBox design as Today's Sales Log
        previewItemCol.setCellValueFactory(data -> data.getValue().itemsProperty());
        previewItemCol.setCellFactory(col -> new TableCell<>() {
            @Override
            protected void updateItem(String item, boolean empty) {
                super.updateItem(item, empty);
                if (empty || item == null || getTableRow() == null || getTableRow().getItem() == null) {
                    setGraphic(null);
                    setText(null);
                } else {
                    StockItem si = getTableRow().getItem();
                    javafx.scene.layout.VBox box = new javafx.scene.layout.VBox(2);

                    javafx.scene.layout.HBox nameBox = new javafx.scene.layout.HBox(6);
                    nameBox.setAlignment(javafx.geometry.Pos.BOTTOM_LEFT);

                    Label nameLabel = new Label(item);
                    nameLabel.getStyleClass().add("bold-label");

                    Label sizeLabel = new Label(si.getQty() != null ? si.getQty() : "");
                    sizeLabel.setStyle("-fx-text-fill: -fx-text-muted; -fx-font-size: 11px;");

                    nameBox.getChildren().addAll(nameLabel, sizeLabel);
                    box.getChildren().add(nameBox);
                    box.setAlignment(javafx.geometry.Pos.CENTER_LEFT);
                    setGraphic(box);
                    setAlignment(javafx.geometry.Pos.CENTER_LEFT);
                }
            }
        });

        // Total column: green text
        previewTotalCol.setCellFactory(col -> new TableCell<StockItem, String>() {
            @Override
            protected void updateItem(String item, boolean empty) {
                super.updateItem(item, empty);
                if (empty || item == null) {
                    setText(null);
                    setGraphic(null);
                } else {
                    setText(item);
                    setStyle("-fx-text-fill: #10B981; -fx-font-weight: bold;"); // Green
                    setAlignment(javafx.geometry.Pos.CENTER_LEFT);
                }
            }
        });

        // Delete button column
        actionColumn.setCellFactory(col -> new TableCell<>() {
            private final Button deleteButton = new Button("Delete");
            {
                deleteButton.getStyleClass().add("btn-red");
                deleteButton.setStyle("-fx-font-size: 10px; -fx-padding: 2 6;"); // Ensure consistency
                deleteButton.setOnAction(e -> items.remove(getTableView().getItems().get(getIndex())));
            }

            @Override
            protected void updateItem(Void item, boolean empty) {
                super.updateItem(item, empty);
                setGraphic(empty ? null : deleteButton);
            }
        });
    }

    private void setupAutoPriceCalculation() {
        unitField.textProperty().addListener((obs, oldVal, newVal) -> {
            String item = itemsComboBox.getEditor().getText();
            String size = qtyComboBox.getEditor().getText();

            if (!item.isEmpty() && !size.isEmpty() && !newVal.isEmpty()) {
                double costPerPiece = dataManager.getDbHelper().getExistingPrice(item, size);

                if (costPerPiece > 0) {
                    double multiplier = dataManager.getDbHelper().getUnitMultiplier(newVal, size, newVal);
                    double count = extractNumericValue(newVal);

                    double totalAmount = count * multiplier * costPerPiece;
                    priceField.setText(String.format("%.2f", totalAmount));

                    // Lock it for auto-calculated prices
                    priceField.setEditable(false);
                    priceField.setStyle("-fx-background-color: #F3F4F6; -fx-text-fill: #6B7280;");
                }
            }
        });
    }

    private double extractNumericValue(String text) {
        return dataManager.getDbHelper().extractNumericValue(text);
    }

    private void refreshDropdowns() {
        ObservableList<String> availableItems = dataManager.getDbHelper().getAvailableItems();
        itemsComboBox.setItems(availableItems);
        itemsComboBox.getEditor().clear();

        // Populate supplier dropdown from past stock entries
        ObservableList<String> suppliers = dataManager.getDbHelper().getDistinctSuppliers();
        supplierNameComboBox.setItems(suppliers);
    }

    private void createQtyQuickButtons() {
        String[] quick = { "None", "g", "kg", "ml", "l", "inch", "50kg", "25kg", "10kg" };
        for (String q : quick) {
            Button b = new Button(q);
            b.getStyleClass().add("pill-quick");
            b.setOnAction(evt -> {
                selectQuickButton(b, qtyButtonsMap);
                appendUnitToQty(q);
            });
            qtyButtonsBox.getChildren().add(b);
            qtyButtonsMap.put(q, b);
        }
    }

    private void updateQtyButtonsLockState(boolean itemExists) {
        // Buttons to lock if item exists
        // UNLOCK ALL buttons as requested by user to allow adding new sizes (e.g. 1l
        // for Soda)
        for (Button btn : qtyButtonsMap.values()) {
            btn.setDisable(false);
        }
    }

    private void createUnitQuickButtons() {
        Map<String, String> unitLabels = Map.of(
                "pcs", "pcs * 1", "sack", "Sack", "half doz", "Half Doz * 6",
                "dozen", "Dozen", "box*10", "Box * 10", "box*12", "Dozen",
                "box*20", "Box * 20", "box*24", "Box * 24", "crate", "Crate * 25",
                "box*72", "Box * 72");

        Map<String, Integer> unitMultipliers = Map.of(
                "pcs", 1, "sack", 1, "half doz", 6,
                "dozen", 12, "box*10", 10, "box*12", 12,
                "box*20", 20, "box*24", 24, "crate", 25, "box*72", 72);

        String[] order = { "pcs", "sack", "half doz", "box*10", "box*12", "box*20", "box*24", "crate", "box*72" };

        for (String unitKey : order) {
            String labelText = unitLabels.get(unitKey);
            Integer val = unitMultipliers.get(unitKey);
            Button b = new Button(labelText);

            if (unitKey.equals("sack")) {
                b.setStyle("-fx-background-color: #2196F3; -fx-text-fill: white;");
            } else {
                Label valLabel = new Label("*" + val);
                valLabel.setStyle("-fx-text-fill: red; -fx-font-weight: bold; -fx-padding: 0 0 0 5;");
                // Note: valLabel is redundant if labelText already has *X, but keeping for
                // styling
                // Actually, let's just use the mobile labels directly for unity.
                b.setGraphic(null);
            }

            b.getStyleClass().add("pill-quick");
            b.setOnAction(evt -> {
                selectQuickButton(b, unitButtonsMap);
                appendUnit(unitKey);
            });

            // STORE REFERENCE and add to box
            unitButtonsMap.put(unitKey, b);
            unitButtonsBox.getChildren().add(b);
        }
    }

    private void filterUnitButtons(String size) {
        if (size == null || size.isEmpty())
            return;
        String s = size.toLowerCase();

        // First, hide all buttons
        unitButtonsMap.values().forEach(btn -> {
            btn.setVisible(false);
            btn.setManaged(false);
        });

        // 2. APPLY STRICT LOGIC
        if (s.contains("kg")) {
            double numericValue = extractNumericValue(size);
            if (numericValue <= 9.9) {
                showButton("pcs");
                showButton("half doz");
                showButton("box*10");
                showButton("box*12");
                showButton("box*20");
                showButton("box*24");
                showButton("crate");
                showButton("box*72");
            } else {
                showButton("sack");
            }
        } else if (s.contains("ml") || s.contains("l") || s.contains("g") || s.contains("inch")) {
            // VOLUME-BASED or measurement-based
            showButton("pcs");
            showButton("half doz");
            showButton("box*10");
            showButton("box*12");
            showButton("box*20");
            showButton("box*24");
            showButton("crate");
            showButton("box*72");
        } else {
            // DEFAULT/OTHER: Show pcs and standard units
            showButton("pcs");
            showButton("box*12");
        }
    }

    /** Marks btn as selected (green fill) and deselects all others in the group. */
    private void selectQuickButton(Button btn, java.util.Map<String, Button> group) {
        for (Button b : group.values()) {
            b.getStyleClass().remove("pill-quick-selected");
            if (!b.getStyleClass().contains("pill-quick"))
                b.getStyleClass().add("pill-quick");
        }
        btn.getStyleClass().remove("pill-quick");
        if (!btn.getStyleClass().contains("pill-quick-selected"))
            btn.getStyleClass().add("pill-quick-selected");
    }

    private void showButton(String key) {
        Button b = unitButtonsMap.get(key);
        if (b != null) {
            b.setVisible(true);
            b.setManaged(true);
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

        String numberPart = extractBaseQuantity(unitField.getText().trim());

        // Smart replace: Keep number, update unit
        unitField.setText(numberPart + " " + unit);

        // 1. Get the price of 1 base unit (e.g., 1kg of Posho = 4,444)
        double basePrice = dataManager.getDbHelper().getExistingPrice(selectedItem, selectedSize);

        if (basePrice > 0) {
            // 2. Get the multiplier (e.g., Sack = 45)
            double multiplier = dataManager.getDbHelper().getUnitMultiplier(unit, selectedSize, unit);

            // 3. Fill the price field with the price of ONE UNIT (e.g., 1 Sack = 200,000)
            double unitPrice = basePrice * multiplier;
            priceField.setText(String.format("%.0f", unitPrice));
            unitErrorLabel.setVisible(false);
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

        // HARD BLOCK: If the current text matches an item in the dropdown list, STOP.
        if (qtyComboBox.getItems().contains(currentQty)) {
            showAlert("This size is already recorded in the database. You cannot modify it using quick buttons.");
            return;
        }

        if (unit.equalsIgnoreCase("None")) {
            qtyComboBox.getEditor().setText("None");
            handleQtySelection();
            return;
        }

        // Logic for appending units...

        // CHECK IF IT HAS NUMBERS
        boolean hasNumbers = currentQty.matches(".*\\d.*");

        if (!hasNumbers) {
            // Case 1: Empty or just text -> Set Unit & Move Cursor to START
            // This allows User to Click 'kg' -> Type '5' -> Result '5kg'
            qtyComboBox.getEditor().setText(unit);
            javafx.application.Platform.runLater(() -> {
                qtyComboBox.getEditor().positionCaret(0);
                qtyComboBox.requestFocus();
            });
        } else {
            // Case 2: Already has number -> Append unit to end
            // e.g. "5" -> "5kg"
            if (currentQty.endsWith("kg") || currentQty.endsWith("ml") || currentQty.endsWith("l")) {
                qtyComboBox.getEditor().setText(currentQty.replaceAll("(g|kg|ml|l)$", "") + unit);
            } else {
                qtyComboBox.getEditor().setText(currentQty + unit);
            }
            javafx.application.Platform.runLater(() -> {
                qtyComboBox.getEditor().positionCaret(qtyComboBox.getEditor().getText().length());
                qtyComboBox.requestFocus();
            });
        }
    }

    private void onAdd() {
        supplierNameComboBox.getEditor().getText().trim();
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

        // BLOCK DUPLICATE ITEMS IN PREVIEW LIST
        for (StockItem existing : items) {
            if (existing.getItems().equalsIgnoreCase(itemName) && existing.getQty().equalsIgnoreCase(qtyRaw)) {
                showAlert("You already have '" + itemName + " " + qtyRaw + "' in the preview list! Please save or delete it first before adding a different unit to avoid average-cost calculation conflicts.");
                return;
            }
        }

        // CHECK FOR NEW QTY: Check if the typed size exists in the dropdown list
        boolean sizeExists = qtyComboBox.getItems().contains(qtyRaw);

        if (!sizeExists && !qtyRaw.isEmpty()) {
            String content = "This size is not in your current stock records for " + itemName + ".\n\n" +
                    "Are you sure you want to add this as a NEW product category?";

            // If they don't click OK, stop the process
            if (!com.meto.inventory.utils.DialogHelper.showConfirm("New Quantity Size Detected", "New Size: " + qtyRaw,
                    content)) {
                return;
            }
        }
        // inside onAdd()
        if (!itemsComboBox.getItems().contains(itemName)) {
            itemsComboBox.getItems().add(itemName);
            FXCollections.sort(itemsComboBox.getItems()); // Keep it alphabetical
        }

        // 2. Define allowed patterns
        // Matches numbers followed by g, kg, ml, l or inch (e.g., 500ml, 1.5l, 10inch)
        // OR "None"
        String sizePattern = ".*\\d+(g|kg|ml|l|inch)$|^none$";
        // Added specialized box units to the regex pattern
        // Update the regex to accept 'pc' (without the s)
        String countPattern = ".*\\d+.*(pc|pcs|doz|carton|box|sack|dozen|crate|box\\*10|box\\*12|box\\*20|box\\*24|box\\*72).*";

        boolean hasError = false;

        if (itemName.isEmpty()) {
            itemErrorLabel.setVisible(true);
            itemErrorLabel.setManaged(true);
            hasError = true;
        }
        // 3. Validate QTY (Size)
        if (!qtyRaw.matches(sizePattern)) {
            qtyErrorLabel.setText("* Missing size unit (e.g., 500ml, 1kg, 12inch)");
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

        if (hasError)
            return;

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
        // This assumes the price you type in the box is the price for the unit shown
        // (pc, sack, box, etc.)
        double totalAmount = count * inputPrice;

        String amountStr = String.format("%,.2f", totalAmount);
        String priceStr = String.format("%,.2f", inputPrice);

        StockItem si = new StockItem(itemName, qtyRaw, unitText, priceStr, amountStr);
        items.add(si);

        // clear fields — reset values to null FIRST so re-selecting the same item works
        itemsComboBox.setValue(null);
        itemsComboBox.getEditor().clear();
        qtyComboBox.setValue(null);
        qtyComboBox.getEditor().clear();
        unitField.clear();
        priceField.clear();
        priceField.setEditable(true);
        priceField.setMouseTransparent(false);
        priceField.setStyle("");
    }

    @FXML
    private void onSave() {
        String supplier = supplierNameComboBox.getEditor().getText().trim();
        if (supplier.isEmpty()) {
            supplierErrorLabel.setVisible(true);
            supplierErrorLabel.setManaged(true);
            return;
        }

        if (items.isEmpty()) {
            showAlert("Please Fill in item to continue!");
            return;
        }

        java.util.Iterator<StockItem> iterator = items.iterator();
        while (iterator.hasNext()) {
            StockItem s = iterator.next();
            String item = s.getItems();
            String qty = s.getQty();
            String unit = s.getUnit();
            double price = Double.parseDouble(s.getPrice().replaceAll("[^0-9.]", ""));

            if (dataManager.getDbHelper().itemExists(item, qty)) {
                // 1. Try to merge normally (forceSave = false)
                boolean success = dataManager.getDbHelper().mergeStock(item, qty, unit, price, supplier, false);

                if (!success) {
                    // 2. If it fails, show the Alert
                    String content = "The price for " + unit
                            + " makes the unit price very different from current stock.\n\n" +
                            "Do you want to save this anyway?";

                    if (com.meto.inventory.utils.DialogHelper.showConfirm("Price Variance Warning",
                            "Price mismatch for " + item + " (" + qty + ")", content)) {
                        // 3. If user says OK, merge with forceSave = true
                        dataManager.getDbHelper().mergeStock(item, qty, unit, price, supplier, true);
                    } else {
                        break; // Stop processing further items so user can fix the price
                    }
                }
            } else {
                dataManager.getDbHelper().addStock(supplier, item, qty, unit, price, LocalDate.now().toString());
            }

            // Parse Total Amount from the StockItem
            double totalAmount = 0.0;
            try {
                totalAmount = Double.parseDouble(s.getAmount().replaceAll("[^0-9.]", ""));
            } catch (Exception e) {}
            
            dataManager.getDbHelper().addSaleWithProfit(supplier, item, qty, unit, price, totalAmount, "NEW STOCK", false, null);
            
            // Item successfully processed, remove it from the list
            iterator.remove();
        }

        if (items.isEmpty()) {
            showAlert("Stock saved successfully!");
            supplierNameComboBox.getEditor().clear();
            supplierNameComboBox.setValue(null);
        } else {
            // Some items were left in the list (because of cancellation)
            showAlert("Save process aborted. Please fix the items remaining in the preview list.");
        }
        
        dataManager.notifyDataChanged();
        refreshDropdowns();
    }

    @FXML
    private void onClear() {
        supplierNameComboBox.getEditor().clear();
        supplierNameComboBox.setValue(null);
        itemsComboBox.getEditor().clear();
        itemsComboBox.setValue(null);
        qtyComboBox.getEditor().clear();
        qtyComboBox.setValue(null);
        unitField.clear();
        priceField.clear();
        priceField.setEditable(true);
        priceField.setMouseTransparent(false);
        priceField.setStyle("");
        items.clear();
        setFlowLevel(0);

        // Reset error labels
        supplierErrorLabel.setVisible(false);
        itemErrorLabel.setVisible(false);
        qtyErrorLabel.setVisible(false);
        unitErrorLabel.setVisible(false);
        priceErrorLabel.setVisible(false);

        // Reset button states
        updateQtyButtonsLockState(false);
    }

    private void showAlert(String text) {
        com.meto.inventory.utils.DialogHelper.showAlert(text);
    }

    @Override
    public void onDataChanged() {
        javafx.application.Platform.runLater(this::refreshDropdowns);
    }
}