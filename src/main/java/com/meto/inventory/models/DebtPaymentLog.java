package com.meto.inventory.models;

import javafx.beans.property.*;

public class DebtPaymentLog {
    private final StringProperty customer = new SimpleStringProperty();
    private final StringProperty item = new SimpleStringProperty();
    private final DoubleProperty amountPaid = new SimpleDoubleProperty();
    private final StringProperty date = new SimpleStringProperty();

    public DebtPaymentLog(String customer, String item, double amountPaid, String date) {
        this.customer.set(customer);
        this.item.set(item);
        this.amountPaid.set(amountPaid);
        this.date.set(date);
    }

    public String getCustomer() { return customer.get(); }
    public StringProperty customerProperty() { return customer; }

    public String getItem() { return item.get(); }
    public StringProperty itemProperty() { return item; }

    public double getAmountPaid() { return amountPaid.get(); }
    public DoubleProperty amountPaidProperty() { return amountPaid; }

    public String getDate() { return date.get(); }
    public StringProperty dateProperty() { return date; }
}
