import 'package:flutter/material.dart';
import '../utils/colors.dart';
import '../screens/account_screen.dart';
import '../services/passcode_service.dart';

class StandardAppBarActions extends StatelessWidget {
  final VoidCallback? onNotificationPressed;
  final VoidCallback? onRefresh;

  const StandardAppBarActions({
    super.key,
    this.onNotificationPressed,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_outlined, color: AppColors.textSecondary),
              onPressed: onNotificationPressed ?? () {},
            ),
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            )
          ],
        ),
        ValueListenableBuilder<bool>(
          valueListenable: PasscodeService.instance.isLocked,
          builder: (context, isLocked, child) {
            if (isLocked) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(Icons.lock_outline, color: AppColors.textPrimary),
              onPressed: () => PasscodeService.instance.lock(),
              tooltip: 'Hide Metrics',
            );
          },
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AccountScreen()),
            );
            if (onRefresh != null) onRefresh!();
          },
          child: Container(
            margin: const EdgeInsets.only(right: 16),
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.primaryGreen.withValues(alpha: 0.2),
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.3)),
            ),
            child: const Icon(Icons.person, size: 20, color: AppColors.primaryGreen),
          ),
        ),
      ],
    );
  }
}
