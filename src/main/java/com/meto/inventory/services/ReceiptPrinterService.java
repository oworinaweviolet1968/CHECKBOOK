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
    private static final byte[] GS_DOUBLE_SIZE = {0x1D, 0x21, 0x11};
    private static final byte[] GS_NORMAL_SIZE = {0x1D, 0x21, 0x00};
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
            baos.write(GS_DOUBLE_SIZE);
            baos.write("CHECKBOOK APP\n".getBytes());
            baos.write(GS_NORMAL_SIZE);
            baos.write(ESC_BOLD_OFF);
            
            var dbHelper = com.meto.inventory.DataManager.getInstance().getDbHelper();
            String shopName = dbHelper.getSetting("receipt_shop_name");
            if (shopName != null && !shopName.trim().isEmpty()) {
                baos.write(ESC_BOLD_ON);
                baos.write((shopName.toUpperCase() + "\n").getBytes());
                baos.write(ESC_BOLD_OFF);
            }
            
            String shopNum = dbHelper.getSetting("receipt_shop_number");
            if (shopNum != null && !shopNum.trim().isEmpty()) {
                baos.write(("Shop No: " + shopNum + "\n").getBytes());
            }
            
            String location = dbHelper.getSetting("receipt_location");
            if (location != null && !location.trim().isEmpty()) {
                baos.write((location + "\n").getBytes());
            }
            
            String phone = dbHelper.getSetting("receipt_phone");
            if (phone != null && !phone.trim().isEmpty()) {
                baos.write(("Tel: " + phone + "\n").getBytes());
            }
            
            if ((shopName == null || shopName.trim().isEmpty()) && (shopNum == null || shopNum.trim().isEmpty()) && (location == null || location.trim().isEmpty())) {
                baos.write("Inventory Management\n".getBytes());
            }
            
            String formattedDate = new SimpleDateFormat("yyyy-MM-dd HH:mm").format(new Date());
            baos.write(("Date: " + formattedDate + "\n").getBytes());
            baos.write(("Customer: " + (customer.isEmpty() ? "Walk-in Customer" : customer) + "\n").getBytes());
            baos.write("--------------------------------\n".getBytes()); // 32 chars
            
            // 4. Items Table
            baos.write("Item                   Total\n".getBytes());
            baos.write("--------------------------------\n".getBytes()); // 32 chars
            for (SaleItem item : items) {
                String name = item.getItems();
                String size = item.getQty();
                
                String displayTitle = name;
                if (size != null && !size.trim().isEmpty() && !size.trim().equalsIgnoreCase("none")) {
                    displayTitle += " (" + size + ")";
                }
                
                // Print the title line
                baos.write((displayTitle + "\n").getBytes());
                
                // Form the details & amount line
                String unit = item.getUnit(); // e.g. "3 pc"
                long amt = parseAmount(item.getAmount());
                String formattedAmt = df.format(amt);
                
                // We have 32 chars total for a standard 58mm printer line
                String detailLine = " " + unit;
                int remainingPadding = 32 - detailLine.length() - formattedAmt.length();
                if (remainingPadding > 0) {
                    detailLine += " ".repeat(remainingPadding);
                }
                detailLine += formattedAmt + "\n";
                baos.write(detailLine.getBytes());
            }
            
            // 5. Total
            baos.write("--------------------------------\n".getBytes());
            baos.write(ESC_BOLD_ON);
            long total = parseAmount(totalAmount);
            String totalLabel = "TOTAL AMOUNT";
            String totalValStr = df.format(total);
            String totalRow = totalLabel;
            int totalPadding = 32 - totalLabel.length() - totalValStr.length();
            if (totalPadding > 0) {
                totalRow += " ".repeat(totalPadding);
            }
            totalRow += totalValStr + "\n";
            baos.write(totalRow.getBytes());
            baos.write(ESC_BOLD_OFF);
            baos.write("--------------------------------\n".getBytes());
            
            // 6. Footer
            baos.write(ESC_CENTER);
            baos.write("\n\n".getBytes()); // Feed 2 lines
            baos.write("Thank you for your business!\n".getBytes());
            baos.write("Powered by METO IMS\n".getBytes());
            baos.write("\n\n\n".getBytes()); // spacing before cut
            
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
