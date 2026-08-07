import 'dart:async';
import 'package:flutter/foundation.dart';
import 'database_helper.dart';
import 'supabase_service.dart';

class AppNotification {
  final String id;
  final String userId;
  final String title;
  final String body;
  final String type;
  final bool isRead;
  final String timestamp;
  final bool isDirty;

  AppNotification({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    this.isRead = false,
    required this.timestamp,
    this.isDirty = false,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    String notifTitle = map['title']?.toString() ?? '';
    String notifBody = map['body']?.toString() ?? map['message']?.toString() ?? '';
    if (notifTitle.isEmpty && notifBody.isNotEmpty) {
      notifTitle = _deriveTitleFromMessage(notifBody);
    }

    return AppNotification(
      id: map['id']?.toString() ?? map['uuid_id']?.toString() ?? map['sync_id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      title: notifTitle.isNotEmpty ? notifTitle : 'Alert',
      body: notifBody,
      type: map['type']?.toString() ?? map['target_type']?.toString() ?? 'GENERAL',
      isRead: map['is_read'] == 1 || map['is_read'] == true,
      timestamp: map['timestamp']?.toString() ?? map['created_at']?.toString() ?? DateTime.now().toUtc().toIso8601String(),
      isDirty: map['is_dirty'] == 1 || map['is_dirty'] == true,
    );
  }

  static String _deriveTitleFromMessage(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('stock')) return 'Stock Alert';
    if (lower.contains('sale')) return 'Sale Alert';
    if (lower.contains('debt') || lower.contains('payment')) return 'Debt / Payment Alert';
    if (lower.contains('deleted')) return 'Audit Alert';
    return 'Notification';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'uuid_id': id,
      'user_id': userId,
      'title': title,
      'body': body,
      'message': body,
      'type': type,
      'target_type': type,
      'is_read': isRead ? 1 : 0,
      'timestamp': timestamp,
      'created_at': timestamp,
      'is_dirty': isDirty ? 1 : 0,
    };
  }

  Map<String, dynamic> toCloudMap() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'body': body,
      'type': type,
      'is_read': isRead,
      'timestamp': timestamp,
    };
  }

  AppNotification copyWith({bool? isRead}) {
    return AppNotification(
      id: id,
      userId: userId,
      title: title,
      body: body,
      type: type,
      isRead: isRead ?? this.isRead,
      timestamp: timestamp,
      isDirty: isDirty,
    );
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._privateConstructor();
  static NotificationService get instance => _instance;

  NotificationService._privateConstructor();

  final StreamController<List<AppNotification>> _notificationsController = StreamController<List<AppNotification>>.broadcast();

  Stream<List<AppNotification>> get notificationsStream => _notificationsController.stream;

  /// Notify user with dual-write (local SQLite + Cloud Push) and local OS system notification
  Future<AppNotification> notify({
    required String title,
    required String body,
    required String type,
    String? userId,
    bool showLocalNotification = true,
  }) async {
    final currentUserId = userId ?? SupasService.instance.userId ?? 'anonymous';
    final notifId = DatabaseHelper.generateUUID();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    final item = AppNotification(
      id: notifId,
      userId: currentUserId,
      title: title,
      body: body,
      type: type.toUpperCase(),
      isRead: false,
      timestamp: nowIso,
      isDirty: true,
    );

    // 1. Dual Write: Save locally
    await DatabaseHelper.instance.saveNotificationRecord(item.toMap());

    // 2. Trigger OS system notification if requested
    if (showLocalNotification) {
      try {
        await DatabaseHelper.instance.showLocalNotification(title, body);
      } catch (e) {
        debugPrint('NotificationService local display error: $e');
      }
    }

    refresh();

    // 3. Dual Write: Push to Cloud backend
    try {
      if (SupasService.instance.userId != null) {
        await SupasService.instance.client
            .from('notifications')
            .upsert(item.toCloudMap(), onConflict: 'id');

        await DatabaseHelper.instance.clearDirtyNotifications([notifId]);
        refresh();
      }
    } catch (e) {
      debugPrint('NotificationService: Deferred cloud push for $notifId: $e');
    }

    return item;
  }

  /// Fetch notifications from local SQLite
  Future<List<AppNotification>> getNotifications({int limit = 100}) async {
    final rawList = await DatabaseHelper.instance.getNotificationsList(limit: limit);
    return rawList.map((m) => AppNotification.fromMap(m)).toList();
  }

  /// Mark notification as read locally & in cloud
  Future<void> markAsRead(String id) async {
    await DatabaseHelper.instance.markNotificationRead(id);
    refresh();

    try {
      if (SupasService.instance.userId != null) {
        await SupasService.instance.client
            .from('notifications')
            .update({'is_read': true})
            .eq('id', id);
      }
    } catch (e) {
      debugPrint('Error updating cloud read status for $id: $e');
    }
  }

  /// Clear/Mark read all notifications
  Future<void> clearAll() async {
    await DatabaseHelper.instance.clearAllNotificationsRecord();
    refresh();

    try {
      if (SupasService.instance.userId != null) {
        await SupasService.instance.client
            .from('notifications')
            .update({'is_read': true})
            .eq('user_id', SupasService.instance.userId!);
      }
    } catch (e) {
      debugPrint('Error clearing cloud notifications: $e');
    }
  }

  /// Trigger stream controller update
  Future<void> refresh() async {
    try {
      final list = await getNotifications();
      if (!_notificationsController.isClosed) {
        _notificationsController.add(list);
      }
    } catch (e) {
      debugPrint('NotificationService refresh error: $e');
    }
  }

  /// Sync all dirty notifications to cloud
  Future<void> syncPendingNotifications() async {
    if (SupasService.instance.userId == null) return;
    try {
      final dirty = await DatabaseHelper.instance.getDirtyNotifications();
      if (dirty.isEmpty) return;

      final cloudPayload = dirty.map((m) => AppNotification.fromMap(m).toCloudMap()).toList();

      await SupasService.instance.client.from('notifications').upsert(cloudPayload, onConflict: 'id');

      final syncedIds = dirty.map((e) => (e['id'] ?? e['uuid_id'] ?? e['sync_id']).toString()).toList();
      await DatabaseHelper.instance.clearDirtyNotifications(syncedIds);
      await refresh();
    } catch (e) {
      debugPrint('NotificationService syncPendingNotifications error: $e');
    }
  }

  /// Upsert cloud records into local SQLite
  Future<void> upsertCloudNotifications(List<Map<String, dynamic>> cloudNotifications) async {
    if (cloudNotifications.isEmpty) return;
    await DatabaseHelper.instance.upsertCloudNotifications(cloudNotifications);
    await refresh();
  }
}
