import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database_helper.dart';
import 'passcode_service.dart';
import 'logger_service.dart';
import 'audit_service.dart';
import 'notification_service.dart';
import 'powersync/device_identity.dart';

class SessionConflictInfo {
  final String activeDeviceId;
  final String activeDeviceName;
  final String lastActive;

  SessionConflictInfo({
    required this.activeDeviceId,
    required this.activeDeviceName,
    required this.lastActive,
  });
}

enum SyncStatus { idle, syncing, synced, error, offline }

/// Represents the live connection status of the desktop application.
/// - [online]  : desktop heartbeat seen within the last 30 seconds
/// - [offline] : heartbeat is stale (>30s ago)
/// - [checking]: status not yet determined (initial state)
/// - [unknown] : user has never run the desktop app (no heartbeat field)
enum DesktopStatus { online, offline, checking, unknown }


class SupasService {
  static final SupasService _instance = SupasService._privateConstructor();
  static SupasService get instance => _instance;

  SupasService._privateConstructor() {
    client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.tokenRefreshed || event == AuthChangeEvent.signedIn) {
        if (userId != null) {
          _restartRealtime();
        }
      } else if (event == AuthChangeEvent.signedOut) {
        _realtimeChannel?.unsubscribe();
        _realtimeChannel = null;
      }
    });
  }

  final SupabaseClient client = Supabase.instance.client;
  final ValueNotifier<SyncStatus> syncStatus = ValueNotifier(SyncStatus.idle);
  final ValueNotifier<Map<String, dynamic>?> userMetadata = ValueNotifier(null);

  /// Live status of the desktop application, polled every 15 seconds.
  final ValueNotifier<DesktopStatus> desktopStatus = ValueNotifier(DesktopStatus.checking);

  // Sign In
  Future<AuthResponse> signIn(String email, String password) async {
    return await client.auth.signInWithPassword(email: email, password: password);
  }

  // Sign Out
  Future<void> signOut() async {
    await client.auth.signOut();
  }

  // Get Current User ID
  String? get userId => client.auth.currentUser?.id;

  final ValueNotifier<bool> sessionRevokedNotif = ValueNotifier(false);

  /// Checks if an active session exists for the user on another device of the given category
  Future<SessionConflictInfo?> checkSessionConflict(String targetUserId, {String category = 'mobile'}) async {
    try {
      final currentDeviceId = await DeviceIdentity.getDeviceId();
      final res = await client
          .from('user_sessions')
          .select()
          .eq('user_id', targetUserId)
          .maybeSingle();

      if (res != null) {
        final String? activeId = category == 'mobile'
            ? res['active_mobile_device_id']?.toString()
            : res['active_desktop_device_id']?.toString();
        final String? activeName = category == 'mobile'
            ? res['active_mobile_device_name']?.toString()
            : res['active_desktop_device_name']?.toString();
        final String? lastActive = category == 'mobile'
            ? res['active_mobile_last_active']?.toString()
            : res['active_desktop_last_active']?.toString();

        if (activeId != null && activeId.isNotEmpty && activeId != currentDeviceId) {
          return SessionConflictInfo(
            activeDeviceId: activeId,
            activeDeviceName: activeName ?? (category == 'mobile' ? 'Another Mobile Device' : 'Another Desktop Device'),
            lastActive: lastActive ?? 'recently',
          );
        }
      }
    } catch (e) {
      AppLogger.warning('SESSION CONFLICT CHECK: Note $e', tag: 'SupasService');
    }
    return null;
  }

  /// Registers or force-switches the active session slot for the current device
  Future<void> registerSession(String targetUserId, {String category = 'mobile', bool force = false}) async {
    try {
      final currentDeviceId = await DeviceIdentity.getDeviceId();
      final deviceName = category == 'mobile' ? 'Mobile App (${Platform.operatingSystem})' : 'Desktop PC';
      final nowIso = DateTime.now().toUtc().toIso8601String();

      final Map<String, dynamic> updateData = {
        'user_id': targetUserId,
        'updated_at': nowIso,
      };

      if (category == 'mobile') {
        updateData['active_mobile_device_id'] = currentDeviceId;
        updateData['active_mobile_device_name'] = deviceName;
        updateData['active_mobile_last_active'] = nowIso;
      } else {
        updateData['active_desktop_device_id'] = currentDeviceId;
        updateData['active_desktop_device_name'] = deviceName;
        updateData['active_desktop_last_active'] = nowIso;
      }

      await client.from('user_sessions').upsert(updateData, onConflict: 'user_id');
      AppLogger.info('SESSION: Registered $category session slot for device $currentDeviceId (force=$force)', tag: 'SupasService');

      if (force) {
        await AuditService.instance.logAction(
          action: 'SECURITY_ALERT',
          details: 'Session force-switched to current $category device ($currentDeviceId). Old session revoked.',
        );
      }
    } catch (e) {
      AppLogger.error('SESSION REGISTER ERROR: $e', tag: 'SupasService');
    }
  }

  /// Verifies if the current device session is still active and valid in user_sessions
  Future<bool> verifyCurrentSessionValid() async {
    if (userId == null) return true;
    try {
      final currentDeviceId = await DeviceIdentity.getDeviceId();
      final res = await client
          .from('user_sessions')
          .select('active_mobile_device_id')
          .eq('user_id', userId!)
          .maybeSingle();

      if (res != null) {
        final String? activeId = res['active_mobile_device_id']?.toString();
        if (activeId != null && activeId.isNotEmpty && activeId != currentDeviceId) {
          AppLogger.warning('SESSION REVOKED: Device $currentDeviceId superseded by $activeId', tag: 'SupasService');
          return false;
        }
      }
    } catch (_) {}
    return true;
  }

  /// Executes an API call with automatic auth token refresh on 401 Unauthorized errors
  Future<T> executeWithAuthRetry<T>(Future<T> Function() apiCall) async {
    try {
      return await apiCall();
    } on AuthException catch (e) {
      if (e.statusCode == '401' ||
          e.message.toLowerCase().contains('jwt') ||
          e.message.toLowerCase().contains('expired') ||
          e.message.toLowerCase().contains('unauthorized')) {
        try {
          AppLogger.info('AUTH RETRY: Token expired or 401. Refreshing session...', tag: 'SupasService');
          await client.auth.refreshSession();
          return await apiCall();
        } on AuthApiException catch (refreshError) {
          final msg = refreshError.message.toLowerCase();
          if (refreshError.statusCode == '400' ||
              refreshError.code == 'invalid_grant' ||
              msg.contains('invalid refresh token') ||
              msg.contains('refresh_token_not_found')) {
            AppLogger.error('AUTH RETRY: Refresh token explicitly invalid.', tag: 'SupasService', error: refreshError);
            rethrow;
          }
          rethrow;
        } catch (err) {
          AppLogger.warning('AUTH RETRY: Session refresh failed due to network/system: $err', tag: 'SupasService');
          rethrow;
        }
      }
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  // Sync Logic (Mirroring Java syncOnLogin)
  bool _isSyncing = false;

  Future<void> syncDatabase({bool isManual = false}) async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      if (userId == null) return;

      final sessionValid = await verifyCurrentSessionValid();
      if (!sessionValid) {
        AppLogger.warning('SYNC CANCELLED: Session ended on another mobile device.', tag: 'SupasService');
        sessionRevokedNotif.value = true;
        await signOut();
        syncStatus.value = SyncStatus.error;
        return;
      }

      syncStatus.value = SyncStatus.syncing;
      AppLogger.info('SYNC: Starting Delta Sync for user $userId', tag: 'SupasService');
      
      await DatabaseHelper.instance.checkAutoResyncMigration();

      initializeRealtime();

      // 1. PUSH local changes to Postgres
      final dirtyStock = await DatabaseHelper.instance.getDirtyStock();
      AppLogger.info('SYNC: PUSHING dirty stock: ${dirtyStock.length} items', tag: 'SupasService');
      if (dirtyStock.isNotEmpty) {
          final nowIso = DateTime.now().toUtc().toIso8601String();
          final mapped = dirtyStock.map((e) => {...e, 'user_id': userId, 'updated_at': nowIso}).toList();
          await client.from('stock').upsert(mapped, onConflict: 'sync_id');
      }

      final dirtySales = await DatabaseHelper.instance.getDirtySales();
      AppLogger.info('SYNC: PUSHING dirty sales: ${dirtySales.length} items', tag: 'SupasService');
      if (dirtySales.isNotEmpty) {
          final nowIso = DateTime.now().toUtc().toIso8601String();
          final mapped = dirtySales.map((e) => {...e, 'user_id': userId, 'updated_at': nowIso}).toList();
          await client.from('sales').upsert(mapped, onConflict: 'sync_id');
      }

      await DatabaseHelper.instance.cleanupZombieStock();

      final deletedStock = await DatabaseHelper.instance.getDirtyDeletedStock();
      AppLogger.info('SYNC: PUSHING dirty deleted stock: ${deletedStock.length} items', tag: 'SupasService');
      if (deletedStock.isNotEmpty) {
          for (var item in deletedStock) {
            final String? syncId = item['sync_id']?.toString();
            final String? itemName = item['item']?.toString();
            final String? quantity = item['quantity']?.toString();

            if (syncId != null && syncId.isNotEmpty) {
              await client.from('stock').delete().eq('sync_id', syncId);
            }
            if (itemName != null && itemName.isNotEmpty && quantity != null && quantity.isNotEmpty) {
              await client.from('stock').delete().eq('item', itemName).eq('quantity', quantity);
            }
          }
      }

      final deletedHistory = await DatabaseHelper.instance.getDirtyDeletedHistory();
      AppLogger.info('SYNC: PUSHING dirty deleted sales: ${deletedHistory.length} items', tag: 'SupasService');
      if (deletedHistory.isNotEmpty) {
          for (var item in deletedHistory) {
            final String? syncId = item['sync_id']?.toString();
            final String? customer = item['customer']?.toString();
            final String? itemName = item['item']?.toString();
            final dynamic amount = item['amount'];
            final String? date = item['date']?.toString();

            if (syncId != null && syncId.isNotEmpty) {
              await client.from('sales').delete().eq('sync_id', syncId);
            }
            if (itemName != null && itemName.isNotEmpty && date != null && date.isNotEmpty) {
              var query = client.from('sales').delete().eq('item', itemName).eq('date', date);
              if (customer != null && customer.isNotEmpty && customer != 'Walk-in Customer') {
                query = query.eq('customer', customer);
              }
              if (amount != null && amount.toString().isNotEmpty) {
                query = query.eq('amount', amount);
              }
              await query;
            }
          }
      }

      await DatabaseHelper.instance.clearDirtyFlags();

      // PUSH pending audit logs and notifications to cloud
      await AuditService.instance.syncPendingAuditLogs();
      await NotificationService.instance.syncPendingNotifications();

      // 2. PULL remote changes from Postgres
      final localVersionStr = await DatabaseHelper.instance.getSetting('last_backup_timestamp');
      final localVersionTs = int.tryParse(localVersionStr ?? '0') ?? 0;
      final queryTs = localVersionTs > 300000 ? localVersionTs - 300000 : 0;
      final isoTs = DateTime.fromMillisecondsSinceEpoch(queryTs).toUtc().toIso8601String();
      AppLogger.info('SYNC: PULLING remote changes since $isoTs (original TS: $localVersionTs)', tag: 'SupasService');

      // Pull stock
      var stockQuery = client.from('stock').select();
      if (localVersionTs > 0 && !isManual) {
          stockQuery = stockQuery.gt('updated_at', isoTs);
      }
      final cloudStock = await stockQuery;
      AppLogger.info('SYNC: PULLED remote stock: ${cloudStock.length} items', tag: 'SupasService');
      // Only accept cloud available_pieces on manual/first sync to correct drift.
      // During incremental sync, delta merge from sales handles stock adjustments.
      bool acceptPieces = isManual || localVersionTs == 0;
      await DatabaseHelper.instance.upsertCloudStock(cloudStock, forceAcceptPieces: acceptPieces);

      // Pull sales (Full Sync for sales to reconcile deletions across all devices)
      final cloudSales = await client.from('sales').select();
      AppLogger.info('SYNC: PULLED remote sales: ${cloudSales.length} items', tag: 'SupasService');
      await DatabaseHelper.instance.upsertCloudSales(cloudSales, false); // false = Full Sync

      // Pull cloud audit logs
      try {
        final cloudAuditLogs = await client.from('audit_logs').select().eq('user_id', userId!);
        AppLogger.info('SYNC: PULLED remote audit logs: ${cloudAuditLogs.length} items', tag: 'SupasService');
        await AuditService.instance.upsertCloudAuditLogs(List<Map<String, dynamic>>.from(cloudAuditLogs));
      } catch (e) {
        AppLogger.info('SYNC: Cloud audit logs pull note: $e', tag: 'SupasService');
      }

      // Pull cloud notifications
      try {
        final cloudNotifs = await client.from('notifications').select().eq('user_id', userId!);
        AppLogger.info('SYNC: PULLED remote notifications: ${cloudNotifs.length} items', tag: 'SupasService');
        await NotificationService.instance.upsertCloudNotifications(List<Map<String, dynamic>>.from(cloudNotifs));
      } catch (e) {
        AppLogger.info('SYNC: Cloud notifications pull note: $e', tag: 'SupasService');
      }

      // We do not have a deleted_stock/deleted_sales table on cloud so physical deletions are hard to pull incrementally.
      // However, Realtime will push deletions instantly while online.
      
      final ts = DateTime.now().millisecondsSinceEpoch;
      await DatabaseHelper.instance.saveSetting('last_backup_timestamp', ts.toString());
      await client.from('users').update({'last_backup_timestamp': ts}).eq('id', userId!);

      // Push local receipt settings to cloud (ensures settings saved before this update get synced)
      final shopName = await DatabaseHelper.instance.getSetting('receipt_shop_name');
      if (shopName != null && shopName.isNotEmpty) {
        await uploadReceiptSettings();
      }

      _lastKnownCloudTimestamp = ts;
      syncStatus.value = SyncStatus.synced;

      // Pull receipt settings from cloud (in case saved from desktop/other device)
      await downloadReceiptSettings();

      AppLogger.info('SYNC: Finished successfully!', tag: 'SupasService');
    } on SocketException catch (e) {
      AppLogger.warning('SYNC OFFLINE: Socket error during database sync: $e', tag: 'SupasService');
      syncStatus.value = SyncStatus.offline;
    } on AuthApiException catch (e) {
      AppLogger.error('SYNC AUTH ERROR (${e.code}): ${e.message}', tag: 'SupasService');
      syncStatus.value = SyncStatus.error;
    } catch (e, stack) {
      AppLogger.error('SYNC ERROR: $e', tag: 'SupasService', error: e, stackTrace: stack);
      syncStatus.value = SyncStatus.error;
    } finally {
      _isSyncing = false;
    }
  }

  // Deprecated wrapper for backward compatibility
  Future<void> uploadDatabase() async {
      await syncDatabase();
  }

  /// Uploads local receipt settings to Supabase Storage as settings.json
  Future<void> uploadReceiptSettings() async {
    if (userId == null) return;
    try {
      final db = DatabaseHelper.instance;
      final settings = {
        'receipt_shop_name': await db.getSetting('receipt_shop_name') ?? '',
        'receipt_shop_number': await db.getSetting('receipt_shop_number') ?? '',
        'receipt_location': await db.getSetting('receipt_location') ?? '',
        'receipt_phone': await db.getSetting('receipt_phone') ?? '',
        'receipt_phone2': await db.getSetting('receipt_phone2') ?? '',
        'passcode': await db.getSetting('passcode') ?? '',
      };

      final jsonBytes = utf8.encode(jsonEncode(settings));
      final storagePath = '$userId/settings.json';

      await client.storage.from('backups').uploadBinary(
        storagePath,
        Uint8List.fromList(jsonBytes),
        fileOptions: const FileOptions(upsert: true, contentType: 'application/json'),
      );
      AppLogger.info('SETTINGS UPLOAD: Success', tag: 'SupasService');
      invalidateSettingsCache();
    } catch (e, stack) {
      AppLogger.error('SETTINGS UPLOAD ERROR: $e', tag: 'SupasService', error: e, stackTrace: stack);
    }
  }

  int _lastSettingsCheckTime = 0;

  void invalidateSettingsCache() {
    _lastSettingsCheckTime = 0;
  }

  /// Downloads receipt settings from Supabase Storage and saves locally
  Future<void> downloadReceiptSettings() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSettingsCheckTime < 600000) {
      return;
    }
    _lastSettingsCheckTime = now;
    if (userId == null) return;
    try {
      final storagePath = '$userId/settings.json';
      final bytes = await client.storage.from('backups').download(storagePath);
      final jsonStr = utf8.decode(bytes);
      final settings = jsonDecode(jsonStr) as Map<String, dynamic>;

      final db = DatabaseHelper.instance;
      final keys = ['receipt_shop_name', 'receipt_shop_number', 'receipt_location', 'receipt_phone', 'receipt_phone2', 'passcode'];
      bool passcodeUpdated = false;
      for (final key in keys) {
        if (settings.containsKey(key)) {
          final cloudVal = settings[key]?.toString() ?? '';
          final localVal = await db.getSetting(key);
          
          if (key == 'passcode') {
            if (cloudVal != localVal && (cloudVal.isNotEmpty || localVal == null || localVal.isEmpty)) {
              await db.saveSetting(key, cloudVal);
              passcodeUpdated = true;
            }
          } else {
            // Accept cloud value if local is empty/null
            if (cloudVal.isNotEmpty && (localVal == null || localVal.isEmpty)) {
              await db.saveSetting(key, cloudVal);
            }
            // If local has never been set, always accept cloud
            if (localVal == null) {
              await db.saveSetting(key, cloudVal);
            }
          }
        }
      }
      if (passcodeUpdated) {
        await PasscodeService.instance.init();
      }
      AppLogger.info('SETTINGS DOWNLOAD: Applied receipt settings from cloud', tag: 'SupasService');
    } catch (e) {
      AppLogger.info('SETTINGS DOWNLOAD: No settings found or info: $e', tag: 'SupasService');
    }
  }

  Future<void> ensureUserMetadataExists(String email) async {
    if (userId == null) return;
    try {
      final meta = await refreshUserMetadata();
      if (meta != null) return; // Already exists

      await client.from('users').insert({
        'id': userId,
        'email': email,
        'ownership_payment': false,
        'ownership_expiry': 0,
        'monthly_cloud_backup': true,
        'backup_expiry': 0,
      });
      AppLogger.info('SYNC: Created user metadata', tag: 'SupasService');
      await refreshUserMetadata();
    } catch (e, stack) {
       AppLogger.error('METADATA ERROR: $e', tag: 'SupasService', error: e, stackTrace: stack);
    }
  }

  Future<void> migrateLegacyDatabase() async {
    // Disabled legacy un-partitioned database copying to prevent cross-account inventory leaks
    return;
  }

  String generateUniqueCheckbookId() {
    final random = Random();
    final digits = List.generate(6, (_) => random.nextInt(10)).join();
    return 'CK-$digits';
  }

  Future<Map<String, dynamic>?> refreshUserMetadata() async {
      if (userId == null) return null;
      try {
        final meta = await client.from('users').select().eq('id', userId!).maybeSingle() ?? <String, dynamic>{};
        
        String? checkbookId = client.auth.currentUser?.userMetadata?['checkbook_id'] as String?;
        if (checkbookId == null || checkbookId.isEmpty || checkbookId.contains('*')) {
          try {
            final profile = await client.from('user_profiles').select('checkbook_id').eq('user_id', userId!).maybeSingle();
            if (profile != null && profile['checkbook_id'] != null && !(profile['checkbook_id'] as String).contains('*')) {
              checkbookId = profile['checkbook_id'] as String;
            }
          } catch (_) {}
        }

        // If checkbookId is still unassigned or contains literal asterisks, generate dynamic 6-digit ID
        if (checkbookId == null || checkbookId.isEmpty || checkbookId.contains('*')) {
          checkbookId = generateUniqueCheckbookId();
          try {
            await client.from('users').upsert({
              'id': userId,
              'checkbook_id': checkbookId,
            }, onConflict: 'id');
          } catch (e) {
            try {
              await client.from('user_profiles').upsert({
                'user_id': userId,
                'checkbook_id': checkbookId,
                'updated_at': DateTime.now().toIso8601String(),
              }, onConflict: 'user_id');
            } catch (_) {}
          }
        }

        // Ensure checkbook_id is synced to Supabase Auth metadata
        try {
          await client.auth.updateUser(UserAttributes(data: {'checkbook_id': checkbookId}));
        } catch (_) {}

        meta['checkbook_id'] = checkbookId;
        userMetadata.value = meta;
        return meta;
      } catch (e, stack) {
        AppLogger.error('REFRESH METADATA ERROR: $e', tag: 'SupasService', error: e, stackTrace: stack);
        return null;
      }
  }
  
  Future<String> _getLocalDbPath() async {
      return await DatabaseHelper.instance.getDbPath();
  }

  /// Permanently deletes the cloud backup and resets metadata.
  Future<void> wipeCloudData() async {
      if (userId == null) return;
      try {
          syncStatus.value = SyncStatus.syncing;
          
          final dbPath = await _getLocalDbPath();
          final fileName = dbPath.split(Platform.pathSeparator).last;
          
          // 1. Delete storage files
          try {
              await client.storage.from('backups').remove(['$userId/$fileName']);
              await client.storage.from('backups').remove(['$userId/inventory.db']); // legacy
          } catch (e) {
              debugPrint('CLOUDWIPE STORAGE: $e');
          }

          // 2. Reset cloud metadata
          await client.from('users').update({
              'last_backup_timestamp': 0,
          }).eq('id', userId!);

          AppLogger.info('CLOUDWIPE: Cloud data successfully cleared.', tag: 'SupasService');
          syncStatus.value = SyncStatus.synced;
      } catch (e, stack) {
          AppLogger.error('CLOUDWIPE ERROR: $e', tag: 'SupasService', error: e, stackTrace: stack);
          syncStatus.value = SyncStatus.error;
      }
  }

  // --- PUSH-TO-LOGIN ---

  Stream<List<Map<String, dynamic>>> getLoginRequestsStream() {
    final email = client.auth.currentUser?.email;
    if (userId == null || email == null) return const Stream.empty();
    
    // Note: RLS should already filter by email. 
    // We filter by status='pending' here manually to avoid .eq() build issues.
    return client
        .from('login_requests')
        .stream(primaryKey: ['id'])
        .map((list) => list.where((item) => item['status'] == 'pending').toList());
  }

  /// Direct HTTP poll for pending login requests (AJAX-style fallback).
  /// This works even if the Realtime WebSocket has gone stale.
  Future<List<Map<String, dynamic>>> fetchPendingLoginRequests() async {
    final email = client.auth.currentUser?.email;
    final currentUid = userId;
    if (currentUid == null) return [];

    try {
      final List<dynamic> result = await client
          .from('login_requests')
          .select();

      final myCheckbookId = userMetadata.value?['checkbook_id'] as String? ??
          client.auth.currentUser?.userMetadata?['checkbook_id'] as String?;
      final formattedMyCid = myCheckbookId?.trim().toUpperCase();
      final formattedEmail = email?.trim().toLowerCase();

      final now = DateTime.now();
      return result
          .cast<Map<String, dynamic>>()
          .where((item) {
            final st = (item['status'] ?? '').toString().toLowerCase();
            if (st != 'pending') return false;

            final itemEmail = (item['email'] ?? item['user_email'] ?? '').toString().trim();
            final itemEmailLower = itemEmail.toLowerCase();
            final itemEmailUpper = itemEmail.toUpperCase();

            // Match if email equals user email, or equals checkbook ID, or if item email is a CK- request
            final isMatch = (formattedEmail != null && itemEmailLower == formattedEmail) ||
                (formattedMyCid != null && itemEmailUpper == formattedMyCid) ||
                (formattedMyCid != null && itemEmailUpper.contains(formattedMyCid)) ||
                itemEmailUpper.startsWith('CK-');

            if (!isMatch) return false;

            final expStr = item['created_at']?.toString();
            if (expStr != null) {
              final created = DateTime.tryParse(expStr);
              if (created != null && now.difference(created).inMinutes > 5) return false;
            }

            return true;
          })
          .toList();
    } catch (e) {
      debugPrint('LOGIN POLL ERROR: $e');
      return [];
    }
  }

  Future<void> updateLoginRequestStatus(String requestId, String status) async {
    final lowercaseStatus = status.toLowerCase(); // 'approved' or 'rejected'
    final uppercaseStatus = status.toUpperCase(); // 'APPROVED' or 'REJECTED'
    final session = client.auth.currentSession;
    final accToken = session?.accessToken ?? '';
    final refToken = session?.refreshToken ?? '';
    final tokenPayload = '$accToken:::$refToken';

    // 1. Update login_requests with schema-valid columns only
    try {
      await client.from('login_requests').update({
        'status': lowercaseStatus,
        'refresh_token': tokenPayload,
      }).eq('id', requestId);
    } catch (e) {
      debugPrint('Error updating login_requests status: $e');
    }

    // 2. Try device_pairing_requests table fallback
    try {
      await client.from('device_pairing_requests').update({
        'status': uppercaseStatus,
        'pairing_token': tokenPayload,
        'refresh_token': tokenPayload,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', requestId);
    } catch (_) {}
  }

  // --- REMOTE DATA CHANGE DETECTION ---

  int _lastKnownCloudTimestamp = 0;

  /// Check if the remote database has been updated by another app (desktop/mobile).
  /// Returns true if new data was detected and downloaded.
  Future<bool> checkForRemoteChanges() async {
    if (userId == null) return false;

    try {
      final meta = await client.from('users').select('last_backup_timestamp').eq('id', userId!).maybeSingle();
      if (meta == null) return false;

      final val = meta['last_backup_timestamp'];
      final cloudTs = val is int ? val : (val is num ? val.toInt() : (val is String ? (int.tryParse(val) ?? 0) : 0));

      final localVersionStr = await DatabaseHelper.instance.getSetting('last_backup_timestamp');
      final localVersionTs = int.tryParse(localVersionStr ?? '0') ?? 0;

      // If cloud timestamp is newer than our local database version, another app uploaded
      if (cloudTs > localVersionTs) {
        AppLogger.info('SYNC POLL: Remote change detected! Cloud=$cloudTs, Local=$localVersionTs', tag: 'SupasService');
        await syncDatabase();
        return true;
      }

      return false;
    } catch (e, stack) {
      AppLogger.error('SYNC POLL ERROR: $e', tag: 'SupasService', error: e, stackTrace: stack);
      return false;
    }
  }

  /// Call this after a successful upload to update the cached timestamp
  void updateLastKnownTimestamp(int ts) {
    _lastKnownCloudTimestamp = ts;
  }

  int get lastKnownCloudTimestamp => _lastKnownCloudTimestamp;

  /// Polls `desktop_last_seen` from the users table and updates [desktopStatus].
  ///
  /// Returns the newly computed [DesktopStatus] so the caller can fire
  /// local notifications on state transitions.
  ///
  /// Thresholds:
  ///   - `desktop_last_seen` null/0  → [DesktopStatus.unknown]
  ///   - last seen ≤ 30 seconds ago  → [DesktopStatus.online]
  ///   - last seen > 30 seconds ago  → [DesktopStatus.offline]
  Future<DesktopStatus> checkDesktopPresence() async {
    if (userId == null) return DesktopStatus.unknown;
    try {
      final row = await client
          .from('users')
          .select('desktop_last_seen')
          .eq('id', userId!)
          .maybeSingle();

      if (row == null) {
        desktopStatus.value = DesktopStatus.unknown;
        return DesktopStatus.unknown;
      }

      final lastSeen = row['desktop_last_seen'];
      if (lastSeen == null || (lastSeen is num && lastSeen == 0)) {
        desktopStatus.value = DesktopStatus.unknown;
        return DesktopStatus.unknown;
      }

      final lastSeenMs = (lastSeen as num).toInt();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final staleMs = nowMs - lastSeenMs;

      // Online if heartbeat within 30 seconds
      final newStatus = staleMs <= 30000 ? DesktopStatus.online : DesktopStatus.offline;
      desktopStatus.value = newStatus;
      return newStatus;
    } catch (e, stack) {
      AppLogger.error('DESKTOP PRESENCE ERROR: $e', tag: 'SupasService', error: e, stackTrace: stack);
      // Don't change status on network error — keep last known value
      return desktopStatus.value;
    }
  }

  RealtimeChannel? _realtimeChannel;

  void _restartRealtime() {
    if (_realtimeChannel != null) {
      client.removeChannel(_realtimeChannel!);
      _realtimeChannel = null;
    }
    initializeRealtime();
  }

  void initializeRealtime() {
    if (userId == null || _realtimeChannel != null) return;

    AppLogger.info('REALTIME: Subscribing to Postgres changes...', tag: 'SupasService');
    try {
      _realtimeChannel = client
          .channel('public:user_data_$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'audit_logs',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: userId!),
            callback: (payload) async {
              AppLogger.info('REALTIME AUDIT EVENT: ${payload.eventType}', tag: 'SupasService');
              if (payload.newRecord.isNotEmpty) {
                await AuditService.instance.upsertCloudAuditLogs([payload.newRecord]);
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'notifications',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'user_id', value: userId!),
            callback: (payload) async {
              AppLogger.info('REALTIME NOTIFICATION EVENT: ${payload.eventType}', tag: 'SupasService');
              if (payload.newRecord.isNotEmpty) {
                await NotificationService.instance.upsertCloudNotifications([payload.newRecord]);
              }
            },
          )
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            callback: (payload) {
               AppLogger.info('REALTIME EVENT: ${payload.eventType} on ${payload.table}', tag: 'SupasService');
               syncDatabase();
            },
          )
          .subscribe((status, [error]) {
             if (status == RealtimeSubscribeStatus.closed || status == RealtimeSubscribeStatus.channelError) {
                AppLogger.warning('REALTIME STATUS: $status, ERROR: $error', tag: 'SupasService');
                _realtimeChannel = null;
             }
          });
    } catch (e, stack) {
      AppLogger.error('REALTIME INIT ERROR: $e', tag: 'SupasService', error: e, stackTrace: stack);
      _realtimeChannel = null;
    }
  }

  /// Checks for active pending desktop device pairing requests for the current user
  Future<Map<String, dynamic>?> checkPendingPairingRequests() async {
    if (userId == null) return null;
    final nowIso = DateTime.now().toIso8601String();

    // 1. Try device_pairing_requests table
    try {
      final result = await client
          .from('device_pairing_requests')
          .select()
          .eq('user_id', userId!)
          .eq('status', 'PENDING')
          .gt('expires_at', nowIso)
          .maybeSingle();
      if (result != null) return result;
    } catch (_) {}

    // 2. Try login_requests table fallback
    try {
      final result = await client
          .from('login_requests')
          .select()
          .eq('user_id', userId!)
          .eq('status', 'PENDING')
          .gt('expires_at', nowIso)
          .maybeSingle();
      if (result != null) return result;
    } catch (_) {}

    return null;
  }

  /// Responds to a desktop device pairing request (ACCEPT or REJECT)
  Future<bool> respondPairingRequest(String sessionId, String action) async {
    final lowercaseStatus = (action.toUpperCase() == 'ACCEPT' || action.toUpperCase() == 'APPROVED') ? 'approved' : 'rejected';
    final uppercaseStatus = lowercaseStatus.toUpperCase();

    final session = client.auth.currentSession;
    final accToken = session?.accessToken ?? '';
    final refToken = session?.refreshToken ?? '';
    final tokenPayload = '$accToken:::$refToken';

    // 1. Try RPC rpc_respond_pairing_request
    try {
      final res = await client.rpc('rpc_respond_pairing_request', params: {
        'p_session_id': sessionId,
        'p_action': action,
      });
      if (res != null && (res['success'] == true || res['status'] == uppercaseStatus || res['status'] == lowercaseStatus)) {
        return true;
      }
    } catch (_) {}

    // 2. Direct update on login_requests with schema-valid columns
    try {
      await client.from('login_requests').update({
        'status': lowercaseStatus,
        'refresh_token': tokenPayload,
      }).eq('id', sessionId);
      return true;
    } catch (e) {
      debugPrint('Error updating login_requests in respondPairingRequest: $e');
    }

    // 3. Direct update on device_pairing_requests fallback
    try {
      await client.from('device_pairing_requests').update({
        'status': uppercaseStatus,
        'pairing_token': tokenPayload,
        'refresh_token': tokenPayload,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', sessionId);
      return true;
    } catch (_) {}

    return false;
  }
}
