import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/colors.dart';
import '../screens/login_screen.dart';
import '../services/supabase_service.dart';
import '../screens/passcode_setup_screen.dart';
import '../services/passcode_service.dart';
import '../screens/deleted_history_screen.dart';
import '../screens/price_update_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> with SingleTickerProviderStateMixin {
  final User? _user = Supabase.instance.client.auth.currentUser;
  bool _isBackingUp = false;
  late final AnimationController _spinController;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _spinController.dispose();
    super.dispose();
  }

  void _handlePriceUpdateNavigation() {
    if (!PasscodeService.instance.hasPasscode) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PriceUpdateScreen()),
      );
      return;
    }

    final controller = TextEditingController();
    String? errorMessage;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Security Verification', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter passcode to access repricing.', style: TextStyle(color: Colors.grey, fontSize: 13)),
              const SizedBox(height: 20),
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                maxLength: 6,
                obscureText: true,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 10, fontWeight: FontWeight.bold, color: AppColors.primaryGreen),
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  counterText: "",
                  hintText: "******",
                  hintStyle: const TextStyle(letterSpacing: 0, color: Colors.grey),
                ),
                onChanged: (_) {
                  if (errorMessage != null) setModalState(() => errorMessage = null);
                },
              ),
              if (errorMessage != null) ...[
                const SizedBox(height: 8),
                Text(errorMessage!, style: const TextStyle(color: Colors.red, fontSize: 13, fontWeight: FontWeight.bold)),
              ],
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
            TextButton(
              onPressed: () async {
                bool success = await PasscodeService.instance.verifyPasscode(controller.text);
                if (mounted) {
                  if (success) {
                    Navigator.pop(context);
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const PriceUpdateScreen()),
                    );
                  } else {
                    setModalState(() => errorMessage = "Incorrect Passcode!");
                  }
                }
              },
              child: const Text('Verify', style: TextStyle(color: AppColors.primaryGreen, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _logout() async {
    PasscodeService.instance.reset();
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _handleBackup() async {
    if (_isBackingUp) return;

    setState(() => _isBackingUp = true);
    
    try {
      await SupasService.instance.uploadDatabase();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Backup successful!'),
            backgroundColor: AppColors.primaryGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isBackingUp = false);
      }
    }
  }

  String _formatTimestamp(int? timestamp) {
    if (timestamp == null || timestamp == 0) return 'Never';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return DateFormat('dd-MMM-yyyy HH:mm').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final email = _user?.email ?? 'User';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.asset('assets/images/app_icon.png', width: 20, height: 20),
            ),
            const SizedBox(width: 12),
            const Text(
              'Account',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Avatar
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryGreen,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Username/Email
            Text(
              email,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            // Subscription status
            ValueListenableBuilder<Map<String, dynamic>?>(
              valueListenable: SupasService.instance.userMetadata,
              builder: (context, meta, child) {
                final now = DateTime.now().millisecondsSinceEpoch;
                final isBackupEnabled = meta?['monthly_cloud_backup'] as bool? ?? true;
                final backupExpiry = meta?['backup_expiry'] as int? ?? 0;
                final isBackupActive = isBackupEnabled && (backupExpiry == 0 || backupExpiry > now);
                
                final statusText = isBackupActive ? 'cloud subscription: active' : 'your backup subscription is done';
                final statusColor = isBackupActive ? AppColors.primaryGreen : Colors.red;

                return InkWell(
                  onTap: () async {
                    final url = Uri.parse('https://beckhamz777.github.io/cb/#/cloud-backup');
                    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Could not open website'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isBackupActive)
                          RotationTransition(
                            turns: _spinController,
                            child: Icon(Icons.sync, size: 14, color: statusColor),
                          )
                        else
                          Icon(Icons.error_outline, size: 14, color: statusColor),
                        const SizedBox(width: 8),
                        Text(
                          statusText,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 40),
            // Last Backed Up Section
            ValueListenableBuilder<Map<String, dynamic>?>(
              valueListenable: SupasService.instance.userMetadata,
              builder: (context, meta, child) {
                final timestamp = meta?['last_backup_timestamp'] as int?;
                return _buildInfoCard(
                  title: 'LAST BACKED UP',
                  subtitle: _formatTimestamp(timestamp),
                  icon: _isBackingUp ? Icons.sync : Icons.cloud_download,
                  iconColor: AppColors.primaryGreen,
                  onTap: _handleBackup,
                  isLoading: _isBackingUp,
                );
              },
            ),
            const SizedBox(height: 16),
            // Buttons Section
            _buildActionCard(
              title: 'Price Update / Repricing',
              icon: Icons.edit_note_rounded,
              iconColor: AppColors.primaryGreen,
              onTap: _handlePriceUpdateNavigation,
            ),
            const SizedBox(height: 16),
            _buildActionCard(
              title: 'Create passcode',
              icon: Icons.lock_outline,
              iconColor: AppColors.primaryGreen,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PasscodeSetupScreen()),
                );
              },
            ),
            const SizedBox(height: 16),
            _buildActionCard(
              title: 'Delete History',
              icon: Icons.delete_outline,
              iconColor: Colors.red,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const DeletedHistoryScreen()),
                );
              },
            ),
            const SizedBox(height: 16),
            _buildActionCard(
              title: 'Customer support',
              icon: Icons.headset_mic_outlined,
              iconColor: AppColors.primaryGreen,
              onTap: () {},
            ),
            const SizedBox(height: 16),
            _buildActionCard(
              title: 'Log out',
              icon: Icons.logout,
              iconColor: Colors.red,
              textColor: Colors.red,
              onTap: _logout,
            ),
            const SizedBox(height: 48),
            // Version
            const Text(
              'VERSION V.0',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: isLoading
                  ? SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(iconColor),
                      ),
                    )
                  : Icon(icon, color: iconColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard({
    required String title,
    required IconData icon,
    required Color iconColor,
    Color? textColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: textColor == Colors.red ? 0.05 : 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor),
            ),
            const SizedBox(width: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textColor ?? AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

