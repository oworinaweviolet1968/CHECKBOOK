import 'dart:async';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import '../utils/colors.dart';
import '../services/passcode_service.dart';
import '../screens/notifications_screen.dart';
import '../services/notification_service.dart';
import '../services/supabase_service.dart';

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

  StreamSubscription? _notifSub;

  @override
  void initState() {
    super.initState();
    _checkUnread();
    _notifSub = NotificationService.instance.notificationsStream.listen((_) {
      _checkUnread();
    });
  }

  @override
  void dispose() {
    _notifSub?.cancel();
    super.dispose();
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
        // Desktop app presence indicator
        const _DesktopStatusChip(),
        const SizedBox(width: 4),
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
      ],
    );
  }
}

/// A compact pill widget that shows the desktop app's live online/offline status.
/// Reads from [SupasService.instance.desktopStatus] which is updated every 15 seconds.
class _DesktopStatusChip extends StatelessWidget {
  const _DesktopStatusChip();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<DesktopStatus>(
      valueListenable: SupasService.instance.desktopStatus,
      builder: (context, status, _) {
        Color color;
        Color bgColor;
        IconData icon;
        String label;

        switch (status) {
          case DesktopStatus.online:
            color = const Color(0xFF10B981); // Emerald 500
            bgColor = const Color(0xFFECFDF5); // Emerald 50
            icon = Icons.desktop_windows;
            label = 'Desktop';
            break;
          case DesktopStatus.offline:
            color = const Color(0xFFEF4444); // Red 500
            bgColor = const Color(0xFFFEF2F2); // Red 50
            icon = Icons.desktop_access_disabled;
            label = 'Desktop';
            break;
          case DesktopStatus.checking:
            color = const Color(0xFFF59E0B); // Amber 500
            bgColor = const Color(0xFFFFFBEB); // Amber 50
            icon = Icons.desktop_windows_outlined;
            label = 'Desktop';
            break;
          case DesktopStatus.unknown:
            color = const Color(0xFF9CA3AF); // Gray 400
            bgColor = const Color(0xFFF9FAFB); // Gray 50
            icon = Icons.desktop_windows_outlined;
            label = 'Desktop';
            break;
        }

        final dotColor = status == DesktopStatus.online
            ? const Color(0xFF10B981)
            : status == DesktopStatus.offline
                ? const Color(0xFFEF4444)
                : const Color(0xFFF59E0B);

        return Tooltip(
          message: _statusTooltip(status),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated dot
                _PulseDot(color: dotColor, isPulsing: status == DesktopStatus.online),
                const SizedBox(width: 4),
                Icon(icon, size: 11, color: color),
                const SizedBox(width: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: color,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _statusTooltip(DesktopStatus status) {
    final meta = SupasService.instance.userMetadata.value;
    final lastSeenTs = meta?['desktop_last_seen'] as int?;
    String timeStr = 'Never';
    if (lastSeenTs != null && lastSeenTs > 0) {
      final date = DateTime.fromMillisecondsSinceEpoch(lastSeenTs);
      timeStr = DateFormat('dd-MMM-yyyy HH:mm').format(date);
    }
    switch (status) {
      case DesktopStatus.online:
        return 'Desktop app is online and connected';
      case DesktopStatus.offline:
        return 'Desktop app is offline (Last seen: $timeStr)';
      case DesktopStatus.checking:
        return 'Checking desktop app status...';
      case DesktopStatus.unknown:
        return 'Desktop app has never connected';
    }
  }
}

/// A small dot that optionally pulses (scale animation) when online.
class _PulseDot extends StatefulWidget {
  final Color color;
  final bool isPulsing;

  const _PulseDot({required this.color, required this.isPulsing});

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _scale = Tween<double>(begin: 0.85, end: 1.15).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
    if (widget.isPulsing) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_PulseDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isPulsing && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.isPulsing && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: widget.isPulsing
              ? [BoxShadow(color: widget.color.withValues(alpha: 0.5), blurRadius: 4, spreadRadius: 1)]
              : null,
        ),
      ),
    );
  }
}
