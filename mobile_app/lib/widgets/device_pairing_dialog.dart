import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/colors.dart';
import '../services/passcode_service.dart';
import '../services/supabase_service.dart';
import 'passcode_dialog.dart';

class DevicePairingDialog extends StatefulWidget {
  final String sessionId;
  final String checkbookId;
  final String deviceName;

  const DevicePairingDialog({
    super.key,
    required this.sessionId,
    required this.checkbookId,
    required this.deviceName,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String sessionId,
    required String checkbookId,
    required String deviceName,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DevicePairingDialog(
        sessionId: sessionId,
        checkbookId: checkbookId,
        deviceName: deviceName,
      ),
    );
  }

  @override
  State<DevicePairingDialog> createState() => _DevicePairingDialogState();
}

class _DevicePairingDialogState extends State<DevicePairingDialog> {
  bool _isProcessing = false;

  Future<void> _handleAccept() async {
    if (_isProcessing) return;

    // Passcode security check if enabled
    if (PasscodeService.instance.hasPasscode) {
      final verified = await PasscodeDialog.show(
        context,
        reason: "Enter passcode to authorize desktop access.",
      );
      if (!verified) return;
    }

    setState(() => _isProcessing = true);

    try {
      final success = await SupasService.instance.respondPairingRequest(widget.sessionId, 'ACCEPT');
      if (mounted) {
        Navigator.pop(context, success);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Desktop connection approved!', style: GoogleFonts.outfit()),
            backgroundColor: AppColors.primaryGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Approval failed: $e', style: GoogleFonts.outfit()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleReject() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      await SupasService.instance.respondPairingRequest(widget.sessionId, 'REJECT');
      if (mounted) {
        Navigator.pop(context, false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Desktop connection request rejected.', style: GoogleFonts.outfit()),
            backgroundColor: Colors.grey[700],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context, false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Header Icon & Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.lightCyan,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.desktop_windows_rounded,
                  color: AppColors.primaryGreen,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Desktop Login Request',
                      style: GoogleFonts.outfit(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Checkbook ID: ${widget.checkbookId}',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: AppColors.primaryGreen,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Details Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Requesting Device',
                      style: GoogleFonts.outfit(color: Colors.grey[600], fontSize: 13),
                    ),
                    Text(
                      widget.deviceName,
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Divider(height: 1),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Time',
                      style: GoogleFonts.outfit(color: Colors.grey[600], fontSize: 13),
                    ),
                    Text(
                      'Just now',
                      style: GoogleFonts.outfit(
                        fontWeight: FontWeight.w500,
                        color: AppColors.textPrimary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Action Buttons
          if (_isProcessing)
            const Center(
              child: CircularProgressIndicator(color: AppColors.primaryGreen),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _handleReject,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Reject',
                      style: GoogleFonts.outfit(
                        color: const Color(0xFF64748B),
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _handleAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      'Accept & Pair',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
