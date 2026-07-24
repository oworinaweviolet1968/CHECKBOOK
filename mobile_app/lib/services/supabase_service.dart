import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'database_helper.dart';
import 'passcode_service.dart';

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

  // Sync Logic (Mirroring Java syncOnLogin)
  bool _isSyncing = false;

  Future<void> syncDatabase({bool isManual = false}) async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      if (userId == null) return;
      syncStatus.value = SyncStatus.syncing;
      print('SYNC: Starting Delta Sync for user $userId');
      
      initializeRealtime();

      // 1. PUSH local changes to Postgres
      final dirtyStock = await DatabaseHelper.instance.getDirtyStock();
      print('SYNC: PUSHING dirty stock: ${dirtyStock.length} items');
      if (dirtyStock.isNotEmpty) {
          final nowIso = DateTime.now().toUtc().toIso8601String();
          final mapped = dirtyStock.map((e) => {...e, 'user_id': userId, 'updated_at': nowIso}).toList();
          await client.from('stock').upsert(mapped, onConflict: 'sync_id');
      }

      final dirtySales = await DatabaseHelper.instance.getDirtySales();
      print('SYNC: PUSHING dirty sales: ${dirtySales.length} items');
      if (dirtySales.isNotEmpty) {
          final nowIso = DateTime.now().toUtc().toIso8601String();
          final mapped = dirtySales.map((e) => {...e, 'user_id': userId, 'updated_at': nowIso}).toList();
          await client.from('sales').upsert(mapped, onConflict: 'sync_id');
      }

      final deletedStock = await DatabaseHelper.instance.getDirtyDeletedStock();
      print('SYNC: PUSHING dirty deleted stock: ${deletedStock.length} items');
      if (deletedStock.isNotEmpty) {
          final ids = deletedStock.map((e) => e['sync_id']).toList();
          await client.from('stock').delete().inFilter('sync_id', ids);
      }

      final deletedHistory = await DatabaseHelper.instance.getDirtyDeletedHistory();
      print('SYNC: PUSHING dirty deleted sales: ${deletedHistory.length} items');
      if (deletedHistory.isNotEmpty) {
          final ids = deletedHistory.map((e) => e['sync_id']).toList();
          await client.from('sales').delete().inFilter('sync_id', ids);
      }

      await DatabaseHelper.instance.clearDirtyFlags();

      // 2. PULL remote changes from Postgres
      final localVersionStr = await DatabaseHelper.instance.getSetting('last_backup_timestamp');
      final localVersionTs = int.tryParse(localVersionStr ?? '0') ?? 0;
      final queryTs = localVersionTs > 300000 ? localVersionTs - 300000 : 0;
      final isoTs = DateTime.fromMillisecondsSinceEpoch(queryTs).toUtc().toIso8601String();
      print('SYNC: PULLING remote changes since $isoTs (original TS: $localVersionTs)');

      // Pull stock
      var stockQuery = client.from('stock').select();
      if (localVersionTs > 0 && !isManual) {
          stockQuery = stockQuery.gt('updated_at', isoTs);
      }
      final cloudStock = await stockQuery;
      print('SYNC: PULLED remote stock: ${cloudStock.length} items');
      // Only accept cloud available_pieces on manual/first sync to correct drift.
      // During incremental sync, delta merge from sales handles stock adjustments.
      bool acceptPieces = isManual || localVersionTs == 0;
      await DatabaseHelper.instance.upsertCloudStock(cloudStock, forceAcceptPieces: acceptPieces);

      // Pull sales
      var salesQuery = client.from('sales').select();
      if (localVersionTs > 0 && !isManual) {
          salesQuery = salesQuery.gt('updated_at', isoTs);
      }
      final cloudSales = await salesQuery;
      print('SYNC: PULLED remote sales: ${cloudSales.length} items');
      bool isIncremental = localVersionTs > 0;
      await DatabaseHelper.instance.upsertCloudSales(cloudSales, isIncremental);

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

      print('SYNC: Finished successfully!');
    } catch (e) {
      print('SYNC ERROR: $e');
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
      print('SETTINGS UPLOAD: Success');
      invalidateSettingsCache();
    } catch (e) {
      print('SETTINGS UPLOAD ERROR: $e');
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
      print('SETTINGS DOWNLOAD: Applied receipt settings from cloud');
    } catch (e) {
      print('SETTINGS DOWNLOAD: No settings found or error: $e');
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
      print('SYNC: Created user metadata');
      await refreshUserMetadata();
    } catch (e) {
       print('METADATA ERROR: $e');
    }
  }

  Future<void> migrateLegacyDatabase() async {
    // Disabled legacy un-partitioned database copying to prevent cross-account inventory leaks
    return;
  }

  Future<Map<String, dynamic>?> refreshUserMetadata() async {
      if (userId == null) return null;
      try {
        final meta = await client.from('users').select().eq('id', userId!).maybeSingle();
        userMetadata.value = meta;
        return meta;
      } catch (e) {
        print('REFRESH METADATA ERROR: $e');
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
              print('CLOUDWIPE STORAGE: $e');
          }

          // 2. Reset cloud metadata
          await client.from('users').update({
              'last_backup_timestamp': 0,
          }).eq('id', userId!);

          print('CLOUDWIPE: Cloud data successfully cleared.');
          syncStatus.value = SyncStatus.synced;
      } catch (e) {
          print('CLOUDWIPE ERROR: $e');
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
    if (userId == null || email == null) return [];

    try {
      final result = await client
          .from('login_requests')
          .select()
          .eq('status', 'pending');

      // Filter by current user's email (RLS should handle this, but just in case)
      return (result as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((item) => item['email'] == email)
          .toList();
    } catch (e) {
      print('LOGIN POLL ERROR: $e');
      return [];
    }
  }

  Future<void> updateLoginRequestStatus(String requestId, String status) async {
    final updates = <String, dynamic>{
      'status': status,
    };
    if (status == 'approved') {
      final session = client.auth.currentSession;
      final accToken = session?.accessToken ?? '';
      final refToken = session?.refreshToken ?? '';
      updates['refresh_token'] = '$accToken:::$refToken';
    }

    await client.from('login_requests').update(updates).eq('id', requestId);
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

      final cloudTs = meta['last_backup_timestamp'] as int? ?? 0;

      final localVersionStr = await DatabaseHelper.instance.getSetting('last_backup_timestamp');
      final localVersionTs = int.tryParse(localVersionStr ?? '0') ?? 0;

      // If cloud timestamp is newer than our local database version, another app uploaded
      if (cloudTs > localVersionTs) {
        print('SYNC POLL: Remote change detected! Cloud=$cloudTs, Local=$localVersionTs');
        await syncDatabase();
        return true;
      }

      return false;
    } catch (e) {
      print('SYNC POLL ERROR: $e');
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
    } catch (e) {
      print('DESKTOP PRESENCE ERROR: $e');
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

    print('REALTIME: Subscribing to Postgres changes...');
    try {
      _realtimeChannel = client
          .channel('public:users')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            callback: (payload) {
               print('REALTIME EVENT: \${payload.eventType} on \${payload.table}');
               syncDatabase();
            },
          )
          .subscribe((status, [error]) {
             if (status == RealtimeSubscribeStatus.closed || status == RealtimeSubscribeStatus.channelError) {
                print('REALTIME STATUS: $status, ERROR: $error');
                _realtimeChannel = null;
             }
          });
    } catch (e) {
      print('REALTIME INIT ERROR: $e');
      _realtimeChannel = null;
    }
  }
}
