import '../database_helper.dart';
import 'clock_sync.dart';
import 'reactive_query.dart';
import 'write_queue.dart';

class DeltaStockManager {
  static Future<bool> applyLocalStockDelta({
    required String userId,
    required String syncId,
    required int delta,
  }) async {
    final db = await DatabaseHelper.instance.database;

    return await db.transaction((txn) async {
      // 1. Commutative Local SQLite Update
      final nowIso = ClockSync.getAdjustedTimestampIso();
      final rowsUpdated = await txn.rawUpdate('''
        UPDATE stock
        SET quantity = quantity + ?, updated_at = ?
        WHERE sync_id = ?
      ''', [delta, nowIso, syncId]);

      if (rowsUpdated == 0) {
        return false;
      }

      // 2. Queue Mutation Payload for Remote RPC Delta
      await WriteQueueManager.enqueueOperation(
        db: txn,
        userId: userId,
        tableName: 'stock',
        opType: 'DELTA_STOCK',
        syncId: syncId,
        payload: {
          'sync_id': syncId,
          'delta': delta,
        },
      );

      // 3. Instant 0ms Reactive UI Invalidation
      ReactiveQueryEngine.notifyTableChanged('stock');
      return true;
    });
  }
}
