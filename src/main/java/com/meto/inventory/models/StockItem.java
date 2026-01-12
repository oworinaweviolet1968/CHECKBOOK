package com.meto.inventory.models;

import javafx.beans.binding.Bindings;
import javafx.beans.property.SimpleStringProperty;
import javafx.beans.property.StringProperty;

public class StockItem {
    private final StringProperty items = new SimpleStringProperty();
    private final StringProperty qty = new SimpleStringProperty();
    private final StringProperty unit = new SimpleStringProperty();
    private final StringProperty price = new SimpleStringProperty();
    private final StringProperty amount = new SimpleStringProperty();
    private final StringProperty supplier = new SimpleStringProperty();
    private final StringProperty date = new SimpleStringProperty();

    public StockItem() {}

    // Original constructor (5 parameters)
    public StockItem(String items, String qty, String unit, String price, String amount) {
        this.items.set(items);
        this.qty.set(qty);
        this.unit.set(unit);
        this.price.set(price);
        this.amount.set(amount);
    }

    // New constructor with supplier and date (7 parameters)
    public StockItem(String items, String qty, String unit, String price, String amount,
                     String supplier, String date) {
        this.items.set(items);
        this.qty.set(qty);
        this.unit.set(unit);
        this.price.set(price == null ? "" : price);
        this.amount.set(amount == null ? "" : amount);
        this.supplier.set(supplier == null ? "" : supplier);
        this.date.set(date == null ? "" : date);
    }

    // Getters and property methods
    public String getItems() { return items.get(); }
    public void setItems(String items) { this.items.set(items); }
    public StringProperty itemsProperty() { return items; }

    public String getQty() { return qty.get(); }
    public void setQty(String qty) { this.qty.set(qty); }
    public StringProperty qtyProperty() { return qty; }

    public String getUnit() { return unit.get(); }
    public void setUnit(String unit) { this.unit.set(unit); }
    public StringProperty unitProperty() { return unit; }

    public String getPrice() { return price.get(); }
    public void setPrice(String price) { this.price.set(price); }
    public StringProperty priceProperty() { return price; }

    public String getAmount() { return amount.get(); }
    public void setAmount(String amount) { this.amount.set(amount); }
    public StringProperty amountProperty() { return amount; }

    public String getSupplier() { return supplier.get(); }
    public void setSupplier(String supplier) { this.supplier.set(supplier); }
    public StringProperty supplierProperty() { return supplier; }

    public String getDate() { return date.get(); }
    public void setDate(String date) { this.date.set(date); }
    public StringProperty dateProperty() { return date; }

    public javafx.beans.binding.StringBinding computedAmountProperty() {
        return Bindings.createStringBinding(() -> {
            try {
                // Check for null or empty to avoid unnecessary exceptions
                String qStr = getQty() == null ? "" : getQty().replaceAll("[^0-9.]", "");
                String pStr = getPrice() == null ? "" : getPrice().replaceAll("[^0-9.]", "");

                if (qStr.isEmpty() || pStr.isEmpty()) return "UGX 0";

                double qtyVal = Double.parseDouble(qStr);
                double priceVal = Double.parseDouble(pStr);

                return String.format("UGX %,.0f", qtyVal * priceVal);
            } catch (Exception e) {
                return "UGX 0";
            }
        }, qtyProperty(), priceProperty()); // <--- This tells JavaFX to watch these two fields
    }
}