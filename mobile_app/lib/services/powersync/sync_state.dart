import 'package:flutter/foundation.dart';

enum SyncConnectionState { online, offline, reconnecting }
enum SyncEngineStatus { idle, uploading, downloading, synced, error }

class PowerSyncTelemetry {
  final SyncConnectionState connectionState;
  final SyncEngineStatus status;
  final int pendingUploadsCount;
  final DateTime? lastSyncedAt;
  final String? lastError;

  const PowerSyncTelemetry({
    this.connectionState = SyncConnectionState.offline,
    this.status = SyncEngineStatus.idle,
    this.pendingUploadsCount = 0,
    this.lastSyncedAt,
    this.lastError,
  });

  PowerSyncTelemetry copyWith({
    SyncConnectionState? connectionState,
    SyncEngineStatus? status,
    int? pendingUploadsCount,
    DateTime? lastSyncedAt,
    String? lastError,
  }) {
    return PowerSyncTelemetry(
      connectionState: connectionState ?? this.connectionState,
      status: status ?? this.status,
      pendingUploadsCount: pendingUploadsCount ?? this.pendingUploadsCount,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
      lastError: lastError ?? this.lastError,
    );
  }
}

class PowerSyncStateNotifier extends ValueNotifier<PowerSyncTelemetry> {
  PowerSyncStateNotifier() : super(const PowerSyncTelemetry());

  void updateState({
    SyncConnectionState? connectionState,
    SyncEngineStatus? status,
    int? pendingUploadsCount,
    DateTime? lastSyncedAt,
    String? lastError,
  }) {
    value = value.copyWith(
      connectionState: connectionState,
      status: status,
      pendingUploadsCount: pendingUploadsCount,
      lastSyncedAt: lastSyncedAt,
      lastError: lastError,
    );
  }
}
