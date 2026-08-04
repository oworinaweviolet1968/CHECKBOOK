import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/colors.dart';
import '../screens/login_screen.dart';
import '../services/supabase_service.dart';
import '../screens/passcode_setup_screen.dart';
import '../services/passcode_service.dart';
import '../screens/deleted_history_screen.dart';
import '../screens/price_update_screen.dart';
import '../screens/debt_history_screen.dart';
import '../screens/new_stock_screen.dart';
import '../services/database_helper.dart';
import '../services/shorebird_service.dart';
import '../widgets/passcode_dialog.dart';
import '../widgets/receipt_settings_sheet.dart';
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
  double _totalDebt = 0;
  double _todaysCollectedDebt = 0;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    SupasService.instance.syncStatus.addListener(_onSyncStatusChanged);
    _loadDebtData();
  }

  Future<void> _loadDebtData() async {
    final debt = await DatabaseHelper.instance.getTotalDebt();
    final collectedToday = await DatabaseHelper.instance.getTodaysCollectedDebt();
    if (mounted) {
      setState(() {
        _totalDebt = debt;
        _todaysCollectedDebt = collectedToday;
      });
    }
  }

  void _onSyncStatusChanged() {
    if (SupasService.instance.syncStatus.value == SyncStatus.synced) {
      _loadDebtData();
    }
  }

  @override
  void dispose() {
    SupasService.instance.syncStatus.removeListener(_onSyncStatusChanged);
    _spinController.dispose();
    super.dispose();
  }

  void _handlePriceUpdateNavigation() async {
    if (!PasscodeService.instance.hasPasscode) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PriceUpdateScreen()),
      );
      return;
    }

    final bool verified = await PasscodeDialog.show(
      context,
      reason: "Enter passcode to access repricing.",
    );

    if (verified && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const PriceUpdateScreen()),
      );
    }
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
      await SupasService.instance.syncDatabase(isManual: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup successful!', style: GoogleFonts.outfit()),
            backgroundColor: AppColors.primaryGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup failed: $e', style: GoogleFonts.outfit()),
            backgroundColor: const Color(0xFFEF4444),
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

  void _showReceiptInfoDialog() {
    ReceiptSettingsSheet.show(context);
  }

  @override
  Widget build(BuildContext context) {
    final email = _user?.email ?? 'User';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.lightCyan,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Image.asset('assets/images/app_icon.png', width: 20, height: 20),
            ),
            const SizedBox(width: 12),
            Text(
              'Account',
              style: GoogleFonts.outfit(
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
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(
          children: [
            _buildDebtSummaryCard(),
            const SizedBox(height: 20),

            // Profile Avatar & Email Header
            Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: AppColors.lightCyan,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  initial,
                  style: GoogleFonts.outfit(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryGreen,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              email,
              style: GoogleFonts.outfit(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),

            // Subscription status pill
            ValueListenableBuilder<Map<String, dynamic>?>(
              valueListenable: SupasService.instance.userMetadata,
              builder: (context, meta, child) {
                final now = DateTime.now().millisecondsSinceEpoch;
                final isBackupEnabled = meta?['monthly_cloud_backup'] as bool? ?? true;
                final backupExpiry = meta?['backup_expiry'] as int? ?? 0;
                final isBackupActive = isBackupEnabled && (backupExpiry == 0 || backupExpiry > now);

                final statusText = isBackupActive ? 'cloud subscription: active' : 'your backup subscription is done';
                final statusColor = isBackupActive ? AppColors.primaryGreen : const Color(0xFFEF4444);

                return InkWell(
                  onTap: () async {
                    final url = Uri.parse('https://beckhamz777.github.io/cb/#/cloud-backup');
                    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Could not open website', style: GoogleFonts.outfit()), backgroundColor: const Color(0xFFEF4444)),
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
                          style: GoogleFonts.outfit(
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
            const SizedBox(height: 24),

            // Cloud Sync Info Cards
            ValueListenableBuilder<Map<String, dynamic>?>(
              valueListenable: SupasService.instance.userMetadata,
              builder: (context, meta, child) {
                final timestamp = meta?['last_backup_timestamp'] as int?;
                return _buildInfoCard(
                  title: 'LAST BACKED UP',
                  subtitle: _formatTimestamp(timestamp),
                  icon: _isBackingUp ? Icons.sync : Icons.cloud_download_rounded,
                  iconColor: AppColors.primaryGreen,
                  onTap: _handleBackup,
                  isLoading: _isBackingUp,
                );
              },
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<DesktopStatus>(
              valueListenable: SupasService.instance.desktopStatus,
              builder: (context, status, child) {
                final meta = SupasService.instance.userMetadata.value;
                final lastSeenTs = meta?['desktop_last_seen'] as int?;
                final subtitleText = status == DesktopStatus.online
                    ? 'Currently Online'
                    : _formatTimestamp(lastSeenTs);
                final color = status == DesktopStatus.online ? AppColors.primaryGreen : Colors.grey;
                return _buildInfoCard(
                  title: 'DESKTOP LAST ONLINE',
                  subtitle: subtitleText,
                  icon: status == DesktopStatus.online ? Icons.desktop_windows_rounded : Icons.desktop_access_disabled_rounded,
                  iconColor: color,
                  onTap: () async {
                    await SupasService.instance.checkDesktopPresence();
                  },
                );
              },
            ),
            const SizedBox(height: 20),

            // Add New Stock Primary Button
            _buildPrimaryActionCard(
              title: 'Add New Stock',
              subtitle: 'Register new inventory items and batches',
              icon: Icons.add_box_rounded,
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const NewStockScreen()),
                );
              },
            ),

            // SECTION 1: STORE CONFIGURATION
            _buildSectionHeader('STORE CONFIGURATION'),
            _buildSectionGroup([
              _buildSettingsTile(
                title: 'Price Update / Repricing',
                subtitle: 'Manage item pricing and unit rates',
                icon: Icons.edit_note_rounded,
                onTap: _handlePriceUpdateNavigation,
              ),
              _buildSettingsTile(
                title: 'Receipt Print Information',
                subtitle: 'Configure store details on printed receipts',
                icon: Icons.receipt_long_rounded,
                onTap: _showReceiptInfoDialog,
              ),
            ]),

            // SECTION 2: FINANCE & OPERATIONS
            _buildSectionHeader('FINANCE & OPERATIONS'),
            _buildSectionGroup([
              _buildSettingsTile(
                title: 'Debt Management',
                subtitle: 'View and settle customer debt records',
                icon: Icons.account_balance_wallet_rounded,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DebtHistoryScreen()),
                  ).then((_) => _loadDebtData());
                },
              ),
            ]),

            // SECTION 3: SECURITY & PRIVACY
            _buildSectionHeader('SECURITY & PRIVACY'),
            _buildSectionGroup([
              _buildSettingsTile(
                title: 'App / Metrics Passcode',
                subtitle: PasscodeService.instance.hasPasscode ? 'Passcode Enabled' : 'Not Configured',
                icon: Icons.lock_outline_rounded,
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const PasscodeSetupScreen()),
                  );
                  if (mounted) setState(() {});
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: PasscodeService.instance.isBiometricsEnabled,
                builder: (context, isEnabled, _) {
                  return _buildSwitchTile(
                    title: 'Biometric Authentication',
                    subtitle: 'Use Fingerprint / Face ID to unlock metrics',
                    icon: Icons.fingerprint_rounded,
                    value: isEnabled,
                    onChanged: (val) async {
                      if (val && !PasscodeService.instance.hasPasscode) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Please set a passcode first before enabling biometrics', style: GoogleFonts.outfit()),
                            backgroundColor: Colors.orange,
                          ),
                        );
                        return;
                      }
                      await PasscodeService.instance.toggleBiometrics(val);
                    },
                  );
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: PasscodeService.instance.lockOnLaunch,
                builder: (context, isLockOnBoot, _) {
                  return _buildSwitchTile(
                    title: 'Lock Metrics on Boot',
                    subtitle: 'Default financial metrics to locked on launch',
                    icon: Icons.shield_outlined,
                    value: isLockOnBoot,
                    onChanged: (val) => PasscodeService.instance.toggleLockOnLaunch(val),
                  );
                },
              ),
              if (PasscodeService.instance.hasPasscode) ...[
                ValueListenableBuilder<bool>(
                  valueListenable: PasscodeService.instance.isLocked,
                  builder: (context, isLocked, _) {
                    if (isLocked) return const SizedBox.shrink();
                    return _buildSettingsTile(
                      title: 'Lock Financial Metrics Now',
                      subtitle: 'Immediately lock financial dashboards',
                      icon: Icons.lock_rounded,
                      iconBgColor: const Color(0xFFFFEDD5),
                      iconColor: const Color(0xFFEA580C),
                      onTap: () {
                        PasscodeService.instance.lock();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Financial metrics locked!', style: GoogleFonts.outfit()),
                            backgroundColor: AppColors.primaryGreen,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            ]),

            // SECTION 4: SYSTEM & SUPPORT
            _buildSectionHeader('SYSTEM & SUPPORT'),
            _buildSectionGroup([
              _buildSettingsTile(
                title: 'Check for Updates',
                subtitle: 'Search for live app updates',
                icon: Icons.system_update_rounded,
                onTap: () => ShorebirdService.instance.checkForUpdate(context, showNoUpdateToast: true),
              ),
              _buildSettingsTile(
                title: 'Customer Support',
                subtitle: 'Get help or contact support',
                icon: Icons.support_agent_rounded,
                onTap: () {},
              ),
              _buildSettingsTile(
                title: 'Delete History',
                subtitle: 'View deleted entries log',
                icon: Icons.delete_forever_rounded,
                iconBgColor: const Color(0xFFFEE2E2),
                iconColor: const Color(0xFFEF4444),
                textColor: const Color(0xFFEF4444),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const DeletedHistoryScreen()),
                  );
                },
              ),
              _buildSettingsTile(
                title: 'Log out',
                icon: Icons.logout_rounded,
                iconBgColor: const Color(0xFFFEE2E2),
                iconColor: const Color(0xFFEF4444),
                textColor: const Color(0xFFEF4444),
                trailing: const SizedBox.shrink(),
                onTap: _logout,
              ),
            ]),

            const SizedBox(height: 36),

            // Footer Version Tag
            Text(
              'VERSION 2.2.0+54',
              style: GoogleFonts.outfit(
                color: const Color(0xFF94A3B8),
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8, top: 24),
        child: Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: const Color(0xFF64748B),
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionGroup(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.neutralBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: List.generate(children.length, (index) {
          return Column(
            children: [
              children[index],
              if (index < children.length - 1)
                const Divider(height: 1, thickness: 0.6, color: Color(0xFFF1F5F9), indent: 64, endIndent: 16),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildSettingsTile({
    required String title,
    String? subtitle,
    required IconData icon,
    Color? iconBgColor,
    Color? iconColor,
    Color? textColor,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    final Color badgeBg = iconBgColor ?? AppColors.lightCyan;
    final Color badgeIcon = iconColor ?? AppColors.primaryGreen;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: badgeIcon, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: textColor ?? const Color(0xFF0F172A),
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.normal,
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing ?? const Icon(Icons.chevron_right_rounded, size: 22, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.lightCyan,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primaryGreen, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.normal,
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeThumbColor: AppColors.primaryGreen,
            onChanged: onChanged,
          ),
        ],
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
          border: Border.all(color: AppColors.neutralBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
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
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: const Color(0xFF64748B),
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

  Widget _buildPrimaryActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.primaryGreen.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.primaryGreen.withValues(alpha: 0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryGreen.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primaryGreen,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.primaryGreen),
          ],
        ),
      ),
    );
  }

  Widget _buildDebtSummaryCard() {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const DebtHistoryScreen()),
          ).then((_) => _loadDebtData());
        },
        borderRadius: BorderRadius.circular(20),
        splashColor: Colors.white.withValues(alpha: 0.1),
        highlightColor: Colors.white.withValues(alpha: 0.05),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 15,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Left Title
                  Expanded(
                    child: Text(
                      'TOTAL OUTSTANDING DEBT',
                      style: GoogleFonts.outfit(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.white70,
                        letterSpacing: 0.8,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Right Debtors Badge Button
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.people_outline, size: 14, color: Colors.white),
                        const SizedBox(width: 4),
                        Text(
                          'Debtors',
                          style: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(width: 2),
                        const Icon(Icons.chevron_right_rounded, size: 14, color: Colors.white),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'UGX ${NumberFormat("#,###").format(_totalDebt)}',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Tap to view and settle customer debts',
                style: GoogleFonts.outfit(color: Colors.white60, fontSize: 11),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.payments_outlined, color: Colors.white70, size: 15),
                        const SizedBox(width: 6),
                        Text(
                          'Collected Debt Today',
                          style: GoogleFonts.outfit(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.center,
                      child: Text(
                        'UGX ${NumberFormat("#,###").format(_todaysCollectedDebt)}',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
