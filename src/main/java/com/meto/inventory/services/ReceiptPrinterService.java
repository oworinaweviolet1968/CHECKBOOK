package com.meto.inventory.services;

import com.meto.inventory.models.SaleItem;
import javafx.collections.ObservableList;

import javax.print.*;
import javax.print.attribute.HashPrintRequestAttributeSet;
import javax.print.attribute.PrintRequestAttributeSet;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.Date;

public class ReceiptPrinterService {

    // Common ESC/POS Commands
    private static final byte[] ESC_INIT = {0x1B, 0x40};
    private static final byte[] ESC_CENTER = {0x1B, 0x61, 0x01};
    private static final byte[] ESC_LEFT = {0x1B, 0x61, 0x00};
    private static final byte[] ESC_BOLD_ON = {0x1B, 0x45, 0x01};
    private static final byte[] ESC_BOLD_OFF = {0x1B, 0x45, 0x00};
    private static final byte[] LF = {0x0A};

    public static void printReceipt(ObservableList<SaleItem> items, String customer, String totalAmount) {
        // Try multiple keywords to find the thermal printer
        PrintService printer = findThermalPrinter();
        
        if (printer == null) {
            System.err.println("⚠️ No thermal printer found (searched for mpt, pos, thermal, demo, yc).");
            System.err.println("Listing all available printers for help:");
            PrintService[] all = PrintServiceLookup.lookupPrintServices(null, null);
            for (PrintService s : all) System.err.println("  - [" + s.getName() + "]");
            
            // Fallback to default
            printer = PrintServiceLookup.lookupDefaultPrintService();
            if (printer != null) {
                System.err.println("⚠️ Falling back to default printer: [" + printer.getName() + "]");
            }
        }

        if (printer == null) {
            System.err.println("❌ Critical: No printers detected at all. Please add your printer in 'Settings > Printers'.");
            return;
        }

        try (ByteArrayOutputStream baos = new ByteArrayOutputStream()) {
            java.text.DecimalFormat df = new java.text.DecimalFormat("#,###");
            
            // 1. Initialize
            baos.write(ESC_INIT);
            
            // 2. Header
            baos.write(ESC_CENTER);
            baos.write(ESC_BOLD_ON);
            baos.write("CHECKBOOK APP\n".getBytes());
            baos.write(ESC_BOLD_OFF);
            baos.write("Inventory Management\n".getBytes());
            baos.write(new SimpleDateFormat("yyyy-MM-dd HH:mm:ss\n").format(new Date()).getBytes());
            baos.write("--------------------------------\n".getBytes()); // 32 chars
            
            // 3. Customer Info
            baos.write(ESC_LEFT);
            baos.write(("Customer: " + (customer.isEmpty() ? "Walk-in" : customer) + "\n").getBytes());
            baos.write("--------------------------------\n".getBytes());
            
            // 4. Items Table
            // Column widths for 32 chars: Item(12) Qty(8) Amount(10) + gaps
            baos.write("Item         Qty       Amount\n".getBytes());
            for (SaleItem item : items) {
                String name = item.getItems();
                if (name.length() > 11) name = name.substring(0, 9) + "..";
                
                String qtyDisplay = item.getQty();
                if (qtyDisplay.length() > 8) qtyDisplay = qtyDisplay.substring(0, 8);
                
                // Safe numeric parsing for amount
                long amt = parseAmount(item.getAmount());
                
                String row = String.format("%-12s %-9s %9s\n", 
                        name, 
                        qtyDisplay, 
                        df.format(amt));
                baos.write(row.getBytes());
            }
            
            // 5. Total
            baos.write("--------------------------------\n".getBytes());
            baos.write(ESC_BOLD_ON);
            long total = parseAmount(totalAmount);
            baos.write(("TOTAL: UGX " + df.format(total) + "\n").getBytes());
            baos.write(ESC_BOLD_OFF);
            baos.write("--------------------------------\n".getBytes());
            
            // 6. Footer
            baos.write(ESC_CENTER);
            baos.write("Thank you for your business!\n".getBytes());
            baos.write("\n\n\n".getBytes()); // Extra spacing for tear-off
            
            // Send to printer
            byte[] bytes = baos.toByteArray();
            DocFlavor flavor = DocFlavor.BYTE_ARRAY.AUTOSENSE;
            Doc doc = new SimpleDoc(bytes, flavor, null);
            DocPrintJob job = printer.createPrintJob();
            PrintRequestAttributeSet pras = new HashPrintRequestAttributeSet();
            job.print(doc, pras);
            
        } catch (IOException | PrintException e) {
            e.printStackTrace();
        }
    }

    private static long parseAmount(String input) {
        if (input == null || input.isEmpty()) return 0;
        try {
            // Remove text and commas, but keep the dot for splitting decimals
            String clean = input.replaceAll("[^0-9.]", "");
            if (clean.contains(".")) {
                // Take only the part before the decimal
                clean = clean.split("\\.")[0];
            }
            return Long.parseLong(clean.isEmpty() ? "0" : clean);
        } catch (Exception e) {
            return 0;
        }
    }

    private static PrintService findThermalPrinter() {
        PrintService[] services = PrintServiceLookup.lookupPrintServices(null, null);
        String[] keywords = {"mpt", "thermal", "pos", "demo", "yc"};
        
        for (PrintService service : services) {
            String name = service.getName().toLowerCase();
            for (String kw : keywords) {
                if (name.contains(kw)) {
                    System.out.println("✅ Found potential thermal printer: [" + service.getName() + "]");
                    return service;
                }
            }
        }
        return null;
    }
}
