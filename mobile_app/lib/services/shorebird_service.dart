import 'package:flutter/material.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';
import '../utils/colors.dart';

class ShorebirdService {
  static final ShorebirdService instance = ShorebirdService._();
  ShorebirdService._();

  final ShorebirdUpdater _updater = ShorebirdUpdater();
  bool _isChecking = false;

  bool get isAvailable => _updater.isAvailable;

  /// Checks for available Shorebird patches in the background. If an update is available, prompts the user to update.
  Future<void> checkForUpdate(BuildContext context, {bool showNoUpdateToast = false}) async {
    if (_isChecking) return;
    _isChecking = true;

    try {
      if (!isAvailable) {
        if (showNoUpdateToast && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Shorebird code push is not active in debug/desktop mode.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }

      final status = await _updater.checkForUpdate();

      if (!context.mounted) return;

      if (status == UpdateStatus.outdated) {
        _showUpdateAvailableDialog(context);
      } else if (status == UpdateStatus.restartRequired) {
        _showRestartDialog(context);
      } else if (showNoUpdateToast) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your app is already up to date!'),
            backgroundColor: AppColors.primaryGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('Shorebird update check failed: $e');
      if (showNoUpdateToast && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update check failed: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      _isChecking = false;
    }
  }

  void _showUpdateAvailableDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.system_update_rounded, color: AppColors.primaryGreen, size: 28),
            SizedBox(width: 10),
            Text('Update Available', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'A new update is available for Checkbook with latest features & fixes. Would you like to update now?',
          style: TextStyle(fontSize: 14, height: 1.4, color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Later', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(dialogContext);
              _downloadAndUpdate(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            icon: const Icon(Icons.download_rounded, size: 18),
            label: const Text('Update Now', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadAndUpdate(BuildContext context) async {
    if (!context.mounted) return;

    // Show downloading progress modal
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppColors.primaryGreen, strokeWidth: 3.5),
                SizedBox(height: 20),
                Text('Downloading Update...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                SizedBox(height: 6),
                Text('Please wait while the new version is fetched.', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      await _updater.update();

      if (!context.mounted) return;

      // Close loading dialog
      Navigator.of(context, rootNavigator: true).pop();

      // Show restart prompt
      _showRestartDialog(context);
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e'), backgroundColor: AppColors.accentRed, behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  void _showRestartDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.primaryGreen, size: 28),
            SizedBox(width: 10),
            Text('Update Ready', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'The update has been downloaded! Please close and re-open the app to apply the changes.',
          style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Got it!', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
