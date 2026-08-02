package com.meto.inventory.controllers;

import com.meto.inventory.DataManager;
import com.meto.inventory.models.HistoryItem;
import com.meto.inventory.utils.*;
import javafx.collections.ObservableList;
import javafx.fxml.FXML;
import javafx.geometry.Pos;
import javafx.scene.Node;
import javafx.scene.control.*;
import javafx.scene.layout.HBox;
import javafx.scene.layout.Priority;
import javafx.scene.layout.Region;
import javafx.scene.layout.VBox;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class HistoryController implements DataManager.DataChangeListener {

    @FXML
    private ComboBox<String> historyFilterCombo;
    @FXML
    private ComboBox<String> periodFilterCombo;
    @FXML
    private TextField searchField;
    @FXML
    private DatePicker datePicker;
    @FXML
    private Button clearDateBtn;
    @FXML
    private Button refreshBtn;
    @FXML
    private ScrollPane historyScrollPane;
    @FXML
    private VBox historyListContainer;

    // Summary metric labels
    @FXML
    private Label totalRecordsLabel;
    @FXML
    private Label salesVolumeLabel;
    @FXML
    private Label stockCountLabel;
    @FXML
    private Label unpaidDebtsLabel;

    // Category Quick Filter Pills
    @FXML
    private Button btnFilterAll;
    @FXML
    private Button btnFilterStock;
    @FXML
    private Button btnFilterRetail;
    @FXML
    private Button btnFilterWholesale;
    @FXML
    private Button btnFilterDebts;

    private String activeTypeFilter = "ALL";
    private final DataManager dataManager = DataManager.getInstance();
    private ObservableList<HistoryItem> masterHistoryList;

    @FXML
    public void initialize() {
        dataManager.addDataChangeListener(this);

        if (historyFilterCombo != null) {
            if (historyFilterCombo.getItems().isEmpty()) {
                historyFilterCombo.getItems().addAll("ALL", "NEW STOCK", "WHOLESALE", "RETAIL", "DEBTS");
            }
            historyFilterCombo.setValue("ALL");
        }

        if (periodFilterCombo != null) {
            periodFilterCombo.getItems().addAll("All Periods", "Today", "Yesterday", "Earlier");
            periodFilterCombo.setValue("All Periods");
        }

        setupCategoryPills();
        loadHistory();

        if (historyFilterCombo != null) {
            historyFilterCombo.setOnAction(e -> applyFilters());
        }
        if (periodFilterCombo != null) {
            periodFilterCombo.setOnAction(e -> applyFilters());
        }
        if (searchField != null) {
            searchField.textProperty().addListener((obs, oldVal, newVal) -> applyFilters());
        }
        if (datePicker != null) {
            datePicker.valueProperty().addListener((obs, oldVal, newVal) -> applyFilters());
        }
        if (clearDateBtn != null) {
            clearDateBtn.setOnAction(e -> {
                if (datePicker != null) datePicker.setValue(null);
            });
        }
        if (refreshBtn != null) {
            refreshBtn.setOnAction(e -> loadHistory());
        }
    }

    private void setupCategoryPills() {
        if (btnFilterAll != null) btnFilterAll.setOnAction(e -> selectCategoryPill(btnFilterAll, "ALL"));
        if (btnFilterStock != null) btnFilterStock.setOnAction(e -> selectCategoryPill(btnFilterStock, "NEW STOCK"));
        if (btnFilterRetail != null) btnFilterRetail.setOnAction(e -> selectCategoryPill(btnFilterRetail, "RETAIL"));
        if (btnFilterWholesale != null) btnFilterWholesale.setOnAction(e -> selectCategoryPill(btnFilterWholesale, "WHOLESALE"));
        if (btnFilterDebts != null) btnFilterDebts.setOnAction(e -> selectCategoryPill(btnFilterDebts, "DEBTS"));
    }

    private void selectCategoryPill(Button selectedBtn, String filterValue) {
        List<Button> pills = Arrays.asList(btnFilterAll, btnFilterStock, btnFilterRetail, btnFilterWholesale, btnFilterDebts);
        for (Button btn : pills) {
            if (btn != null) {
                btn.getStyleClass().removeAll("pill-quick-selected", "pill-quick");
                if (btn == selectedBtn) {
                    btn.getStyleClass().add("pill-quick-selected");
                } else {
                    btn.getStyleClass().add("pill-quick");
                }
            }
        }
        activeTypeFilter = filterValue;
        if (historyFilterCombo != null) {
            historyFilterCombo.setValue(filterValue);
        }
        applyFilters();
    }

    private Node createEmptyStateNode() {
        VBox emptyBox = new VBox(10);
        emptyBox.getStyleClass().add("empty-state-box");

        Label title = new Label("No History Records Found");
        title.getStyleClass().add("empty-state-title");

        Label sub = new Label("Try adjusting your search query, date selection, or category pills.");
        sub.getStyleClass().add("empty-state-sub");

        Button resetBtn = new Button("Reset Filters");
        resetBtn.getStyleClass().add("pill");
        resetBtn.setOnAction(e -> resetAllFilters());

        emptyBox.getChildren().addAll(title, sub, resetBtn);
        return emptyBox;
    }

    private void resetAllFilters() {
        if (searchField != null) searchField.setText("");
        if (datePicker != null) datePicker.setValue(null);
        if (periodFilterCombo != null) periodFilterCombo.setValue("All Periods");
        if (btnFilterAll != null) selectCategoryPill(btnFilterAll, "ALL");
    }

    @Override
    public void onDataChanged() {
        loadHistory();
    }

    private void loadHistory() {
        String filter = activeTypeFilter;
        if ("ALL".equals(filter)) {
            filter = null;
        }
        masterHistoryList = dataManager.getDbHelper().getHistory(filter);
        applyFilters();
    }

    private void applyFilters() {
        if (masterHistoryList == null || historyListContainer == null)
            return;

        String typeFilter = historyFilterCombo != null && historyFilterCombo.getValue() != null ? historyFilterCombo.getValue() : activeTypeFilter;
        String periodFilter = periodFilterCombo != null ? periodFilterCombo.getValue() : "All Periods";
        String searchText = searchField == null || searchField.getText() == null ? "" : searchField.getText().toLowerCase().trim();
        java.time.LocalDate selectedDate = datePicker != null ? datePicker.getValue() : null;

        List<HistoryItem> filteredList = new ArrayList<>();

        for (HistoryItem item : masterHistoryList) {
            // 0. Period Filter
            if (periodFilter != null && !"All Periods".equals(periodFilter)) {
                if (!item.getPeriodGroup().equalsIgnoreCase(periodFilter)) {
                    continue;
                }
            }

            // 1. Type Filter
            if (typeFilter != null && !"ALL".equals(typeFilter)) {
                if ("DEBTS".equals(typeFilter)) {
                    if (!item.isIsDebt()) continue;
                } else {
                    if (!item.getTypeUnit().equalsIgnoreCase(typeFilter))
                        continue;
                }
            }

            // 2. Search Filter
            if (!searchText.isEmpty()) {
                boolean matchesItem = item.getItem() != null && item.getItem().toLowerCase().contains(searchText);
                boolean matchesCustomer = item.getName() != null && item.getName().toLowerCase().contains(searchText);
                if (!matchesItem && !matchesCustomer)
                    continue;
            }

            // 3. Date Filter
            if (selectedDate != null) {
                String itemDateStr = item.getDate();
                if (itemDateStr != null) {
                    try {
                        java.time.LocalDate itemDate;
                        if (itemDateStr.contains("T")) {
                            itemDate = java.time.OffsetDateTime.parse(itemDateStr).toLocalDate();
                        } else if (itemDateStr.contains(" ")) {
                            itemDate = java.time.LocalDate.parse(itemDateStr.split(" ")[0]);
                        } else {
                            itemDate = java.time.LocalDate.parse(itemDateStr);
                        }
                        if (!itemDate.equals(selectedDate))
                            continue;
                    } catch (Exception e) {
                        continue;
                    }
                } else {
                    continue;
                }
            }

            filteredList.add(item);
        }

        renderTransactionCards(filteredList);
        updateMetrics(filteredList);
    }

    private void renderTransactionCards(List<HistoryItem> items) {
        historyListContainer.getChildren().clear();

        if (items.isEmpty()) {
            historyListContainer.getChildren().add(createEmptyStateNode());
            return;
        }

        for (HistoryItem item : items) {
            historyListContainer.getChildren().add(createTransactionRowCard(item));
        }
    }

    /**
     * Builds a clean, self-sizing HBox row card for a single transaction.
     */
    private HBox createTransactionRowCard(HistoryItem item) {
        HBox rowCard = new HBox(12);
        rowCard.setAlignment(Pos.CENTER_LEFT);
        rowCard.getStyleClass().add("history-row-card");

        // Set left accent indicator class
        String type = item.getTypeUnit();
        if (item.isIsDebt() && !item.isIsPaid()) {
            rowCard.getStyleClass().add("card-accent-debt");
        } else if (type != null && type.equalsIgnoreCase("NEW STOCK")) {
            rowCard.getStyleClass().add("card-accent-stock");
        } else if (type != null && type.equalsIgnoreCase("WHOLESALE")) {
            rowCard.getStyleClass().add("card-accent-wholesale");
        } else {
            rowCard.getStyleClass().add("card-accent-retail");
        }

        // 1. Customer / Supplier Block
        VBox nameBox = new VBox(2);
        nameBox.setPrefWidth(170);
        nameBox.setAlignment(Pos.CENTER_LEFT);

        Label nameLabel = new Label(item.getName() == null ? "Walk-in Customer" : item.getName());
        nameLabel.setStyle("-fx-font-weight: 800; -fx-text-fill: #0F172A; -fx-font-size: 13px;");

        String subTagStr = (type != null && type.equalsIgnoreCase("NEW STOCK")) ? "Inventory Restock" : "Transaction";
        if (item.getId() > 0) {
            subTagStr += " #" + item.getId();
        }
        Label subLabel = new Label(subTagStr);
        subLabel.setStyle("-fx-font-size: 11px; -fx-text-fill: #64748B; -fx-font-weight: 500;");

        nameBox.getChildren().addAll(nameLabel, subLabel);

        // 2. Structured Item Details Block
        VBox itemContainer = new VBox(4);
        HBox.setHgrow(itemContainer, Priority.ALWAYS);
        itemContainer.setMaxWidth(Double.MAX_VALUE);

        String rawItemStr = item.getItem();
        if (rawItemStr != null && !rawItemStr.trim().isEmpty()) {
            String[] lines = rawItemStr.split("\n");
            for (String line : lines) {
                String trimmed = line.trim();
                if (!trimmed.isEmpty()) {
                    itemContainer.getChildren().add(buildItemLineCard(trimmed));
                }
            }
        }

        // 3. Type Badge Block
        VBox typeBox = new VBox();
        typeBox.setPrefWidth(95);
        typeBox.setAlignment(Pos.CENTER);

        Label typeBadge = new Label(type == null ? "RETAIL" : type);
        typeBadge.getStyleClass().add("badge");
        if (item.isIsDebt() && !item.isIsPaid()) {
            typeBadge.setText("DEBT");
            typeBadge.getStyleClass().add("badge-debt");
        } else if (type != null && type.equalsIgnoreCase("NEW STOCK")) {
            typeBadge.getStyleClass().add("badge-stock");
        } else if (type != null && type.equalsIgnoreCase("WHOLESALE")) {
            typeBadge.getStyleClass().add("badge-wholesale");
        } else {
            typeBadge.getStyleClass().add("badge-retail");
        }
        typeBox.getChildren().add(typeBadge);

        // 4. Period Badge Block
        VBox periodBox = new VBox();
        periodBox.setPrefWidth(85);
        periodBox.setAlignment(Pos.CENTER);

        String period = item.getPeriodGroup();
        Label periodBadge = new Label(period);
        periodBadge.getStyleClass().add("badge");
        if ("Today".equals(period)) {
            periodBadge.getStyleClass().add("badge-period-today");
        } else if ("Yesterday".equals(period)) {
            periodBadge.getStyleClass().add("badge-period-yesterday");
        } else {
            periodBadge.getStyleClass().add("badge-period-earlier");
        }
        periodBox.getChildren().add(periodBadge);

        // 5. Total Amount Block
        VBox amountBox = new VBox();
        amountBox.setPrefWidth(130);
        amountBox.setAlignment(Pos.CENTER_RIGHT);

        Label amountLabel = new Label("UGX " + (item.getAmount() == null ? "0" : item.getAmount()));
        amountLabel.getStyleClass().add("amount-vibrant");
        amountBox.getChildren().add(amountLabel);

        // 6. Date & Time Block
        VBox dateBox = new VBox();
        dateBox.setPrefWidth(110);
        dateBox.setAlignment(Pos.CENTER_RIGHT);

        Label dateLabel = new Label(item.getDate() == null ? "" : item.getDate());
        dateLabel.setStyle("-fx-font-size: 12px; -fx-text-fill: #475569; -fx-font-weight: 500;");
        dateBox.getChildren().add(dateLabel);

        // 7. Actions Block
        VBox actionBox = new VBox();
        actionBox.setPrefWidth(80);
        actionBox.setAlignment(Pos.CENTER);

        if (item.isIsDebt() && !item.isIsPaid()) {
            Button settleBtn = new Button("Settle");
            settleBtn.getStyleClass().add("pill");
            settleBtn.setStyle("-fx-font-size: 11px; -fx-padding: 3 8; -fx-background-color: #EF4444; -fx-text-fill: white; -fx-font-weight: bold;");
            settleBtn.setOnAction(e -> showSettleDebtDialog(item));
            actionBox.getChildren().add(settleBtn);
        } else if (type != null && !type.equalsIgnoreCase("NEW STOCK")) {
            Button printBtn = new Button("Print");
            printBtn.getStyleClass().add("btn-print");
            printBtn.setOnAction(e -> handlePrintReceipt(item));
            actionBox.getChildren().add(printBtn);
        }

        rowCard.getChildren().addAll(nameBox, itemContainer, typeBox, periodBox, amountBox, dateBox, actionBox);
        return rowCard;
    }

    /**
     * Builds a structured line-item component card for each item in a transaction.
     * Parses raw strings like: "2 Pcs Sugar @ 5000 = 10000"
     */
    private Node buildItemLineCard(String lineText) {
        HBox lineBox = new HBox(8);
        lineBox.setAlignment(Pos.CENTER_LEFT);
        lineBox.getStyleClass().add("item-line-box");

        String text = lineText.trim();
        if (text.contains("@") && text.contains("=")) {
            try {
                int atIdx = text.indexOf('@');
                int eqIdx = text.indexOf('=', atIdx);

                String leftPart = text.substring(0, atIdx).trim();
                String middlePart = text.substring(atIdx + 1, eqIdx).trim();
                String rightPart = text.substring(eqIdx + 1).trim();

                String dateSuffix = "";
                if (rightPart.contains("(") && rightPart.contains(")")) {
                    int pIdx = rightPart.indexOf('(');
                    dateSuffix = " " + rightPart.substring(pIdx).trim();
                    rightPart = rightPart.substring(0, pIdx).trim();
                }

                String qtyTag = "";
                String itemName = leftPart;

                Matcher m = Pattern.compile("^(\\d+(?:\\.\\d+)?\\s*[^\\s]+)\\s+(.+)$").matcher(leftPart);
                if (m.matches()) {
                    qtyTag = m.group(1).trim();
                    itemName = m.group(2).trim();
                }

                if (!qtyTag.isEmpty()) {
                    Label qtyLabel = new Label(qtyTag);
                    qtyLabel.getStyleClass().add("item-qty-badge");
                    lineBox.getChildren().add(qtyLabel);
                }

                Label nameLabel = new Label(itemName);
                nameLabel.getStyleClass().add("item-name-bold");
                nameLabel.setWrapText(true);
                HBox.setHgrow(nameLabel, Priority.ALWAYS);
                lineBox.getChildren().add(nameLabel);

                double unitPriceVal = Double.parseDouble(middlePart.replaceAll("[^0-9.]", ""));
                double amountVal = Double.parseDouble(rightPart.replaceAll("[^0-9.]", ""));

                Label priceLabel = new Label(String.format("@ UGX %,.0f", unitPriceVal));
                priceLabel.getStyleClass().add("item-price-muted");

                Label subtotalLabel = new Label(String.format("UGX %,.0f%s", amountVal, dateSuffix));
                subtotalLabel.getStyleClass().add("item-subtotal-bold");

                VBox priceContainer = new VBox(0);
                priceContainer.setAlignment(Pos.CENTER_RIGHT);
                priceContainer.getChildren().addAll(subtotalLabel, priceLabel);

                lineBox.getChildren().add(priceContainer);
                return lineBox;
            } catch (Exception e) {
                // Fallthrough on parsing exception
            }
        }

        // Fallback for non-standard item strings
        Label fallbackLabel = new Label(text);
        fallbackLabel.getStyleClass().add("item-name-bold");
        fallbackLabel.setWrapText(true);
        lineBox.getChildren().add(fallbackLabel);
        return lineBox;
    }

    private void updateMetrics(List<HistoryItem> list) {
        int totalCount = list.size();
        double salesVolume = 0;
        int stockLogs = 0;
        int unpaidDebts = 0;

        for (HistoryItem item : list) {
            String type = item.getTypeUnit();
            if (type != null && item.getTypeUnit().equalsIgnoreCase("NEW STOCK")) {
                stockLogs++;
            } else {
                try {
                    String amtStr = item.getAmount();
                    if (amtStr != null) {
                        double amt = Double.parseDouble(amtStr.replaceAll("[^0-9.]", ""));
                        salesVolume += amt;
                    }
                } catch (Exception ignored) {}
            }

            if (item.isIsDebt() && !item.isIsPaid()) {
                unpaidDebts++;
            }
        }

        if (totalRecordsLabel != null) totalRecordsLabel.setText(String.valueOf(totalCount));
        if (salesVolumeLabel != null) salesVolumeLabel.setText(String.format("UGX %,.0f", salesVolume));
        if (stockCountLabel != null) stockCountLabel.setText(String.valueOf(stockLogs));
        if (unpaidDebtsLabel != null) unpaidDebtsLabel.setText(String.valueOf(unpaidDebts));
    }

    private void showSettleDebtDialog(HistoryItem item) {
        Dialog<String> dialog = new Dialog<>();
        dialog.setTitle("Settle Customer Debt");
        dialog.setGraphic(null);
        dialog.setHeaderText(null);

        DialogPane dialogPane = dialog.getDialogPane();
        dialogPane.getStyleClass().add("settle-dialog-pane");

        try {
            String stylesheet = getClass().getResource("/com/meto/inventory/views/styles/style.css").toExternalForm();
            dialogPane.getStylesheets().add(stylesheet);
        } catch (Exception ignored) {}

        String amountStrVal = item.getAmount() == null ? "0" : item.getAmount().replaceAll("[^0-9.]", "");
        String paidStrVal = item.getPaidAmount() == null ? "0" : item.getPaidAmount().replaceAll("[^0-9.]", "");

        double total = amountStrVal.isEmpty() ? 0 : Double.parseDouble(amountStrVal);
        double paid = paidStrVal.isEmpty() ? 0 : Double.parseDouble(paidStrVal);
        double remaining = Math.max(0, total - paid);

        VBox mainLayout = new VBox(14);
        mainLayout.setPrefWidth(430);

        // Header Block
        VBox headerBox = new VBox(3);
        Label titleLabel = new Label("Settle Customer Debt");
        titleLabel.setStyle("-fx-font-size: 18px; -fx-font-weight: 900; -fx-text-fill: #0F172A;");
        Label customerLabel = new Label("Customer: " + (item.getName() == null ? "Walk-in Customer" : item.getName()));
        customerLabel.setStyle("-fx-font-size: 13px; -fx-font-weight: 700; -fx-text-fill: #2563EB;");
        headerBox.getChildren().addAll(titleLabel, customerLabel);

        // 1. Structured Items & Financial Summary Card
        VBox summaryCard = new VBox(8);
        summaryCard.getStyleClass().add("settle-summary-card");

        Label itemsTitle = new Label("ITEM BREAKDOWN");
        itemsTitle.setStyle("-fx-font-size: 10px; -fx-font-weight: 800; -fx-text-fill: #64748B;");
        summaryCard.getChildren().add(itemsTitle);

        String rawItemStr = item.getItem();
        if (rawItemStr != null && !rawItemStr.trim().isEmpty()) {
            for (String line : rawItemStr.split("\n")) {
                if (!line.trim().isEmpty()) {
                    summaryCard.getChildren().add(buildItemLineCard(line.trim()));
                }
            }
        }

        // Financial Grid (Total & Already Paid)
        HBox totalsGrid = new HBox(12);
        totalsGrid.setAlignment(Pos.CENTER_LEFT);

        VBox totalBox = new VBox(2);
        Label totalTitle = new Label("TOTAL AMOUNT");
        totalTitle.setStyle("-fx-font-size: 10px; -fx-font-weight: 800; -fx-text-fill: #64748B;");
        Label totalVal = new Label(String.format("UGX %,.0f", total));
        totalVal.setStyle("-fx-font-size: 13px; -fx-font-weight: 700; -fx-text-fill: #0F172A;");
        totalBox.getChildren().addAll(totalTitle, totalVal);

        VBox paidBox = new VBox(2);
        Label paidTitle = new Label("ALREADY PAID");
        paidTitle.setStyle("-fx-font-size: 10px; -fx-font-weight: 800; -fx-text-fill: #64748B;");
        Label paidVal = new Label(String.format("UGX %,.0f", paid));
        paidVal.setStyle("-fx-font-size: 13px; -fx-font-weight: 700; -fx-text-fill: #059669;");
        paidBox.getChildren().addAll(paidTitle, paidVal);

        Region spacer = new Region();
        HBox.setHgrow(spacer, Priority.ALWAYS);
        totalsGrid.getChildren().addAll(totalBox, spacer, paidBox);
        summaryCard.getChildren().addAll(new Separator(), totalsGrid);

        // 2. High-Contrast REMAINING BALANCE Focal Banner
        VBox focalBanner = new VBox(4);
        focalBanner.getStyleClass().add("settle-focal-banner");
        focalBanner.setAlignment(Pos.CENTER);

        Label focalTitle = new Label("REMAINING BALANCE TO COLLECT");
        focalTitle.getStyleClass().add("settle-focal-title");

        Label focalVal = new Label(String.format("UGX %,.0f", remaining));
        focalVal.getStyleClass().add("settle-focal-val");

        focalBanner.getChildren().addAll(focalTitle, focalVal);

        // 3. Input Field with Helper & Quick Fill Button
        VBox inputSection = new VBox(6);
        Label inputLabel = new Label("Enter Amount Paid Today (UGX)");
        inputLabel.setStyle("-fx-font-size: 12px; -fx-font-weight: 800; -fx-text-fill: #0F172A;");

        HBox inputRow = new HBox(8);
        inputRow.setAlignment(Pos.CENTER_LEFT);

        TextField amountInput = new TextField(String.format("%.0f", remaining));
        amountInput.setPromptText("Enter amount...");
        amountInput.setStyle("-fx-font-size: 14px; -fx-font-weight: bold; -fx-padding: 8 10; -fx-border-color: #CBD5E1; -fx-border-radius: 6;");
        HBox.setHgrow(amountInput, Priority.ALWAYS);

        Button fullBtn = new Button("Settle Full");
        fullBtn.getStyleClass().add("pill");
        fullBtn.setStyle("-fx-font-size: 11px; -fx-font-weight: 700; -fx-padding: 8 12;");
        final double remVal = remaining;
        fullBtn.setOnAction(e -> amountInput.setText(String.format("%.0f", remVal)));

        inputRow.getChildren().addAll(amountInput, fullBtn);
        inputSection.getChildren().addAll(inputLabel, inputRow);

        mainLayout.getChildren().addAll(headerBox, summaryCard, focalBanner, inputSection);
        dialogPane.setContent(mainLayout);

        // Custom Action Buttons
        ButtonType confirmButtonType = new ButtonType("Confirm Payment", ButtonBar.ButtonData.OK_DONE);
        ButtonType cancelButtonType = new ButtonType("Cancel", ButtonBar.ButtonData.CANCEL_CLOSE);

        dialogPane.getButtonTypes().addAll(cancelButtonType, confirmButtonType);

        Button confirmBtn = (Button) dialogPane.lookupButton(confirmButtonType);
        if (confirmBtn != null) {
            confirmBtn.getStyleClass().add("btn-confirm-payment");
        }

        dialog.setResultConverter(dialogButton -> {
            if (dialogButton == confirmButtonType) {
                return amountInput.getText();
            }
            return null;
        });

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

    public void destroy() {
        dataManager.removeDataChangeListener(this);
    }
}