public class TestDBHelper2 {
    public static void main(String[] args) {
        System.out.println(formatStockForDisplay(200.0, "1kg", "10 box*20"));
    }

    public static double extractNumericValue(String text) {
        if (text == null || text.isEmpty()) return 0.0;
        String lowercaseText = text.toLowerCase().trim();
        double fractionValue = 0.0;
        if (lowercaseText.contains("1/4")) fractionValue = 0.25;
        else if (lowercaseText.contains("1/2")) fractionValue = 0.5;

        String cleaned = lowercaseText.replace("1/4", "").replace("1/2", "");
        java.util.regex.Pattern pattern = java.util.regex.Pattern.compile("(\\d+\\.?\\d*)");
        java.util.regex.Matcher matcher = pattern.matcher(cleaned);
        if (matcher.find()) {
            try {
                double value = Double.parseDouble(matcher.group(1));
                if (fractionValue > 0) return value + fractionValue;
                return value;
            } catch (NumberFormatException e) {
                return fractionValue;
            }
        }
        return fractionValue;
    }

    public static double getUnitMultiplier(String unitText, String size, String bulkUnit) {
        if (unitText == null || unitText.isEmpty()) return 1.0;
        String type = unitText.toLowerCase().replaceAll("\\s+", ""); 
        String sizeLower = size.toLowerCase().replaceAll("\\s+", "");
        String bulkLower = (bulkUnit != null) ? bulkUnit.toLowerCase().replaceAll("\\s+", "") : "";

        double sizeNum = extractNumericValue(sizeLower);
        boolean isBulkSack = sizeLower.contains("kg") && sizeNum >= 10.0;

        if (type.contains("sack") || (isBulkSack && (type.contains("pc") || type.contains("item")))) {
            return sizeNum;
        }

        if (type.contains("*")) {
            try {
                String afterStar = type.substring(type.lastIndexOf("*") + 1).trim();
                double val = extractNumericValue(afterStar);
                if (val > 0) return val;
            } catch (Exception e) {}
        }

        String normalizedType = type.replaceAll("^[0-9./* ]+", "");
        if (normalizedType.equals("pc") || normalizedType.equals("pcs") || normalizedType.equals("item") || normalizedType.equals("items")) {
            return 1.0;
        }

        if (normalizedType.contains("halfdoz")) return 6.0;
        if (normalizedType.contains("half")) return 0.5;
        if (normalizedType.contains("quarter")) return 0.25;
        if (normalizedType.contains("dozen") || normalizedType.contains("doz")) return 12.0;

        if (normalizedType.equals("box") || normalizedType.equals("boxes") || normalizedType.contains("carton") || normalizedType.contains("crate")) {
            if (sizeLower.contains("*")) {
                try {
                    String afterStar = sizeLower.substring(sizeLower.lastIndexOf("*") + 1).trim();
                    double val = extractNumericValue(afterStar);
                    if (val > 0) return val;
                } catch (Exception e) {}
            }
            if (bulkLower.contains("*")) {
                try {
                    String afterStar = bulkLower.substring(bulkLower.lastIndexOf("*") + 1).trim();
                    double val = extractNumericValue(afterStar);
                    if (val > 0) return val;
                } catch (Exception e) {}
            }
            if (normalizedType.contains("crate")) return 25.0;
            if (normalizedType.contains("carton")) return 24.0;
            return 20.0;
        }
        return 1.0;
    }

    private static String formatStockForDisplay(double totalBase, String size, String bulkUnit) {
        String sizeLower = size.toLowerCase().replaceAll("\\s+", "");

        if (sizeLower.contains("kg")) {
            double kgPerSack = extractNumericValue(size);
            if (kgPerSack >= 10.0) {
                int sacks = (int) (totalBase / kgPerSack);
                double remainingKg = totalBase % kgPerSack;
                if (sacks > 0 && remainingKg > 0.01)
                    return String.format("%d Sacks / %.1f kg", sacks, remainingKg);
                if (sacks > 0)
                    return String.format("%d Sacks", sacks);
                return String.format("%.1f kg", remainingKg);
            }
        }

        double multiplier = getUnitMultiplier(bulkUnit, size, bulkUnit);

        if (multiplier <= 1.0) {
            return String.format("%,.0f pcs", totalBase);
        }

        String friendlyName;
        if (multiplier == 6.0) friendlyName = "Half Doz";
        else if (multiplier == 12.0) friendlyName = "Doz";
        else if (sizeLower.contains("crate")) friendlyName = "Crs";
        else if (sizeLower.contains("carton")) friendlyName = "Cts";
        else if (sizeLower.contains("pack")) friendlyName = "Pks";
        else if (sizeLower.contains("bundle")) friendlyName = "Bndls";
        else friendlyName = "Bx"; 

        int mainCount = (int) (totalBase / multiplier);
        int leftover = (int) (Math.round(totalBase % multiplier));

        StringBuilder display = new StringBuilder();

        if (mainCount > 0) {
            display.append(mainCount).append(" ").append(friendlyName);
        }

        if (multiplier > 12.0 && leftover >= 12) {
            int dozens = leftover / 12;
            leftover = leftover % 12;
            if (display.length() > 0) display.append(" / ");
            display.append(dozens).append(" Doz");
        }

        if (leftover > 0) {
            if (display.length() > 0) display.append(" / ");
            display.append(leftover).append(" pcs");
        }

        return display.length() > 0 ? display.toString() : "0 pcs";
    }
}
