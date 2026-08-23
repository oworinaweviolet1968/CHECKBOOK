import 'package:flutter/material.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import '../services/database_helper.dart';
import '../services/notification_service.dart';
import '../utils/colors.dart';
import 'debt_history_screen.dart';
import 'history_screen.dart';
import 'deleted_history_screen.dart';
import 'price_update_screen.dart';

enum NotificationTargetType { debt, sale, stock, deleted, price, none, general }

class NotificationRouteInfo {
  final NotificationTargetType type;
  final String query;
  final String? targetId;

  NotificationRouteInfo({required this.type, required this.query, this.targetId});

  factory NotificationRouteInfo.fromMetadata(String? targetType, String? targetId, String message) {
    if (targetType != null && targetType.isNotEmpty) {
      final type = _mapTargetType(targetType);
      final fallbackQuery = _extractFallbackQuery(type, message);
      return NotificationRouteInfo(type: type, query: fallbackQuery, targetId: targetId);
    }
    return NotificationRouteInfo.parse(message);
  }

  static NotificationTargetType _mapTargetType(String targetType) {
    switch (targetType) {
      case 'sale':
        return NotificationTargetType.sale;
      case 'debt':
      case 'payment':
        return NotificationTargetType.debt;
      case 'stock':
        return NotificationTargetType.stock;
      case 'deleted':
        return NotificationTargetType.deleted;
      case 'price':
        return NotificationTargetType.price;
      default:
        return NotificationTargetType.general;
    }
  }

  static String _extractFallbackQuery(NotificationTargetType type, String message) {
    final route = NotificationRouteInfo.parse(message);
    return route.query;
  }

  factory NotificationRouteInfo.parse(String message) {
    final lower = message.toLowerCase();
    String query = '';
    NotificationTargetType type = NotificationTargetType.general;

    if (lower.contains('online') || lower.contains('offline') || lower.contains('internet')) {
      type = NotificationTargetType.none;
    } else if (lower.startsWith('new stock:')) {
      type = NotificationTargetType.stock;
      String itemPart = message.substring(10).trim();
      final idx = itemPart.toLowerCase().lastIndexOf('has been stocked');
      if (idx != -1) {
        query = itemPart.substring(0, idx).trim();
      } else {
        query = itemPart;
      }
    } else if (lower.startsWith('added ')) {
      type = NotificationTargetType.stock;
      final fromIdx = lower.lastIndexOf(' from ');
      if (fromIdx != -1) {
        String itemPart = message.substring(6, fromIdx).trim();
        if (itemPart.toLowerCase() == 'stock') {
          query = message.substring(fromIdx + 6).trim();
        } else {
          query = itemPart;
        }
      } else {
        query = message.substring(6).trim();
      }
    } else if (lower.startsWith('sale recorded:')) {
      type = NotificationTargetType.sale;
      final boughtIdx = lower.indexOf(' bought ');
      if (boughtIdx != -1) {
        String itemPart = message.substring(boughtIdx + 8).trim();
        final parenIdx = itemPart.indexOf('(');
        if (parenIdx != -1) {
          query = itemPart.substring(0, parenIdx).trim();
        } else {
          query = itemPart;
        }
      } else {
        query = message.substring(14).trim();
      }
    } else if (lower.startsWith('sale recorded for ')) {
      type = NotificationTargetType.sale;
      final colonIdx = message.indexOf(':');
      if (colonIdx != -1) {
        String customerPart = message.substring(18, colonIdx).trim();
        String itemsPart = message.substring(colonIdx + 1).trim();
        if (customerPart.toLowerCase() == 'walk-in customer' || customerPart.isEmpty) {
          query = itemsPart.split(',').first.trim();
        } else {
          query = customerPart;
        }
      } else {
        query = message.substring(18).trim();
      }
    } else if (lower.startsWith('sale made for ')) {
      type = NotificationTargetType.sale;
      final colonIdx = message.indexOf(':');
      if (colonIdx != -1) {
        String customerPart = message.substring(14, colonIdx).trim();
        String itemsPart = message.substring(colonIdx + 1).trim();
        if (customerPart.toLowerCase() == 'walk-in customer' || customerPart.isEmpty) {
          query = itemsPart.split(',').first.trim();
        } else {
          query = customerPart;
        }
      } else {
        query = message.substring(14).trim();
      }
    } else if (lower.startsWith('debt recorded for ')) {
      type = NotificationTargetType.debt;
      final colonIdx = message.indexOf(':');
      if (colonIdx != -1) {
        String customerPart = message.substring(18, colonIdx).trim();
        String itemsPart = message.substring(colonIdx + 1).trim();
        if (customerPart.toLowerCase() == 'walk-in customer' || customerPart.isEmpty) {
          query = itemsPart.split(',').first.trim();
        } else {
          query = customerPart;
        }
      } else {
        query = message.substring(18).trim();
      }
    } else if (lower.contains('payment') || lower.contains('paid')) {
      type = NotificationTargetType.debt;
      final receivedIdx = lower.indexOf(' received for ');
      if (receivedIdx != -1) {
        String whoPart = message.substring(receivedIdx + 14).trim();
        if (whoPart.toLowerCase().startsWith('sale #')) {
          query = whoPart.substring(6).trim();
        } else if (whoPart.toLowerCase().startsWith('sale')) {
          query = whoPart.substring(4).trim();
        } else {
          query = whoPart;
        }
      }
    } else if (lower.contains('deleted')) {
      type = NotificationTargetType.deleted;
      final match = RegExp(r'(?:deleted\s+stock:|deleted\s+sale\s+for|deleted)\s+([A-Za-z0-9\s#\-\.\:]+)', caseSensitive: false).firstMatch(message);
      if (match != null) {
        query = match.group(1)!.trim();
      }
    } else if (lower.contains('price') || lower.contains('updated')) {
      type = NotificationTargetType.price;
      final match = RegExp(r'(?:price\s+updated\s+for|for)\s+([A-Za-z0-9\s#\-\.]+)', caseSensitive: false).firstMatch(message);
      if (match != null) {
        query = match.group(1)!.trim();
      }
    }

    if (query.isEmpty && type != NotificationTargetType.none) {
      final words = message.split(RegExp(r'\s+')).where((w) => !['payment', 'of', 'ugx', 'received', 'for', 'sale', 'added', 'stock', 'deleted', 'price', 'updated'].contains(w.toLowerCase())).join(' ');
      query = words.trim();
    }

    query = query.replaceAll(RegExp(r'\(.*?\)|:.*'), '').trim();

    return NotificationRouteInfo(type: type, query: query);
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  final List<MapEntry<String, List<Map<String, dynamic>>>> _sections = [];

  StreamSubscription? _notifSubscription;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _notifSubscription = NotificationService.instance.notificationsStream.listen((_) {
      if (mounted) _loadNotifications();
    });
  }

  @override
  void dispose() {
    _notifSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    final notifs = await DatabaseHelper.instance.getNotificationsList();
    final mutableNotifs = List<Map<String, dynamic>>.of(notifs);
    mutableNotifs.sort((a, b) {
      final aDate = (a['timestamp'] ?? a['created_at'])?.toString() ?? '';
      final bDate = (b['timestamp'] ?? b['created_at'])?.toString() ?? '';
      return bDate.compareTo(aDate);
    });

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    final DateTime now = DateTime.now();
    final DateTime todayStart = DateTime(now.year, now.month, now.day);
    final DateTime yesterdayStart = todayStart.subtract(const Duration(days: 1));

    for (var notif in mutableNotifs) {
      final DateTime created = DateTime.parse(notif['created_at'] as String);
      String header;
      if (!created.isBefore(todayStart)) {
        header = 'Today';
      } else if (!created.isBefore(yesterdayStart)) {
        header = 'Yesterday';
      } else {
        header = 'Earlier';
      }
      grouped.putIfAbsent(header, () => []);
      grouped[header]!.add(notif);
    }

    const order = ['Today', 'Yesterday', 'Earlier'];
    setState(() {
      _notifications = mutableNotifs;
      _isLoading = false;
      _sections.clear();
      for (final key in order) {
        if (grouped.containsKey(key)) {
          _sections.add(MapEntry(key, grouped[key]!));
        }
      }
    });
  }

  IconData _iconForType(NotificationTargetType type) {
    switch (type) {
      case NotificationTargetType.debt:
        return Icons.account_balance;
      case NotificationTargetType.sale:
        return Icons.shopping_cart;
      case NotificationTargetType.stock:
        return Icons.inventory;
      case NotificationTargetType.deleted:
        return Icons.delete;
      case NotificationTargetType.price:
        return Icons.price_change;
      case NotificationTargetType.general:
        return Icons.info;
      case NotificationTargetType.none:
        return Icons.notifications;
    }
  }

  Future<void> _onNotificationTap(Map<String, dynamic> notif) async {
    final notifId = (notif['id'] ?? notif['uuid_id'] ?? notif['sync_id'])?.toString();
    if (notifId != null && notifId.isNotEmpty) {
      await NotificationService.instance.markAsRead(notifId);
      _loadNotifications();
    }
    final routeInfo = NotificationRouteInfo.fromMetadata(
      notif['target_type'] as String?,
      notif['target_id'] as String?,
      notif['message'].toString(),
    );
    if (!mounted) return;
    switch (routeInfo.type) {
      case NotificationTargetType.none:
        break;
      case NotificationTargetType.debt:
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DebtHistoryScreen(highlightQuery: routeInfo.query),
        ));
        break;
      case NotificationTargetType.sale:
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => HistoryScreen(
            initialTab: 2,
            highlightQuery: routeInfo.query,
            highlightReceiptId: routeInfo.targetId,
          ),
        ));
        break;
      case NotificationTargetType.stock:
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => HistoryScreen(
            initialTab: 1,
            highlightQuery: routeInfo.query,
            highlightReceiptId: routeInfo.targetId,
          ),
        ));
        break;
      case NotificationTargetType.deleted:
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => DeletedHistoryScreen(highlightQuery: routeInfo.query),
        ));
        break;
      case NotificationTargetType.price:
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PriceUpdateScreen(highlightQuery: routeInfo.query),
        ));
        break;
      case NotificationTargetType.general:
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => HistoryScreen(
            initialTab: 0,
            highlightQuery: routeInfo.query,
            highlightReceiptId: routeInfo.targetId,
          ),
        ));
        break;
    }
  }

  Widget _buildNotificationTile(Map<String, dynamic> notif, {bool isFirst = false, bool isLast = false}) {
    final routeInfo = NotificationRouteInfo.parse(notif['message'].toString());
    final canNavigate = routeInfo.type != NotificationTargetType.none;
    final created = DateTime.parse(notif['created_at'] as String);
    final formattedDate = DateFormat('MMM d, yyyy — HH:mm').format(created);
    String formatCurrencyInMessage(String input) {
      final formatter = NumberFormat("#,###");

      String formatted = input.replaceAllMapped(
        RegExp(r'UGX\s*(\d+(?:\.\d+)?)', caseSensitive: false),
        (match) {
          final val = double.tryParse(match.group(1)!) ?? 0;
          return "UGX ${formatter.format(val.round())}";
        },
      );

      formatted = formatted.replaceAllMapped(
        RegExp(r'Payment of\s+(\d+(?:\.\d+)?)', caseSensitive: false),
        (match) {
          final val = double.tryParse(match.group(1)!) ?? 0;
          return "Payment of UGX ${formatter.format(val.round())}";
        },
      );

      formatted = formatted.replaceAllMapped(
        RegExp(r'(bought|amount|paid)\s+(\d+(?:\.\d+)?)', caseSensitive: false),
        (match) {
          final word = match.group(1)!;
          final val = double.tryParse(match.group(2)!) ?? 0;
          return "$word UGX ${formatter.format(val.round())}";
        },
      );

      return formatted;
    }

    final rawMessage = notif['message'].toString();
    final message = formatCurrencyInMessage(rawMessage);

    // Bold specific parts of the message (UGX amounts, online status, item names)
    List<TextSpan> buildMessageSpans(String text) {
      final spans = <TextSpan>[];
      final regex = RegExp(r'(UGX\s+[\d,]+|App is online\.|Connected to internet\.)', caseSensitive: false);
      
      int start = 0;
      for (final match in regex.allMatches(text)) {
        if (match.start > start) {
          spans.add(TextSpan(text: text.substring(start, match.start)));
        }
        
        final matchedText = match.group(0)!;
        Color color = AppColors.textPrimary;
        if (matchedText.toUpperCase().startsWith('UGX')) {
             color = AppColors.primaryGreen;
        }

        spans.add(TextSpan(
          text: matchedText,
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ));
        start = match.end;
      }
      
      if (start < text.length) {
        spans.add(TextSpan(text: text.substring(start)));
      }
      return spans;
    }

    Widget buildIcon() {
        if (message.contains('App is online') || message.contains('Connected to internet')) {
             return Stack(
                alignment: Alignment.center,
                children: [
                    Icon(Icons.notifications, color: AppColors.primaryGreen, size: 20),
                    if (message.contains('Connected'))
                        Positioned(
                            top: -2,
                            left: -2,
                            child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                    color: AppColors.primaryGreen,
                                    shape: BoxShape.circle,
                                ),
                            ),
                        ),
                ]
             );
        } else if (routeInfo.type == NotificationTargetType.price) {
             return Icon(Icons.money, color: AppColors.primaryGreen, size: 20);
        } else {
             return Icon(_iconForType(routeInfo.type), color: AppColors.primaryGreen, size: 20);
        }
    }


    final rawRead = notif['is_read'];
    final bool isUnread = rawRead == 0 || rawRead == '0' || rawRead == false;

    final radius = BorderRadius.only(
      topLeft: isFirst ? const Radius.circular(8) : Radius.zero,
      topRight: isFirst ? const Radius.circular(8) : Radius.zero,
      bottomLeft: isLast ? const Radius.circular(8) : Radius.zero,
      bottomRight: isLast ? const Radius.circular(8) : Radius.zero,
    );

    return Container(
      decoration: BoxDecoration(
        color: isUnread ? AppColors.primaryGreen.withValues(alpha: 0.08) : Colors.white,
        borderRadius: radius,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: () => _onNotificationTap(notif),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Green circle icon with unread badge indicator
                    Stack(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: isUnread 
                                ? AppColors.primaryGreen.withValues(alpha: 0.22)
                                : AppColors.primaryGreen.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Center(child: buildIcon()),
                        ),
                        if (isUnread)
                          Positioned(
                            right: 0,
                            top: 0,
                            child: Container(
                              width: 11,
                              height: 11,
                              decoration: BoxDecoration(
                                color: AppColors.primaryGreen,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 16),
                    // Message + date + NEW pill
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          RichText(
                            text: TextSpan(
                              style: const TextStyle(
                                fontSize: 14,
                                color: AppColors.textPrimary,
                                height: 1.4,
                              ),
                              children: buildMessageSpans(message),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '$formattedDate • ${notif['source']}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isUnread ? AppColors.primaryGreen : AppColors.textSecondary,
                                    fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isUnread) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryGreen,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'NEW',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Chevron
                    if (canNavigate)
                      const Padding(
                        padding: EdgeInsets.only(left: 8, top: 12),
                        child: Icon(Icons.chevron_right, color: Color(0xFFBDBDBD), size: 20),
                      ),
                  ],
                ),
              ),
              if (!isLast)
                const Divider(height: 1, indent: 76, endIndent: 0, thickness: 0.5, color: Color(0xFFF0F0F0)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA), // Slight off-white background like the screenshot
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0, // No shadow in screenshot
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Notifications',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        actions: [
          if (_notifications.any((n) => n['is_read'] == 0 || n['is_read'] == '0' || n['is_read'] == false))
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton.icon(
                onPressed: () async {
                  for (var n in _notifications) {
                    final isUnread = n['is_read'] == 0 || n['is_read'] == '0' || n['is_read'] == false;
                    if (isUnread) {
                      final rawId = n['id'];
                      final int targetId = rawId is int ? rawId : (rawId is num ? rawId.toInt() : (int.tryParse(rawId?.toString() ?? '0') ?? 0));
                      await DatabaseHelper.instance.markNotificationAsRead(targetId);
                    }
                  }
                  _loadNotifications();
                },
                icon: const Icon(Icons.done_all, size: 18, color: AppColors.primaryGreen),
                label: const Text(
                  'Mark all read',
                  style: TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ),
        ],
        bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1.0),
            child: Container(
                color: const Color(0xFFF0F0F0),
                height: 1.0,
            ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
          : RefreshIndicator(
              onRefresh: _loadNotifications,
              color: AppColors.primaryGreen,
              child: _notifications.isEmpty
                  ? SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: Container(
                        height: MediaQuery.of(context).size.height * 0.7,
                        alignment: Alignment.center,
                        child: const Text(
                          'No notifications yet',
                          style: TextStyle(color: AppColors.textSecondary, fontSize: 16),
                        ),
                      ),
                    )
                  : ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: _sections.length,
                      itemBuilder: (context, sectionIndex) {
                        final section = _sections[sectionIndex];
                        final header = section.key;
                        final items = section.value;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Section header
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12.0, top: 8.0),
                                child: Text(
                                  header,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              // Notification rows inside a rounded card
                              Container(
                                decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                        BoxShadow(
                                            color: Colors.black.withValues(alpha: 0.03),
                                            blurRadius: 10,
                                            offset: const Offset(0, 2),
                                        )
                                    ]
                                ),
                                child: Column(
                                  children: List.generate(items.length, (i) {
                                    return _buildNotificationTile(
                                      items[i],
                                      isFirst: i == 0,
                                      isLast: i == items.length - 1,
                                    );
                                  }),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

