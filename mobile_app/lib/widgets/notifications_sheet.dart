import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/notification_service.dart';
import '../utils/colors.dart';

class NotificationsSheet extends StatefulWidget {
  const NotificationsSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const NotificationsSheet(),
    );
  }

  @override
  State<NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<NotificationsSheet> {
  @override
  void initState() {
    super.initState();
    NotificationService.instance.refresh();
  }

  Color _getTypeColor(String type) {
    switch (type.toUpperCase()) {
      case 'LOW_STOCK':
        return Colors.orangeAccent;
      case 'DEBT_OVERDUE':
        return Colors.redAccent;
      case 'SECURITY_ALERT':
        return Colors.purpleAccent;
      case 'STOCK_UPDATE':
      case 'STOCK':
        return Colors.blueAccent;
      case 'SALE':
        return Colors.greenAccent;
      case 'PAYMENT':
        return Colors.tealAccent;
      default:
        return AppColors.accentBlue;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type.toUpperCase()) {
      case 'LOW_STOCK':
        return Icons.warning_amber_rounded;
      case 'DEBT_OVERDUE':
        return Icons.account_balance_wallet_rounded;
      case 'SECURITY_ALERT':
        return Icons.shield_rounded;
      case 'STOCK_UPDATE':
      case 'STOCK':
        return Icons.inventory_2_rounded;
      case 'SALE':
        return Icons.shopping_cart_rounded;
      case 'PAYMENT':
        return Icons.payments_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }

  String _formatTimestamp(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      return DateFormat('MMM dd, hh:mm a').format(dt);
    } catch (_) {
      return isoString;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.neutralBorder,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0),
            child: StreamBuilder<List<AppNotification>>(
              stream: NotificationService.instance.notificationsStream,
              builder: (context, snapshot) {
                final list = snapshot.data ?? [];
                final unreadCount = list.where((n) => !n.isRead).length;

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Notifications',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (unreadCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.accentBlue,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$unreadCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Row(
                      children: [
                        TextButton(
                          onPressed: () => NotificationService.instance.clearAll(),
                          child: const Text(
                            'Mark all read',
                            style: TextStyle(color: AppColors.accentBlue, fontSize: 13),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: AppColors.textSecondary),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),

          const Divider(color: AppColors.neutralBorder, height: 1),

          // List Body
          Expanded(
            child: StreamBuilder<List<AppNotification>>(
              stream: NotificationService.instance.notificationsStream,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
                  return FutureBuilder<List<AppNotification>>(
                    future: NotificationService.instance.getNotifications(),
                    builder: (context, futureSnap) {
                      if (!futureSnap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return _buildNotificationList(futureSnap.data!);
                    },
                  );
                }

                final list = snapshot.data ?? [];
                return _buildNotificationList(list);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationList(List<AppNotification> list) {
    if (list.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_off_rounded, size: 56, color: AppColors.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text(
              'No notifications right now',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: list.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = list[index];
        final typeColor = _getTypeColor(item.type);
        final typeIcon = _getTypeIcon(item.type);

        return InkWell(
          onTap: () {
            if (!item.isRead) {
              NotificationService.instance.markAsRead(item.id);
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: item.isRead ? AppColors.background.withValues(alpha: 0.5) : AppColors.cardBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: item.isRead ? AppColors.neutralBorder.withValues(alpha: 0.3) : typeColor.withValues(alpha: 0.4),
                width: item.isRead ? 1 : 1.5,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: typeColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(typeIcon, color: typeColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontWeight: item.isRead ? FontWeight.normal : FontWeight.bold,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _formatTimestamp(item.timestamp),
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.body,
                        style: TextStyle(
                          color: item.isRead ? AppColors.textSecondary : AppColors.textPrimary.withValues(alpha: 0.9),
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!item.isRead) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: AppColors.accentBlue,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
