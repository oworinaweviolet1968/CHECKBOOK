package com.meto.inventory.models;

import javafx.beans.property.SimpleStringProperty;
import javafx.beans.property.StringProperty;

public class HistoryItem {
    private final StringProperty name = new SimpleStringProperty();
    private final StringProperty item = new SimpleStringProperty();
    private final StringProperty typeUnit = new SimpleStringProperty();
    private final StringProperty qty = new SimpleStringProperty();
    private final StringProperty unit = new SimpleStringProperty();
    private final StringProperty price = new SimpleStringProperty();
    private final StringProperty amount = new SimpleStringProperty();
    private final StringProperty profit = new SimpleStringProperty();
    private final StringProperty date = new SimpleStringProperty();
    public HistoryItem() {}

    public HistoryItem(String name, String item, String typeUnit, String qty, String unit, String price, String amount, String profit, String date) {
        this.name.set(name);
        this.item.set(item);
        this.typeUnit.set(typeUnit);
        this.qty.set(qty);
        this.unit.set(unit);
        this.price.set(price);
        this.amount.set(amount);
        this.profit.set(profit);
        this.date.set(date);
    }
    public String getProfit() { return profit.get(); }
    public StringProperty profitProperty() { return profit; }

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

    // Property methods (these are what TableView needs)
    public StringProperty nameProperty() { return name; }
    public StringProperty itemProperty() { return item; }
    public StringProperty typeUnitProperty() { return typeUnit; }
    public StringProperty qtyProperty() { return qty; }
    public StringProperty unitProperty() { return unit; }
    public StringProperty priceProperty() { return price; }
    public StringProperty amountProperty() { return amount; }
    public StringProperty dateProperty() { return date; }
}