import 'package:flutter/material.dart';
import '../utils/colors.dart';

class StockTileRedesigned extends StatelessWidget {
  final String itemName;
  final String itemSize; // e.g. "Size: M" or "50kg"
  final String price; // e.g. "UGX 25.00"
  final String quantity; // e.g. "45 pcs"
  final bool isLowStock;
  final bool isEdited;
  final String source;

  const StockTileRedesigned({
    super.key,
    required this.itemName,
    required this.itemSize,
    required this.price,
    required this.quantity,
    this.isLowStock = false,
    this.isEdited = false,
    this.source = "System",
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: Colors.transparent, // Background handled by list container usually
          border: Border(bottom: BorderSide(color: Colors.grey.shade50)), // divider
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Icon + Text
          Expanded(
            child: Row(
              children: [
                 // No icon in HTML list for stock, but we can add one if needed? 
                 // HTML has just text.
                 Expanded(
                   child: Column(
                     crossAxisAlignment: CrossAxisAlignment.start,
                     children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                itemName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: AppColors.textPrimary,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: (source.toLowerCase() == "mobile" ? Colors.blue : Colors.grey).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: (source.toLowerCase() == "mobile" ? Colors.blue : Colors.grey).withValues(alpha: 0.2)),
                              ),
                              child: Text(
                                source.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: source.toLowerCase() == "mobile" ? Colors.blue : Colors.grey,
                                ),
                              ),
                            ),
                          ],
                        ),
                       const SizedBox(height: 2),
                       Text(
                         "$itemSize • $price",
                         style: const TextStyle(
                           fontSize: 12,
                           color: AppColors.textSecondary,
                         ),
                       ),
                     ],
                   ),
                 ),
              ],
            ),
          ),
          
          // Right: Quantity + Badge
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  quantity,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  isLowStock ? "LOW STOCK" : "IN STOCK",
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isLowStock ? AppColors.accentAmber : AppColors.primaryGreen,
                    letterSpacing: 0.5,
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
