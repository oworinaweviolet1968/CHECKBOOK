import 'package:flutter/material.dart';
import '../utils/colors.dart';

class SaleTileRedesigned extends StatelessWidget {
  final String customer; // Or "3x Item Name" as per HTML
  final String orderInfo; // "Order #8921 • 14:32 PM"
  final String amount; // "UGX 50.00"
  final String profit; // "Profit: UGX 10.00"
  final bool isPositiveProfit;

  const SaleTileRedesigned({
    super.key,
    required this.customer,
    required this.orderInfo,
    required this.amount,
    required this.profit,
    this.isPositiveProfit = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Icon Circle
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.payments_outlined,
              color: AppColors.primaryGreen,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          
          // Content
          Expanded(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Main Text (Item Name / Customer)
                    Expanded(
                      child: Text(
                        customer,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    
                    // Amount
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                            Text(
                              amount,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              profit,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primaryGreen, // Always green for profit label? HTML has text-primary green
                              ),
                            ),
                        ]
                    )
                  ],
                ),
                const SizedBox(height: 2),
                // Subtext (Order info)
                Row(
                    children: [
                        Text(
                          orderInfo,
                          style: const TextStyle(
                            fontSize: 10, // HTML says xs (12px usually, but maybe 10 here to fit)
                            color: AppColors.textSecondary,
                          ),
                        ),
                    ]
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}
