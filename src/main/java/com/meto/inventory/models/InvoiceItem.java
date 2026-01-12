package com.meto.inventory.models;

import javafx.beans.property.SimpleStringProperty;
import javafx.beans.property.StringProperty;

public class InvoiceItem {
    private final StringProperty item = new SimpleStringProperty();
    private final StringProperty qty = new SimpleStringProperty();
    private final StringProperty itemUnit = new SimpleStringProperty();
    private final StringProperty amount = new SimpleStringProperty();

    public InvoiceItem() {}

    public InvoiceItem(String item, String qty, String itemUnit, String amount) {
        this.item.set(item);
        this.qty.set(qty);
        this.itemUnit.set(itemUnit);
        this.amount.set(amount);
    }

    public String getItem() { return item.get(); }
    public String getQty() { return qty.get(); }
    public String getItemUnit() { return itemUnit.get(); }
    public String getAmount() { return amount.get(); }
}
