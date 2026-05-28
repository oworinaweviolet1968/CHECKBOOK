import 'package:flutter/material.dart';
import '../utils/colors.dart';

class SaleTileRedesigned extends StatelessWidget {
  final String customer; // Or "3x Item Name" as per HTML
  final String orderInfo; // "Order #8921 • 14:32 PM"
  final String amount; // "UGX 50.00"
  final String profit; // "Profit: UGX 10.00"
  final bool isPositiveProfit;
  final String source;
  final bool isDebt;

  const SaleTileRedesigned({
    super.key,
    required this.customer,
    required this.orderInfo,
    required this.amount,
    required this.profit,
    this.isPositiveProfit = true,
    this.source = "System",
    this.isDebt = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDebt ? Colors.red.shade50 : AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDebt ? Colors.red.shade200 : Colors.grey.shade100),
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
                          fontSize: 13,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    
                    // Amount
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                            Text(
                              amount,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: isDebt ? Colors.red.shade700 : AppColors.textPrimary,
                              ),
                            ),
                            if (isDebt)
                              Text(
                                "DEBT",
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.red.shade700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            if (profit.isNotEmpty)
                              Text(
                                profit,
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primaryGreen,
                                ),
                              ),
                        ]
                    )
                  ],
                ),
                const SizedBox(height: 4),
                // Subtext (Order info)
                Row(
                    children: [
                        Text(
                          orderInfo,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
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
