import 'package:flutter/material.dart';
import '../utils/colors.dart';

class ProcessingLoadingDialog extends StatelessWidget {
  final String title;
  final String message;
  final Color themeColor;

  const ProcessingLoadingDialog({
    super.key,
    required this.title,
    required this.message,
    this.themeColor = AppColors.primaryGreen,
  });

  static void show(
    BuildContext context, {
    required String title,
    required String message,
    Color themeColor = AppColors.primaryGreen,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => ProcessingLoadingDialog(
        title: title,
        message: message,
        themeColor: themeColor,
      ),
    );
  }

  static void hide(BuildContext context) {
    if (Navigator.canPop(context)) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 10,
        backgroundColor: Colors.white,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 340),
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated Spinner Container
              Container(
                width: 72,
                height: 72,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: CircularProgressIndicator(
                  strokeWidth: 3.5,
                  valueColor: AlwaysStoppedAnimation<Color>(themeColor),
                  backgroundColor: themeColor.withValues(alpha: 0.15),
                ),
              ),
              const SizedBox(height: 24),
              // Title
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              // Message
              Text(
                message,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
