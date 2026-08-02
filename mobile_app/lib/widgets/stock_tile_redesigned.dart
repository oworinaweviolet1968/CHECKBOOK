import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/colors.dart';

class StockTileRedesigned extends StatelessWidget {
  final String itemName;
  final String itemSize; // e.g. "250ml" or "Size: 250ml"
  final String price; // e.g. "UGX 100,000" or "UGX 100,000 / box*12"
  final String? packagingUnit; // e.g. "box*12", "box*24", "half doz", "pcs"
  final String quantity; // e.g. "7 Dozen", "19 Bx", "14 Half Dozen", "5 Doz / 6 pcs"
  final bool isLowStock;
  final bool isEdited;
  final String source;

  const StockTileRedesigned({
    super.key,
    required this.itemName,
    required this.itemSize,
    required this.price,
    this.packagingUnit,
    required this.quantity,
    this.isLowStock = false,
    this.isEdited = false,
    this.source = "System",
  });

  @override
  Widget build(BuildContext context) {
    // 1. Prepare Size string: ensure "Size: " prefix
    final formattedSize = itemSize.startsWith("Size:") ? itemSize : "Size: $itemSize";

    // 2. Prepare Price string & extract packaging unit if embedded in price
    String basePrice = price;
    String unitChipText = (packagingUnit ?? "").trim();

    if (basePrice.contains('/')) {
      final parts = basePrice.split('/');
      basePrice = parts.first.trim();
      if (unitChipText.isEmpty && parts.length > 1) {
        unitChipText = parts[1].replaceAll(RegExp(r'^\d+(\.\d+)?\s*'), '').trim();
      }
    }

    // Clean up leading numbers in packaging unit if any (e.g., "1 box*12" -> "box*12")
    unitChipText = unitChipText.replaceAll(RegExp(r'^\d+(\.\d+)?\s*'), '').trim();
    if (unitChipText.isEmpty) unitChipText = "pcs";

    // Ensure price has "UGX " prefix if missing
    final formattedPrice = basePrice.startsWith("UGX") ? basePrice : "UGX $basePrice";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left: Item name + Subtitle with styled Packaging Unit Chip
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  itemName,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                    color: const Color(0xFF000000),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4.0,
                  runSpacing: 4.0,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      "$formattedSize •",
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.normal,
                        color: const Color(0xFF666666),
                      ),
                    ),
                    Text(
                      "$formattedPrice /",
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.normal,
                        color: const Color(0xFF666666),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0F7FA), // Soft light cyan tint
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        unitChipText,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF00838F), // Clean dark cyan neutral
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Right: Total Quantity Badge + Status Pill Badge
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  quantity,
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: const Color(0xFF000000),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  textAlign: TextAlign.end,
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (isLowStock ? AppColors.accentPink : AppColors.primaryGreen).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isLowStock ? "LOW STOCK" : "IN STOCK",
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isLowStock ? AppColors.accentPink : AppColors.primaryGreen,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
