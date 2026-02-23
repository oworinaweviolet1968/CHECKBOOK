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
  Future<void> syncDatabase() async {
    if (userId == null) return;

    try {
      syncStatus.value = SyncStatus.syncing;
      print('SYNC: Starting sync for user $userId');
      
      // 1. Get Metadata & Local Info
      final meta = await _getUserMetadata();
      final cloudTs = meta?['last_backup_timestamp'] as int? ?? 0;
      final isBackupEnabled = meta?['monthly_cloud_backup'] as bool? ?? true;
      
      if (!isBackupEnabled) {
          print('SYNC: Backup disabled for this user.');
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
          if (localHasData) {
              print('SYNC: Uploading changes...');
              await uploadDatabase();
          } else if (cloudTs > 0) {
              print('SYNC: Local empty but cloud has data. Restoring...');
              await _downloadDatabase(userId!, dbPath);
          } else {
              print('SYNC: Both empty. Ready.');
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
      final meta = await _getUserMetadata();
      if (meta != null) return; // Already exists

      await client.from('users').insert({
        'id': userId,
        'email': email,
        'ownership_payment': false,
        'monthly_cloud_backup': true,
      });
      print('SYNC: Created user metadata');
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

  Future<Map<String, dynamic>?> _getUserMetadata() async {
      return await client.from('users').select().eq('id', userId!).maybeSingle();
  }
  
  Future<String> _getLocalDbPath() async {
      return await DatabaseHelper.instance.getDbPath();
  }
}
