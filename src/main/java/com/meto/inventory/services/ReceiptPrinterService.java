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
    // GS ! n — bit 0-2: char width (0-7), bit 4-6: char height (0-7)
    // 0x77 = 0111 0111 = width x8, height x8 (max size for CHECKBOOK header)
    private static final byte[] GS_MAX_SIZE = {0x1D, 0x21, 0x77};
    // 0x11 = double width + double height (for TOTAL line)
    private static final byte[] GS_DOUBLE_SIZE = {0x1D, 0x21, 0x11};
    private static final byte[] GS_NORMAL_SIZE = {0x1D, 0x21, 0x00};
    private static final byte[] LF = {0x0A};

    /**
     * Prints a long-format receipt matching the mobile app layout.
     * Overload for printing from history (with a specific date).
     */
    public static void printReceipt(ObservableList<SaleItem> items, String customer, String totalAmount, String date) {
        doPrint(items, customer, totalAmount, date);
    }

    /**
     * Prints a long-format receipt matching the mobile app layout.
     * Uses current date/time.
     */
    public static void printReceipt(ObservableList<SaleItem> items, String customer, String totalAmount) {
        doPrint(items, customer, totalAmount, null);
    }

    private static void doPrint(ObservableList<SaleItem> items, String customer, String totalAmount, String date) {
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
            
            // ═══════════════════════════════════════════
            // 1. INITIALIZE PRINTER
            // ═══════════════════════════════════════════
            baos.write(ESC_INIT);
            
            // ═══════════════════════════════════════════
            // 2. HEADER — "CHECKBOOK APP" in maximum size
            // ═══════════════════════════════════════════
            baos.write(ESC_CENTER);
            baos.write(ESC_BOLD_ON);
            baos.write(GS_MAX_SIZE);
            baos.write("CHECKBOOK\n".getBytes());
            baos.write("APP\n".getBytes());
            baos.write(GS_NORMAL_SIZE);
            baos.write(ESC_BOLD_OFF);
            
            // ═══════════════════════════════════════════
            // 3. SHOP INFO (from receipt settings)
            // ═══════════════════════════════════════════
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

            String phone2 = dbHelper.getSetting("receipt_phone2");
            if (phone2 != null && !phone2.trim().isEmpty()) {
                baos.write(("Tel: " + phone2 + "\n").getBytes());
            }
            
            // Fallback if nothing is set
            if ((shopName == null || shopName.trim().isEmpty()) 
                && (shopNum == null || shopNum.trim().isEmpty()) 
                && (location == null || location.trim().isEmpty())
                && (phone == null || phone.trim().isEmpty())
                && (phone2 == null || phone2.trim().isEmpty())) {
                baos.write("Smart Inventory Management\n".getBytes());
            }
            
            // ═══════════════════════════════════════════
            // 4. HORIZONTAL RULE
            // ═══════════════════════════════════════════
            baos.write(ESC_LEFT);
            baos.write("--------------------------------\n".getBytes());
            
            // ═══════════════════════════════════════════
            // 5. DATE & CUSTOMER
            // ═══════════════════════════════════════════
            String formattedDate = (date != null && !date.trim().isEmpty()) 
                ? date 
                : new SimpleDateFormat("yyyy-MM-dd HH:mm").format(new Date());
            baos.write(("Date: " + formattedDate + "\n").getBytes());
            baos.write(("Customer: " + (customer.isEmpty() ? "Walk-in Customer" : customer) + "\n").getBytes());
            baos.write("--------------------------------\n".getBytes());
            
            // ═══════════════════════════════════════════
            // 6. ITEMS — Long format (matching mobile)
            //    Each item: bold title line, then detail + amount line
            // ═══════════════════════════════════════════
            for (SaleItem item : items) {
                String name = item.getItems();
                String size = item.getQty();
                
                // Build display title: "ItemName (Size)" like mobile
                String displayTitle = name;
                if (size != null && !size.trim().isEmpty() && !size.trim().equalsIgnoreCase("none")) {
                    displayTitle += " (" + size + ")";
                }
                
                // Print the item name in bold on its own line
                baos.write(ESC_BOLD_ON);
                baos.write((displayTitle + "\n").getBytes());
                baos.write(ESC_BOLD_OFF);
                
                // Print the unit details and amount on the next line
                String unit = item.getUnit(); // e.g. "3 pc"
                long amt = parseAmount(item.getAmount());
                String formattedAmt = df.format(amt);
                
                // 32 chars for 58mm paper
                String detailLine = " " + unit;
                int remainingPadding = 32 - detailLine.length() - formattedAmt.length();
                if (remainingPadding > 0) {
                    detailLine += " ".repeat(remainingPadding);
                }
                detailLine += formattedAmt + "\n";
                baos.write(detailLine.getBytes());
            }
            
            // ═══════════════════════════════════════════
            // 7. TOTAL SECTION
            // ═══════════════════════════════════════════
            baos.write("--------------------------------\n".getBytes());
            baos.write(ESC_BOLD_ON);
            baos.write(GS_DOUBLE_SIZE);
            long total = parseAmount(totalAmount);
            String totalLabel = "TOTAL AMOUNT";
            String totalValStr = df.format(total);
            // In double-size mode, effective chars per line halves to ~16
            // So we print label on one line, amount on the next for clarity
            baos.write(ESC_CENTER);
            baos.write((totalLabel + "\n").getBytes());
            baos.write((totalValStr + "\n").getBytes());
            baos.write(GS_NORMAL_SIZE);
            baos.write(ESC_BOLD_OFF);
            baos.write(ESC_LEFT);
            baos.write("--------------------------------\n".getBytes());
            
            // ═══════════════════════════════════════════
            // 8. FOOTER
            // ═══════════════════════════════════════════
            baos.write(ESC_CENTER);
            baos.write("\n\n".getBytes());
            baos.write("Thank you for your business!\n".getBytes());
            baos.write("Powered by METO IMS\n".getBytes());
            baos.write("\n\n\n".getBytes()); // spacing before cut
            
            // ═══════════════════════════════════════════
            // 9. SEND TO PRINTER
            // ═══════════════════════════════════════════
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
