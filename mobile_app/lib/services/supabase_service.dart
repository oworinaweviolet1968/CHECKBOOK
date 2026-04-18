import 'dart:io';
import 'package:flutter/foundation.dart';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'database_helper.dart';

enum SyncStatus { idle, syncing, synced, error, offline }

class SupasService {
  static final SupasService _instance = SupasService._privateConstructor();
  static SupasService get instance => _instance;

  SupasService._privateConstructor();

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
  Future<void> syncDatabase({bool isManual = false}) async {
    if (userId == null) return;

    try {
      syncStatus.value = SyncStatus.syncing;
      print('SYNC: Starting sync for user $userId');
      
      // 1. Get Metadata & Local Info
      final meta = await refreshUserMetadata();
      final cloudTs = meta?['last_backup_timestamp'] as int? ?? 0;
      final isBackupEnabled = meta?['monthly_cloud_backup'] as bool? ?? true;
      final backupExpiry = meta?['backup_expiry'] as int? ?? 0;
      
      // Check if subscription has expired (if expiry is set)
      final now = DateTime.now().millisecondsSinceEpoch;
      final isBackupActive = isBackupEnabled && (backupExpiry == 0 || backupExpiry > now);

      if (!isBackupActive) {
          print('SYNC: Backup disabled or subscription expired for this user.');
          syncStatus.value = SyncStatus.offline;
          return;
      }

      final dbPath = await _getLocalDbPath();
      final file = File(dbPath);
      final localTs = await file.exists() ? (await file.lastModified()).millisecondsSinceEpoch : 0;
      final localHasData = await DatabaseHelper.instance.hasData();

      print('SYNC: CloudTS=$cloudTs, LocalTS=$localTs, LocalHasData=$localHasData');

      // 3. Compare (Matching Java logic)
      if (cloudTs > localTs) {
          print('SYNC: Cloud is newer. Downloading...');
          await _downloadDatabase(userId!, dbPath);
      } else {
          print('SYNC: Local is newer or same.');
          // Logic: Only upload automatically if the cloud is empty.
          // IF manual, we always force an upload to ensure deletions/updates propagate.
          if (isManual || cloudTs == 0) {
              if (localHasData) {
                  print('SYNC: Uploading changes...');
                  await uploadDatabase();
              } else {
                  print('SYNC: Local empty, nothing to upload.');
              }
          } else {
              print('SYNC: Automatic sync skipped upload to prevent cloud overwrite.');
          }
      }
      syncStatus.value = SyncStatus.synced;
    } catch (e) {
      print('SYNC ERROR: $e');
      syncStatus.value = SyncStatus.error;
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

  Future<void> uploadDatabase() async {
    if (userId == null) return;
    try {
       syncStatus.value = SyncStatus.syncing;
       if (!await DatabaseHelper.instance.hasData()) {
          print('SYNC: Skip upload - No local data');
          syncStatus.value = SyncStatus.synced;
          return;
       }

       final file = File(await _getLocalDbPath());
       if (!await file.exists()) {
          syncStatus.value = SyncStatus.error;
          return;
       }

       final bytes = await file.readAsBytes();
       final cloudFileName = file.path.split(Platform.pathSeparator).last;
       final path = '$userId/$cloudFileName';

       await client.storage.from('backups').uploadBinary(
           path,
           bytes,
           fileOptions: const FileOptions(upsert: true, contentType: 'application/x-sqlite3'),
       );

       final ts = DateTime.now().millisecondsSinceEpoch;
       await client.from('users').update({
           'last_backup_timestamp': ts,
       }).eq('id', userId!);
       
       print('SYNC: Upload complete. TS=$ts');
       updateLastKnownTimestamp(ts);
       syncStatus.value = SyncStatus.synced;
    } catch (e) {
       print('UPLOAD ERROR: $e');
       syncStatus.value = SyncStatus.error;
    }
  }

  Future<void> _downloadDatabase(String uid, String savePath) async {
      try {
          final fileName = savePath.split(Platform.pathSeparator).last;
          Uint8List? data;
          
          try {
            data = await client.storage.from('backups').download('$uid/$fileName');
          } catch (_) {
            // Fallback for legacy generic name
            data = await client.storage.from('backups').download('$uid/inventory.db');
          }
          
          if (data != null) {
            final file = File(savePath);
            await file.writeAsBytes(data);
            print('SYNC: Downloaded to $savePath');
          }
      } catch (e) {
          print('DOWNLOAD ERROR: $e');
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

      // First call: just cache the value, don't trigger a sync
      if (_lastKnownCloudTimestamp == 0) {
        _lastKnownCloudTimestamp = cloudTs;
        return false;
      }

      // If cloud timestamp is newer than what we last knew, another app uploaded
      if (cloudTs > _lastKnownCloudTimestamp) {
        print('SYNC POLL: Remote change detected! Cloud=$cloudTs, LastKnown=$_lastKnownCloudTimestamp');
        _lastKnownCloudTimestamp = cloudTs;

        // Download the newer database
        final dbPath = await _getLocalDbPath();
        await DatabaseHelper.instance.close();
        await _downloadDatabase(userId!, dbPath);
        await DatabaseHelper.instance.reopen();

        syncStatus.value = SyncStatus.synced;
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
}
