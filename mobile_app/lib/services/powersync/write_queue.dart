import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../database_helper.dart';
import 'clock_sync.dart';
import 'device_identity.dart';

class WriteQueueManager {
  static Future<void> initializeQueueTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_write_queue (
        seq_id INTEGER PRIMARY KEY AUTOINCREMENT,
        mutation_id TEXT UNIQUE NOT NULL,
        device_id TEXT NOT NULL,
        user_id TEXT NOT NULL,
        table_name TEXT NOT NULL,
        op_type TEXT NOT NULL,
        sync_id TEXT NOT NULL,
        parent_sync_id TEXT,
        payload TEXT NOT NULL,
        status TEXT DEFAULT 'PENDING',
        retry_count INTEGER DEFAULT 0,
        last_error TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // Local Database Indexing guideline: Add index on (status, seq_id)
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_queue_status_seq 
      ON sync_write_queue(status, seq_id)
    ''');
  }

  static Future<String> enqueueOperation({
    required DatabaseExecutor db,
    required String userId,
    required String tableName,
    required String opType,
    required String syncId,
    String? parentSyncId,
    required Map<String, dynamic> payload,
  }) async {
    final mutationId = DatabaseHelper.generateUUID();
    final deviceId = await DeviceIdentity.getDeviceId();
    final createdAt = ClockSync.getAdjustedTimestampIso();

    await db.insert('sync_write_queue', {
      'mutation_id': mutationId,
      'device_id': deviceId,
      'user_id': userId,
      'table_name': tableName,
      'op_type': opType,
      'sync_id': syncId,
      'parent_sync_id': parentSyncId,
      'payload': jsonEncode(payload),
      'status': 'PENDING',
      'created_at': createdAt,
    });

    return mutationId;
  }

  static Future<List<Map<String, dynamic>>> fetchPendingBatch(Database db, int batchSize) async {
    return await db.query(
      'sync_write_queue',
      where: 'status = ?',
      whereArgs: ['PENDING'],
      orderBy: 'seq_id ASC',
      limit: batchSize,
    );
  }

  static Future<void> markBatchCompleted(Database db, List<String> mutationIds) async {
    if (mutationIds.isEmpty) return;
    final placeholders = List.filled(mutationIds.length, '?').join(', ');
    await db.delete(
      'sync_write_queue',
      where: 'mutation_id IN ($placeholders)',
      whereArgs: mutationIds,
    );
  }

  static Future<void> markOperationFailed(Database db, String mutationId, String error) async {
    await db.rawUpdate('''
      UPDATE sync_write_queue
      SET retry_count = retry_count + 1, last_error = ?, status = 'PENDING'
      WHERE mutation_id = ?
    ''', [error, mutationId]);
  }
}
