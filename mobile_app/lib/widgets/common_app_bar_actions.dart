import 'package:flutter/material.dart';
import '../utils/colors.dart';
import '../screens/account_screen.dart';
import '../services/passcode_service.dart';
import '../screens/notifications_screen.dart';

import '../services/database_helper.dart';

class StandardAppBarActions extends StatefulWidget {
  final VoidCallback? onNotificationPressed;
  final VoidCallback? onRefresh;

  const StandardAppBarActions({
    super.key,
    this.onNotificationPressed,
    this.onRefresh,
  });

  @override
  State<StandardAppBarActions> createState() => _StandardAppBarActionsState();
}

class _StandardAppBarActionsState extends State<StandardAppBarActions> {
  static final Set<int> _notifiedIds = {};
  bool _hasUnread = false;

  @override
  void initState() {
    super.initState();
    _checkUnread();
  }

  @override
  void didUpdateWidget(StandardAppBarActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    _checkUnread();
  }

  Future<void> _checkUnread() async {
    final notifs = await DatabaseHelper.instance.getNotifications();
    if (!mounted) return;
    
    bool hasUnread = false;
    for (var n in notifs) {
      if (n['is_read'] == 0) {
        hasUnread = true;
        int id = n['id'] as int;
        if (n['source'] == 'Desktop' && !_notifiedIds.contains(id)) {
          _notifiedIds.add(id);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Desktop Input: ${n['message']}'),
              backgroundColor: AppColors.primaryGreen,
              duration: const Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
    
    setState(() {
      _hasUnread = hasUnread;
    });
  }

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
              onPressed: widget.onNotificationPressed ?? () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NotificationsScreen()),
                );
                _checkUnread();
              },
            ),
            if (_hasUnread)
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
            if (widget.onRefresh != null) widget.onRefresh!();
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
