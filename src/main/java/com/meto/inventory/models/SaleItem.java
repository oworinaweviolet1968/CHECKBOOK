package com.meto.inventory.models;

import javafx.beans.property.SimpleStringProperty;
import javafx.beans.property.StringProperty;

public class SaleItem {
    private final StringProperty items = new SimpleStringProperty();
    private final StringProperty qty = new SimpleStringProperty();
    private final StringProperty unit = new SimpleStringProperty();
    private final StringProperty price = new SimpleStringProperty();
    private final StringProperty amount = new SimpleStringProperty();

    public SaleItem() {}

    public SaleItem(String items, String qty, String unit, String price, String amount) {
        this.items.set(items);
        this.qty.set(qty);
        this.unit.set(unit);
        this.price.set(price);
        this.amount.set(amount);
    }

    public String getItems() { return items.get(); }
    public StringProperty itemsProperty() { return items; }

    public String getQty() { return qty.get(); }
    public StringProperty qtyProperty() { return qty; }

    public String getUnit() { return unit.get(); }
    public StringProperty unitProperty() { return unit; }

    public String getPrice() { return price.get(); }
    public StringProperty priceProperty() { return price; }

    public String getAmount() { return amount.get(); }
    public StringProperty amountProperty() { return amount; }
}
