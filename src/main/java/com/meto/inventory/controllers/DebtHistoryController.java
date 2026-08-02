package com.meto.inventory.controllers;

import com.meto.inventory.DataManager;
import com.meto.inventory.models.DebtPaymentLog;
import com.meto.inventory.models.HistoryItem;
import com.meto.inventory.utils.*;

import javafx.fxml.FXML;
import javafx.geometry.Pos;
import javafx.scene.Node;
import javafx.scene.control.*;
import javafx.scene.layout.HBox;
import javafx.scene.layout.Priority;
import javafx.scene.layout.Region;
import javafx.scene.layout.VBox;

import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public class DebtHistoryController implements DataManager.DataChangeListener {

    @FXML
    private Label totalDebtLabel, debtorCountLabel, collectedTodayLabel;
    @FXML
    private VBox unsettledListContainer;
    @FXML
    private VBox paymentLogsListContainer;
    @FXML
    private VBox settledListContainer;
    @FXML
    private Button refreshBtn, notificationsBtn;

    private DataManager dataManager;

    @FXML
    public void initialize() {
        dataManager = DataManager.getInstance();
        dataManager.addDataChangeListener(this);

        loadData();

        if (refreshBtn != null) {
            refreshBtn.setOnAction(e -> loadData());
        }

        if (notificationsBtn != null) {
            notificationsBtn.setOnAction(e -> {
                if (MainController.getInstance() != null) {
                    MainController.getInstance().openNotificationsView(() -> MainController.getInstance().navigateTo("debthistory"));
                }
            });
        }
    }

    private void loadData() {
        // Summary Metrics
        double totalDebt = dataManager.getDbHelper().getTotalOutstandingDebt();
        int debtorCount = dataManager.getDbHelper().getDebtorCount();
        double collectedToday = dataManager.getDbHelper().getDebtCollectedToday();

        if (totalDebtLabel != null) totalDebtLabel.setText(String.format("UGX %,.0f", totalDebt));
        if (debtorCountLabel != null) debtorCountLabel.setText(String.valueOf(debtorCount));
        if (collectedTodayLabel != null) collectedTodayLabel.setText(String.format("UGX %,.0f", collectedToday));

        // Render Card Lists
        if (unsettledListContainer != null) {
            renderUnsettledDebts(dataManager.getDbHelper().getHistory("DEBTS"));
        }
        if (paymentLogsListContainer != null) {
            renderPaymentLogs(dataManager.getDbHelper().getRecentDebtPayments());
        }
        if (settledListContainer != null) {
            renderSettledDebts(dataManager.getDbHelper().getSettledDebts());
        }
    }

    @Override
    public void onDataChanged() {
        javafx.application.Platform.runLater(this::loadData);
    }

    // ==========================================
    // 1. ACTIVE DEBTS TAB RENDERING
    // ==========================================
    private void renderUnsettledDebts(List<HistoryItem> items) {
        unsettledListContainer.getChildren().clear();
        if (items == null || items.isEmpty()) {
            unsettledListContainer.getChildren().add(createEmptyStateNode("No Active Debts", "All customer accounts are currently fully settled."));
            return;
        }

        for (HistoryItem item : items) {
            unsettledListContainer.getChildren().add(createUnsettledRowCard(item));
        }
    }

    private HBox createUnsettledRowCard(HistoryItem item) {
        HBox rowCard = new HBox(12);
        rowCard.setAlignment(Pos.CENTER_LEFT);
        rowCard.getStyleClass().addAll("history-row-card", "card-accent-debt");

        // 1. Customer Name Block
        VBox nameBox = new VBox(2);
        nameBox.setPrefWidth(160);
        nameBox.setAlignment(Pos.CENTER_LEFT);

        Label nameLabel = new Label(item.getName() == null ? "Walk-in Customer" : item.getName());
        nameLabel.setStyle("-fx-font-weight: 800; -fx-text-fill: #0F172A; -fx-font-size: 13px;");

        String subStr = "Transaction #" + item.getId();
        Label subLabel = new Label(subStr);
        subLabel.setStyle("-fx-font-size: 11px; -fx-text-fill: #64748B; -fx-font-weight: 500;");
        nameBox.getChildren().addAll(nameLabel, subLabel);

        // 2. Structured Item Details Block
        VBox itemContainer = new VBox(4);
        HBox.setHgrow(itemContainer, Priority.ALWAYS);
        itemContainer.setMaxWidth(Double.MAX_VALUE);

        String rawItemStr = item.getItem();
        if (rawItemStr != null && !rawItemStr.trim().isEmpty()) {
            for (String line : rawItemStr.split("\n")) {
                if (!line.trim().isEmpty()) {
                    itemContainer.getChildren().add(buildItemLineCard(line.trim()));
                }
            }
        }

        // 3. Total Block
        VBox totalBox = new VBox();
        totalBox.setPrefWidth(100);
        totalBox.setAlignment(Pos.CENTER_RIGHT);
        Label totalLabel = new Label("UGX " + (item.getAmount() == null ? "0" : item.getAmount()));
        totalLabel.setStyle("-fx-font-size: 12px; -fx-font-weight: 600; -fx-text-fill: #475569;");
        totalBox.getChildren().add(totalLabel);

        // 4. Paid Block
        VBox paidBox = new VBox();
        paidBox.setPrefWidth(100);
        paidBox.setAlignment(Pos.CENTER_RIGHT);
        Label paidLabel = new Label("UGX " + (item.getPaidAmount() == null ? "0" : item.getPaidAmount()));
        paidLabel.setStyle("-fx-font-size: 12px; -fx-font-weight: 600; -fx-text-fill: #059669;");
        paidBox.getChildren().add(paidLabel);

        // 5. Remaining Balance Block
        VBox remBox = new VBox();
        remBox.setPrefWidth(130);
        remBox.setAlignment(Pos.CENTER_RIGHT);

        double totalVal = parseDouble(item.getAmount());
        double paidVal = parseDouble(item.getPaidAmount());
        double remVal = Math.max(0, totalVal - paidVal);

        Label remLabel = new Label(String.format("UGX %,.0f", remVal));
        remLabel.setStyle("-fx-font-size: 13px; -fx-font-weight: 800; -fx-text-fill: #DC2626;");
        remBox.getChildren().add(remLabel);

        // 6. Date Block
        VBox dateBox = new VBox();
        dateBox.setPrefWidth(100);
        dateBox.setAlignment(Pos.CENTER_RIGHT);
        Label dateLabel = new Label(item.getDate() == null ? "" : item.getDate());
        dateLabel.setStyle("-fx-font-size: 12px; -fx-text-fill: #475569; -fx-font-weight: 500;");
        dateBox.getChildren().add(dateLabel);

        // 7. Actions Block
        VBox actionBox = new VBox();
        actionBox.setPrefWidth(90);
        actionBox.setAlignment(Pos.CENTER);

        Button settleBtn = new Button("Settle Debt");
        settleBtn.getStyleClass().add("pill");
        settleBtn.setStyle("-fx-font-size: 11px; -fx-padding: 4 10; -fx-background-color: #EF4444; -fx-text-fill: white; -fx-font-weight: bold;");
        settleBtn.setOnAction(e -> showSettleDebtDialog(item));
        actionBox.getChildren().add(settleBtn);

        rowCard.getChildren().addAll(nameBox, itemContainer, totalBox, paidBox, remBox, dateBox, actionBox);
        return rowCard;
    }

    // ==========================================
    // 2. PAYMENT HISTORY TAB RENDERING
    // ==========================================
    private void renderPaymentLogs(List<DebtPaymentLog> logs) {
        paymentLogsListContainer.getChildren().clear();
        if (logs == null || logs.isEmpty()) {
            paymentLogsListContainer.getChildren().add(createEmptyStateNode("No Payment Logs", "No partial debt payments recorded yet."));
            return;
        }

        for (DebtPaymentLog log : logs) {
            paymentLogsListContainer.getChildren().add(createPaymentLogRowCard(log));
        }
    }

    private HBox createPaymentLogRowCard(DebtPaymentLog log) {
        HBox rowCard = new HBox(12);
        rowCard.setAlignment(Pos.CENTER_LEFT);
        rowCard.getStyleClass().addAll("history-row-card", "card-accent-stock");

        // 1. Customer Name Block
        VBox nameBox = new VBox(2);
        nameBox.setPrefWidth(220);
        nameBox.setAlignment(Pos.CENTER_LEFT);

        Label nameLabel = new Label(log.getCustomer() == null ? "Customer" : log.getCustomer());
        nameLabel.setStyle("-fx-font-weight: 800; -fx-text-fill: #0F172A; -fx-font-size: 13px;");

        Label subLabel = new Label("Partial Settlement Payment");
        subLabel.setStyle("-fx-font-size: 11px; -fx-text-fill: #64748B; -fx-font-weight: 500;");
        nameBox.getChildren().addAll(nameLabel, subLabel);

        // 2. Amount Paid Block
        VBox amountBox = new VBox();
        amountBox.setPrefWidth(180);
        amountBox.setAlignment(Pos.CENTER_RIGHT);

        Label amountLabel = new Label(String.format("+ UGX %,.0f", log.getAmountPaid()));
        amountLabel.setStyle("-fx-font-size: 14px; -fx-font-weight: 800; -fx-text-fill: #059669;");
        amountBox.getChildren().add(amountLabel);

        // 3. Payment Date Block
        VBox dateBox = new VBox();
        dateBox.setPrefWidth(160);
        dateBox.setAlignment(Pos.CENTER_RIGHT);

        Label dateLabel = new Label(log.getDate() == null ? "" : log.getDate());
        dateLabel.setStyle("-fx-font-size: 12px; -fx-text-fill: #475569; -fx-font-weight: 500;");
        dateBox.getChildren().add(dateLabel);

        // 4. Status Badge Block
        VBox statusBox = new VBox();
        HBox.setHgrow(statusBox, Priority.ALWAYS);
        statusBox.setAlignment(Pos.CENTER);

        Label statusBadge = new Label("PARTIAL PAYMENT");
        statusBadge.getStyleClass().addAll("badge", "badge-partial");
        statusBox.getChildren().add(statusBadge);

        rowCard.getChildren().addAll(nameBox, amountBox, dateBox, statusBox);
        return rowCard;
    }

    // ==========================================
    // 3. SETTLED DEBTS TAB RENDERING
    // ==========================================
    private void renderSettledDebts(List<HistoryItem> items) {
        settledListContainer.getChildren().clear();
        if (items == null || items.isEmpty()) {
            settledListContainer.getChildren().add(createEmptyStateNode("No Fully Settled Debts", "No fully paid customer accounts found yet."));
            return;
        }

        for (HistoryItem item : items) {
            settledListContainer.getChildren().add(createSettledRowCard(item));
        }
    }

    private HBox createSettledRowCard(HistoryItem item) {
        HBox rowCard = new HBox(12);
        rowCard.setAlignment(Pos.CENTER_LEFT);
        rowCard.getStyleClass().addAll("history-row-card", "card-accent-retail");

        // 1. Customer Name Block
        VBox nameBox = new VBox(2);
        nameBox.setPrefWidth(170);
        nameBox.setAlignment(Pos.CENTER_LEFT);

        Label nameLabel = new Label(item.getName() == null ? "Walk-in Customer" : item.getName());
        nameLabel.setStyle("-fx-font-weight: 800; -fx-text-fill: #0F172A; -fx-font-size: 13px;");

        Label subLabel = new Label("Fully Settled Account");
        subLabel.setStyle("-fx-font-size: 11px; -fx-text-fill: #64748B; -fx-font-weight: 500;");
        nameBox.getChildren().addAll(nameLabel, subLabel);

        // 2. Structured Item Details Block
        VBox itemContainer = new VBox(4);
        HBox.setHgrow(itemContainer, Priority.ALWAYS);
        itemContainer.setMaxWidth(Double.MAX_VALUE);

        String rawItemStr = item.getItem();
        if (rawItemStr != null && !rawItemStr.trim().isEmpty()) {
            for (String line : rawItemStr.split("\n")) {
                if (!line.trim().isEmpty()) {
                    itemContainer.getChildren().add(buildItemLineCard(line.trim()));
                }
            }
        }

        // 3. Total Amount Block
        VBox amountBox = new VBox();
        amountBox.setPrefWidth(140);
        amountBox.setAlignment(Pos.CENTER_RIGHT);

        Label amountLabel = new Label("UGX " + (item.getAmount() == null ? "0" : item.getAmount()));
        amountLabel.setStyle("-fx-font-size: 13px; -fx-font-weight: 800; -fx-text-fill: #059669;");
        amountBox.getChildren().add(amountLabel);

        // 4. Completion Date Block
        VBox dateBox = new VBox();
        dateBox.setPrefWidth(120);
        dateBox.setAlignment(Pos.CENTER_RIGHT);

        Label dateLabel = new Label(item.getDate() == null ? "" : item.getDate());
        dateLabel.setStyle("-fx-font-size: 12px; -fx-text-fill: #475569; -fx-font-weight: 500;");
        dateBox.getChildren().add(dateLabel);

        // 5. Status Badge Block
        VBox statusBox = new VBox();
        statusBox.setPrefWidth(110);
        statusBox.setAlignment(Pos.CENTER);

        Label statusBadge = new Label("FULLY SETTLED");
        statusBadge.getStyleClass().addAll("badge", "badge-settled");
        statusBox.getChildren().add(statusBadge);

        rowCard.getChildren().addAll(nameBox, itemContainer, amountBox, dateBox, statusBox);
        return rowCard;
    }

    // ==========================================
    // HELPER & DIALOG METHODS
    // ==========================================
    private Node createEmptyStateNode(String titleStr, String subStr) {
        VBox emptyBox = new VBox(8);
        emptyBox.getStyleClass().add("empty-state-box");

        Label title = new Label(titleStr);
        title.getStyleClass().add("empty-state-title");

        Label sub = new Label(subStr);
        sub.getStyleClass().add("empty-state-sub");

        emptyBox.getChildren().addAll(title, sub);
        return emptyBox;
    }

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

                double unitPriceVal = parseDouble(middlePart);
                double amountVal = parseDouble(rightPart);

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

        Label fallbackLabel = new Label(text);
        fallbackLabel.getStyleClass().add("item-name-bold");
        fallbackLabel.setWrapText(true);
        lineBox.getChildren().add(fallbackLabel);
        return lineBox;
    }

    private double parseDouble(String str) {
        if (str == null) return 0;
        try {
            String cleaned = str.replaceAll("[^0-9.]", "");
            return cleaned.isEmpty() ? 0 : Double.parseDouble(cleaned);
        } catch (Exception e) {
            return 0;
        }
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

        double total = parseDouble(item.getAmount());
        double paid = parseDouble(item.getPaidAmount());
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
                double amount = parseDouble(amountStr);
                if (amount <= 0) {
                    DialogHelper.showAlert("Please enter a valid amount.");
                    return;
                }
                dataManager.getDbHelper().markDebtAsPaid(item.getName(), amount);
                dataManager.notifyDataChanged();
                loadData();
            } catch (NumberFormatException e) {
                DialogHelper.showAlert("Invalid amount format.");
            }
        });
    }
}
