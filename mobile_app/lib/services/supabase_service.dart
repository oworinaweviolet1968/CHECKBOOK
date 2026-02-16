import 'dart:io';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'database_helper.dart';

class SupasService {
  static final SupasService _instance = SupasService._privateConstructor();
  static SupasService get instance => _instance;

  SupasService._privateConstructor();

  final SupabaseClient client = Supabase.instance.client;

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
      print('SYNC: Starting sync for user $userId');
      
      // 1. Get Metadata
      final meta = await _getUserMetadata();
      final cloudTs = meta?['last_backup_timestamp'] as int? ?? 0;
      
      // 2. Get Local File Info
      final dbPath = await _getLocalDbPath();
      final file = File(dbPath);
      final localTs = await file.exists() ? (await file.lastModified()).millisecondsSinceEpoch : 0; // Dart file timestamps might differ slightly from Java.
      // Actually, relying on file timestamp is tricky across OS.
      // Java code uses `lastModified()`.
      
      print('SYNC: CloudTS=$cloudTs, LocalTS=$localTs');

      // 3. Compare
      if (cloudTs > localTs) {
          print('SYNC: Cloud is newer. Downloading...');
          await _downloadDatabase(userId!, dbPath);
      } else {
          print('SYNC: Local is newer or same.');
          // If local exists but not uploaded? 
          // For now, assume if local is newer, we upload on save, not on login.
          // Unless local is empty and cloud has data?
          if (!await file.exists() && cloudTs > 0) {
              print('SYNC: Local missing, downloading backup.');
              await _downloadDatabase(userId!, dbPath);
          }
      }
      
    } catch (e) {
      print('SYNC ERROR: $e');
    }
  }

  Future<void> uploadDatabase() async {
    if (userId == null) return;
    try {
       final dbPath = await _getLocalDbPath();
       final file = File(dbPath);
       if (!await file.exists()) return;

       final bytes = await file.readAsBytes();
       final cloudPath = 'backups/$userId/inventory.db'; // Using standard name for simplicity or match Java logic
       // Java logic: `backups/UID/inventory_<uid>.db` or similar based on filename.
       // Let's stick to a consistent name 'inventory.db' inside the user folder for mobile.
       // Java code uses `file.getName()` which is `inventory.db` or `inventory_<uid>.db`.
       // Let's try to match the Java expectation if possible.
       // If Java expects a specific name, we should find it. Java uses `resolvePath("inventory.db")` by default.
       
       await client.storage.from('backups').uploadBinary(
           '$userId/inventory.db',
           bytes,
           fileOptions: const FileOptions(upsert: true),
       );

       // Update Metadata
       // Java uses `System.currentTimeMillis()`.
       final ts = DateTime.now().millisecondsSinceEpoch;
       await client.rest.from('users').update({
           'last_backup_timestamp': ts,
       }).eq('id', userId!);
       
       print('SYNC: Upload complete. TS=$ts');
       
    } catch (e) {
       print('UPLOAD ERROR: $e');
    }
  }

  Future<void> _downloadDatabase(String uid, String savePath) async {
      try {
          // Try standard name
          final Uint8List data = await client.storage.from('backups').download('$uid/inventory.db');
          final file = File(savePath);
          await file.writeAsBytes(data);
          print('SYNC: Downloaded to $savePath');
      } catch (e) {
          print('DOWNLOAD ERROR: $e');
      }
  }

  Future<Map<String, dynamic>?> _getUserMetadata() async {
      final response = await client.rest.from('users').select().eq('id', userId!).maybeSingle();
      return response;
  }
  
  Future<String> _getLocalDbPath() async {
      final docDir = await getApplicationDocumentsDirectory();
      // Use database_helper path logic to be safe, but usually:
      final dbPath = await getDatabasesPath(); // sqflite path
      return join(dbPath, 'inventory.db');
  }
}
