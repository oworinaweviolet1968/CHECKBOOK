import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'database_helper.dart';
import 'supabase_service.dart';
import 'powersync/device_identity.dart';

class AuditLogItem {
  final String id;
  final String userId;
  final String action;
  final Map<String, dynamic> details;
  final String timestamp;
  final String deviceId;
  final bool isDirty;

  AuditLogItem({
    required this.id,
    required this.userId,
    required this.action,
    required this.details,
    required this.timestamp,
    required this.deviceId,
    this.isDirty = false,
  });

  factory AuditLogItem.fromMap(Map<String, dynamic> map) {
    Map<String, dynamic> parsedDetails = {};
    if (map['details'] != null) {
      if (map['details'] is Map) {
        parsedDetails = Map<String, dynamic>.from(map['details']);
      } else if (map['details'] is String) {
        try {
          parsedDetails = Map<String, dynamic>.from(jsonDecode(map['details']));
        } catch (_) {
          parsedDetails = {'raw': map['details']};
        }
      }
    }

    return AuditLogItem(
      id: map['id']?.toString() ?? '',
      userId: map['user_id']?.toString() ?? '',
      action: map['action']?.toString() ?? 'GENERAL',
      details: parsedDetails,
      timestamp: map['timestamp']?.toString() ?? DateTime.now().toUtc().toIso8601String(),
      deviceId: map['device_id']?.toString() ?? '',
      isDirty: map['is_dirty'] == 1 || map['is_dirty'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'action': action,
      'details': jsonEncode(details),
      'timestamp': timestamp,
      'device_id': deviceId,
      'is_dirty': isDirty ? 1 : 0,
    };
  }

  Map<String, dynamic> toCloudMap() {
    return {
      'id': id,
      'user_id': userId,
      'action': action,
      'details': details,
      'timestamp': timestamp,
      'device_id': deviceId,
    };
  }
}

class AuditService {
  static final AuditService _instance = AuditService._privateConstructor();
  static AuditService get instance => _instance;

  AuditService._privateConstructor();

  final StreamController<List<AuditLogItem>> _logsController = StreamController<List<AuditLogItem>>.broadcast();

  Stream<List<AuditLogItem>> get auditLogsStream => _logsController.stream;

  /// Log an audit action with dual-write to local SQLite and Cloud backend
  Future<AuditLogItem> logAction({
    required String action,
    required dynamic details,
    String? userId,
    String? deviceId,
  }) async {
    final currentUserId = userId ?? SupasService.instance.userId ?? 'anonymous';
    final currentDeviceId = deviceId ?? await DeviceIdentity.getDeviceId();
    final logId = DatabaseHelper.generateUUID();
    final nowIso = DateTime.now().toUtc().toIso8601String();

    Map<String, dynamic> detailsMap = {};
    if (details is Map) {
      detailsMap = Map<String, dynamic>.from(details);
    } else if (details != null) {
      detailsMap = {'message': details.toString()};
    }

    final auditItem = AuditLogItem(
      id: logId,
      userId: currentUserId,
      action: action,
      details: detailsMap,
      timestamp: nowIso,
      deviceId: currentDeviceId,
      isDirty: true,
    );

    // 1. Dual Write: Save to local SQLite cache first (instantly available for UI)
    await DatabaseHelper.instance.saveAuditLog(auditItem.toMap());
    refresh();

    // 2. Dual Write: Attempt Cloud Push if online
    try {
      if (SupasService.instance.userId != null) {
        await SupasService.instance.client
            .from('audit_logs')
            .upsert(auditItem.toCloudMap(), onConflict: 'id');

        // Mark local record as synced (is_dirty = 0)
        await DatabaseHelper.instance.clearDirtyAuditLogs([logId]);
        refresh();
      }
    } catch (e) {
      if (e.toString().contains('PGRST205') || e.toString().contains('PGRST204')) {
        debugPrint('AuditService: public.audit_logs table not in Supabase schema (audit log preserved locally).');
      } else {
        debugPrint('AuditService: Cloud push deferred for offline log $logId: $e');
      }
    }

    return auditItem;
  }

  /// Fetches audit logs from local SQLite
  Future<List<AuditLogItem>> getAuditLogs({String? action, int limit = 100}) async {
    final rawList = await DatabaseHelper.instance.getAuditLogs(action: action, limit: limit);
    return rawList.map((m) => AuditLogItem.fromMap(m)).toList();
  }

  /// Triggers a refresh on the stream controller
  Future<void> refresh() async {
    try {
      final logs = await getAuditLogs();
      if (!_logsController.isClosed) {
        _logsController.add(logs);
      }
    } catch (e) {
      debugPrint('AuditService refresh error: $e');
    }
  }

  /// Push all local un-synced audit logs to cloud
  Future<void> syncPendingAuditLogs() async {
    if (SupasService.instance.userId == null) return;
    try {
      final dirtyLogs = await DatabaseHelper.instance.getDirtyAuditLogs();
      if (dirtyLogs.isEmpty) return;

      final cloudPayload = dirtyLogs.map((logMap) {
        final item = AuditLogItem.fromMap(logMap);
        return item.toCloudMap();
      }).toList();

      await SupasService.instance.client.from('audit_logs').upsert(cloudPayload, onConflict: 'id');

      final syncedIds = dirtyLogs.map((e) => e['id'].toString()).toList();
      await DatabaseHelper.instance.clearDirtyAuditLogs(syncedIds);
      await refresh();
    } catch (e) {
      if (e.toString().contains('PGRST205') || e.toString().contains('PGRST204')) {
        debugPrint('AuditService: public.audit_logs table not in Supabase schema (audit logs preserved locally).');
      } else {
        debugPrint('AuditService syncPendingAuditLogs error: $e');
      }
    }
  }

  /// Upserts records pulled from Cloud into local SQLite
  Future<void> upsertCloudAuditLogs(List<Map<String, dynamic>> cloudLogs) async {
    if (cloudLogs.isEmpty) return;
    await DatabaseHelper.instance.upsertCloudAuditLogs(cloudLogs);
    await refresh();
  }
}
