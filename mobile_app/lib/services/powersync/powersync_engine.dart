import 'dart:async';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database_helper.dart';
import 'device_identity.dart';
import 'reactive_query.dart';
import 'sync_state.dart';
import 'write_queue.dart';

class PowerSyncEngine {
  static final PowerSyncEngine instance = PowerSyncEngine._internal();
  PowerSyncEngine._internal();

  final PowerSyncStateNotifier stateNotifier = PowerSyncStateNotifier();
  Timer? _syncTimer;
  bool _isProcessing = false;

  void initialize() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(seconds: 5), (_) => processWriteQueue());
    processWriteQueue();
  }

  void dispose() {
    _syncTimer?.cancel();
  }

  Future<void> processWriteQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        stateNotifier.updateState(
          connectionState: SyncConnectionState.offline,
          status: SyncEngineStatus.idle,
        );
        return;
      }

      final db = await DatabaseHelper.instance.database;

      // Queue Chunking: 50 items per batch
      final batch = await WriteQueueManager.fetchPendingBatch(db, 50);

      if (batch.isEmpty) {
        stateNotifier.updateState(
          connectionState: SyncConnectionState.online,
          status: SyncEngineStatus.synced,
          pendingUploadsCount: 0,
        );
        return;
      }

      stateNotifier.updateState(
        connectionState: SyncConnectionState.online,
        status: SyncEngineStatus.uploading,
        pendingUploadsCount: batch.length,
      );

      final deviceId = await DeviceIdentity.getDeviceId();
      final ops = <Map<String, dynamic>>[];
      final mutationIds = <String>[];

      for (final item in batch) {
        final mutId = item['mutation_id'] as String;
        mutationIds.add(mutId);

        final opMap = {
          'mutation_id': mutId,
          'op_type': item['op_type'],
          'sync_id': item['sync_id'],
          'table_name': item['table_name'],
        };

        final payloadStr = item['payload'] as String?;
        if (payloadStr != null && payloadStr.isNotEmpty) {
          try {
            final payloadObj = jsonDecode(payloadStr) as Map<String, dynamic>;
            if (payloadObj.containsKey('delta')) {
              opMap['delta'] = payloadObj['delta'];
            }
          } catch (_) {}
        }

        ops.add(opMap);
      }

      // Invoke Supabase RPC
      final response = await supabase.rpc(
        'rpc_process_sync_batch',
        params: {
          'p_device_id': deviceId,
          'p_user_id': user.id,
          'p_operations': ops,
        },
      );

      if (response != null && (response['success'] == true)) {
        await WriteQueueManager.markBatchCompleted(db, mutationIds);

        stateNotifier.updateState(
          status: SyncEngineStatus.synced,
          lastSyncedAt: DateTime.now(),
          pendingUploadsCount: 0,
        );

        ReactiveQueryEngine.notifyTableChanged('all');
      } else {
        for (final mutId in mutationIds) {
          await WriteQueueManager.markOperationFailed(db, mutId, 'Batch RPC upload failed');
        }
        stateNotifier.updateState(
          status: SyncEngineStatus.error,
          lastError: 'Batch upload failed',
        );
      }
    } catch (e) {
      stateNotifier.updateState(
        connectionState: SyncConnectionState.offline,
        status: SyncEngineStatus.error,
        lastError: e.toString(),
      );
    } finally {
      _isProcessing = false;
    }
  }
}
