import 'package:flutter/material.dart';
import '../services/powersync/powersync_engine.dart';
import '../services/powersync/sync_state.dart';

class PowerSyncStatusBadge extends StatelessWidget {
  const PowerSyncStatusBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<PowerSyncTelemetry>(
      valueListenable: PowerSyncEngine.instance.stateNotifier,
      builder: (context, telemetry, child) {
        final isOnline = telemetry.connectionState == SyncConnectionState.online;
        final isSyncing = telemetry.status == SyncEngineStatus.uploading ||
            telemetry.status == SyncEngineStatus.downloading;
        final pendingCount = telemetry.pendingUploadsCount;

        Color badgeColor;
        IconData badgeIcon;
        String statusText;

        if (!isOnline) {
          badgeColor = Colors.amber.shade800;
          badgeIcon = Icons.cloud_off_rounded;
          statusText = pendingCount > 0 ? 'Offline ($pendingCount pending)' : 'Offline Mode';
        } else if (isSyncing) {
          badgeColor = Colors.blue.shade600;
          badgeIcon = Icons.sync_rounded;
          statusText = 'Syncing...';
        } else if (telemetry.status == SyncEngineStatus.error) {
          badgeColor = Colors.red.shade700;
          badgeIcon = Icons.error_outline_rounded;
          statusText = 'Sync Error';
        } else {
          badgeColor = Colors.green.shade700;
          badgeIcon = Icons.cloud_done_rounded;
          statusText = 'Synced';
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSyncing)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(badgeColor),
                  ),
                )
              else
                Icon(badgeIcon, size: 16, color: badgeColor),
              const SizedBox(width: 6),
              Text(
                statusText,
                style: TextStyle(
                  color: badgeColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
