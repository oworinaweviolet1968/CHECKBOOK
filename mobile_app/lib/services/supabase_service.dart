import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:archive/archive_io.dart';
import 'database_helper.dart';

enum SyncStatus { idle, syncing, synced, error, offline }

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

      _lastKnownCloudTimestamp = ts;
      syncStatus.value = SyncStatus.synced;
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
    if (userId == null) return;
    try {
      final newPath = await _getLocalDbPath();
      final newFile = File(newPath);
      
      // If user-specific file already exists and has data, don't migrate legacy
      if (await newFile.exists()) {
        // Optional: Check if it's empty? 
        // For now, if it exists, we assume it's the right one or already synced.
        return;
      }

      // 1. Try Shared Desktop legacy path (JavaFX)
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final userHome = Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
        final jfxLegacyPath = join(userHome, 'METO_IMS_DATA', 'inventory.db');
        final jfxFile = File(jfxLegacyPath);
        
        if (await jfxFile.exists()) {
          print('SYNC: Migrating shared legacy inventory.db');
          await jfxFile.copy(newPath);
          return;
        }
      }

      // 2. Fallback to private mobile legacy path
      final legacyPath = join(await getDatabasesPath(), 'inventory.db');
      final legacyFile = File(legacyPath);

      if (await legacyFile.exists()) {
        print('SYNC: Migrating legacy private inventory.db');
        await legacyFile.copy(newPath);
      }
    } catch (e) {
      print('MIGRATION ERROR: $e');
    }
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
    final updates = {
      'status': status,
    };
    if (status == 'approved') {
      updates['refresh_token'] = client.auth.currentSession?.refreshToken ?? '';
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
