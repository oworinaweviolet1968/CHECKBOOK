import 'package:flutter/material.dart';
import '../utils/colors.dart';

class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final String percentage; // e.g. "+12%" or "-5%"
  final bool isPositive;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.percentage,
    required this.isPositive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12), // rounded-xl
        border: Border.all(color: Colors.grey.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 2,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title (Uppercased, grey)
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          
          // Value and Bubble Row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Value
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              
              const SizedBox(width: 8),

              // Percentage Bubble
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isPositive 
                      ? AppColors.primaryGreen.withValues(alpha: 0.1) 
                      : AppColors.accentRed.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999), // rounded-full
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPositive ? Icons.trending_up : Icons.trending_down,
                      size: 14,
                      color: isPositive ? AppColors.primaryGreen : AppColors.accentRed,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      percentage,
                      style: TextStyle(
                        color: isPositive ? AppColors.primaryGreen : AppColors.accentRed,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
