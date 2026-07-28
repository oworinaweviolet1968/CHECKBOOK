package com.meto.inventory.models;

import javafx.beans.property.*;

public class HistoryItem {
    private final IntegerProperty id = new SimpleIntegerProperty();
    private final StringProperty name = new SimpleStringProperty();
    private final StringProperty item = new SimpleStringProperty();
    private final StringProperty typeUnit = new SimpleStringProperty();
    private final StringProperty qty = new SimpleStringProperty();
    private final StringProperty unit = new SimpleStringProperty();
    private final StringProperty price = new SimpleStringProperty();
    private final StringProperty amount = new SimpleStringProperty();
    private final StringProperty profit = new SimpleStringProperty();
    private final StringProperty date = new SimpleStringProperty();
    private final BooleanProperty isDebt = new SimpleBooleanProperty();
    private final BooleanProperty isPaid = new SimpleBooleanProperty();
    private final StringProperty paidAmount = new SimpleStringProperty();

    public HistoryItem() {}

    public HistoryItem(int id, String name, String item, String typeUnit, String qty, String unit, String price, String amount, String profit, String date, boolean isDebt, boolean isPaid, String paidAmount) {
        this.id.set(id);
        this.name.set(name);
        this.item.set(item);
        this.typeUnit.set(typeUnit);
        this.qty.set(qty);
        this.unit.set(unit);
        this.price.set(price);
        this.amount.set(amount);
        this.profit.set(profit);
        this.date.set(date);
        this.isDebt.set(isDebt);
        this.isPaid.set(isPaid);
        this.paidAmount.set(paidAmount);
    }

    public HistoryItem(String name, String item, String typeUnit, String qty, String unit, String price, String amount, String profit, String date) {
        this(0, name, item, typeUnit, qty, unit, price, amount, profit, date, false, false, "0");
    }

    public int getId() { return id.get(); }
    public IntegerProperty idProperty() { return id; }
    public void setId(int id) { this.id.set(id); }

    public String getProfit() { return profit.get(); }
    public StringProperty profitProperty() { return profit; }

    public boolean isIsDebt() { return isDebt.get(); }
    public BooleanProperty isDebtProperty() { return isDebt; }
    public void setIsDebt(boolean isDebt) { this.isDebt.set(isDebt); }

    public boolean isIsPaid() { return isPaid.get(); }
    public BooleanProperty isPaidProperty() { return isPaid; }
    public void setIsPaid(boolean isPaid) { this.isPaid.set(isPaid); }

    public String getPaidAmount() { return paidAmount.get(); }
    public StringProperty paidAmountProperty() { return paidAmount; }
    public void setPaidAmount(String paidAmount) { this.paidAmount.set(paidAmount); }

    // Getters
    public String getName() { return name.get(); }
    public String getItem() { return item.get(); }
    public String getTypeUnit() { return typeUnit.get(); }
    public String getQty() { return qty.get(); }
    public String getUnit() { return unit.get(); }
    public String getPrice() { return price.get(); }
    public String getAmount() { return amount.get(); }
    public String getDate() { return date.get(); }

    // Setters
    public void setName(String name) { this.name.set(name); }
    public void setItem(String item) { this.item.set(item); }
    public void setTypeUnit(String typeUnit) { this.typeUnit.set(typeUnit); }
    public void setQty(String qty) { this.qty.set(qty); }
    public void setUnit(String unit) { this.unit.set(unit); }
    public void setPrice(String price) { this.price.set(price); }
    public void setAmount(String amount) { this.amount.set(amount); }
    public void setDate(String date) { this.date.set(date); }

    // Property methods
    public StringProperty nameProperty() { return name; }
    public StringProperty itemProperty() { return item; }
    public StringProperty typeUnitProperty() { return typeUnit; }
    public StringProperty qtyProperty() { return qty; }
    public StringProperty unitProperty() { return unit; }
    public StringProperty priceProperty() { return price; }
    public StringProperty amountProperty() { return amount; }
    public StringProperty dateProperty() { return date; }

    public String getPeriodGroup() {
        String dateStr = getDate();
        if (dateStr == null || dateStr.isEmpty()) return "Earlier";
        try {
            java.time.LocalDate itemDate;
            if (dateStr.contains("T")) {
                itemDate = java.time.OffsetDateTime.parse(dateStr).toLocalDate();
            } else if (dateStr.contains(" ")) {
                itemDate = java.time.LocalDate.parse(dateStr.split(" ")[0]);
            } else {
                itemDate = java.time.LocalDate.parse(dateStr);
            }
            java.time.LocalDate today = java.time.LocalDate.now();
            if (itemDate.equals(today)) {
                return "Today";
            } else if (itemDate.equals(today.minusDays(1))) {
                return "Yesterday";
            } else {
                return "Earlier";
            }
        } catch (Exception e) {
            return "Earlier";
        }
    }
}