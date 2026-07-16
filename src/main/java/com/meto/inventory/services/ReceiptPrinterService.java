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
    // 0x11 = double width + double height (for TOTAL line)
    private static final byte[] GS_DOUBLE_SIZE = {0x1D, 0x21, 0x11};
    private static final byte[] GS_NORMAL_SIZE = {0x1D, 0x21, 0x00};
    private static final byte[] LF = {0x0A};
    // GS V m — partial cut (0x42 = feed and partial cut)
    private static final byte[] GS_CUT = {0x1D, 0x56, 0x42, 0x00};

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
            // 32 chars per line on 58mm thermal paper
            final int LINE_WIDTH = 32;
            
            // ═══════════════════════════════════════════
            // 1. INITIALIZE PRINTER
            // ═══════════════════════════════════════════
            baos.write(ESC_INIT);
            
            // ═══════════════════════════════════════════
            // 2. HEADER — "CHECKBOOK APP" in double size (matching mobile PosTextSize.size2)
            // ═══════════════════════════════════════════
            baos.write(ESC_CENTER);
            baos.write(ESC_BOLD_ON);
            baos.write(GS_DOUBLE_SIZE);  // double width + double height (same as mobile size2)
            baos.write("CHECKBOOK APP\n".getBytes());
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
            // 6. COLUMN HEADERS (matching mobile: Item / Qty / Total)
            // ═══════════════════════════════════════════
            // Mobile layout: PosColumn(Item, w=6), PosColumn(Qty, w=2), PosColumn(Total, w=4)
            // 6/12 = 16 chars, 2/12 = ~5 chars, 4/12 = ~11 chars
            baos.write(ESC_BOLD_ON);
            String headerItem = "Item";
            String headerQty = "Qty";
            String headerTotal = "Total";
            // Build: "Item            Qty       Total"
            String headerLine = padRight(headerItem, 16) + padRight(headerQty, 5) + padLeft(headerTotal, LINE_WIDTH - 16 - 5);
            baos.write((headerLine + "\n").getBytes());
            baos.write(ESC_BOLD_OFF);
            
            // ═══════════════════════════════════════════
            // 7. ITEMS — matching mobile format exactly:
            //    Line 1: "ItemName (Size)" bold
            //    Line 2: " unit              amount"
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
                // Mobile: PosColumn(' unit', w=8) + PosColumn(amount, w=4, right)
                // 8/12 = ~21 chars, 4/12 = ~11 chars
                String unit = item.getUnit(); // e.g. "1 dozen"
                long amt = parseAmount(item.getAmount());
                String formattedAmt = df.format(amt);
                
                String detailLine = " " + unit;
                int padding = LINE_WIDTH - detailLine.length() - formattedAmt.length();
                if (padding > 0) {
                    detailLine += " ".repeat(padding);
                }
                detailLine += formattedAmt + "\n";
                baos.write(detailLine.getBytes());
            }
            
            // ═══════════════════════════════════════════
            // 8. TOTAL SECTION — matching mobile: label and value on SAME row
            // ═══════════════════════════════════════════
            baos.write("--------------------------------\n".getBytes());
            baos.write(ESC_BOLD_ON);
            baos.write(GS_DOUBLE_SIZE);
            long total = parseAmount(totalAmount);
            String totalLabel = "TOTAL AMOUNT";
            String totalValStr = df.format(total);
            // In double-size mode, effective line width is ~16 chars
            // Mobile: PosColumn('TOTAL AMOUNT', w=6) + PosColumn(value, w=6, right)
            int dblLineWidth = LINE_WIDTH / 2; // ~16 effective chars
            int totalPad = dblLineWidth - totalLabel.length() - totalValStr.length();
            String totalLine = totalLabel;
            if (totalPad > 0) {
                totalLine += " ".repeat(totalPad);
            }
            totalLine += totalValStr;
            baos.write(ESC_LEFT);
            baos.write((totalLine + "\n").getBytes());
            baos.write(GS_NORMAL_SIZE);
            baos.write(ESC_BOLD_OFF);
            baos.write(ESC_LEFT);
            baos.write("--------------------------------\n".getBytes());
            
            // ═══════════════════════════════════════════
            // 9. FOOTER — matching mobile: feed(2) + text + feed(3) + cut
            // ═══════════════════════════════════════════
            baos.write(ESC_CENTER);
            baos.write("\n\n\n".getBytes());  // feed(2) equivalent + extra spacing
            baos.write("Thank you for your business!\n".getBytes());
            baos.write("Powered by METO IMS\n".getBytes());
            baos.write("\n\n\n\n\n".getBytes()); // feed(3) equivalent + extra for long receipt
            baos.write(GS_CUT); // Paper cut command (same as mobile generator.cut())
            
            // ═══════════════════════════════════════════
            // 10. SEND TO PRINTER
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

    /** Pads a string with spaces on the right to reach the target width. */
    private static String padRight(String text, int width) {
        if (text.length() >= width) return text;
        return text + " ".repeat(width - text.length());
    }

    /** Pads a string with spaces on the left to reach the target width. */
    private static String padLeft(String text, int width) {
        if (text.length() >= width) return text;
        return " ".repeat(width - text.length()) + text;
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
