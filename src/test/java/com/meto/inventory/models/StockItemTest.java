package com.meto.inventory.models;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

public class StockItemTest {

    @Test
    public void testFiveParameterConstructor() {
        StockItem item = new StockItem("Widget", "10", "pcs", "100.0", "1000.0");
        assertEquals("Widget", item.getItems());
        assertEquals("10", item.getQty());
        assertEquals("pcs", item.getUnit());
        assertEquals("100.0", item.getPrice());
        assertEquals("1000.0", item.getAmount());
    }

    @Test
    public void testSevenParameterConstructor() {
        StockItem item = new StockItem("Gadget", "5", "box", "50.0", "250.0", "Acme Corp", "2026-07-24");
        assertEquals("Gadget", item.getItems());
        assertEquals("5", item.getQty());
        assertEquals("box", item.getUnit());
        assertEquals("50.0", item.getPrice());
        assertEquals("250.0", item.getAmount());
        assertEquals("Acme Corp", item.getSupplier());
        assertEquals("2026-07-24", item.getDate());
    }

    @Test
    public void testSettersAndPropertyBindings() {
        StockItem item = new StockItem();
        item.setItems("Tool");
        item.setQty("20");
        item.setUnit("pcs");
        item.setPrice("15.5");
        item.setAmount("310.0");

        assertEquals("Tool", item.getItems());
        assertEquals("20", item.getQty());
        assertEquals("pcs", item.getUnit());
        assertEquals("15.5", item.getPrice());
        assertEquals("310.0", item.getAmount());
    }

    @Test
    public void testNullHandlingInSevenParamConstructor() {
        StockItem item = new StockItem("Item", "1", "pcs", null, null, null, null);
        assertEquals("", item.getPrice());
        assertEquals("", item.getAmount());
        assertEquals("", item.getSupplier());
        assertEquals("", item.getDate());
    }
}
