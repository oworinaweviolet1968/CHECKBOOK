import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/colors.dart';
import '../screens/login_screen.dart';
import '../services/supabase_service.dart';
import '../screens/passcode_setup_screen.dart';
import '../services/passcode_service.dart';
import '../screens/deleted_history_screen.dart';
import '../screens/price_update_screen.dart';
import '../screens/debt_history_screen.dart';
import '../services/database_helper.dart';
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
      await SupasService.instance.syncDatabase(isManual: true);
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

  void _showReceiptInfoDialog() async {
    final name = await DatabaseHelper.instance.getSetting("receipt_shop_name") ?? "";
    final number = await DatabaseHelper.instance.getSetting("receipt_shop_number") ?? "";
    final location = await DatabaseHelper.instance.getSetting("receipt_location") ?? "";
    final phone = await DatabaseHelper.instance.getSetting("receipt_phone") ?? "";
    final phone2 = await DatabaseHelper.instance.getSetting("receipt_phone2") ?? "";

    if (!mounted) return;

    final nameController = TextEditingController(text: name);
    final numberController = TextEditingController(text: number);
    final locationController = TextEditingController(text: location);
    final phoneController = TextEditingController(text: phone);
    final phone2Controller = TextEditingController(text: phone2);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Receipt Information',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Add info to display under CHECKBOOK APP on printed receipts',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 24),
              _buildModalTextField(
                controller: nameController,
                label: 'Shop / Company Name',
                hint: 'e.g. Meto Electronics',
                icon: Icons.store_rounded,
                maxLength: 40,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9 .&()\-\/,]')),
                ],
              ),
              const SizedBox(height: 16),
              _buildModalTextField(
                controller: numberController,
                label: 'Shop Number',
                hint: 'e.g. Shop G15',
                icon: Icons.tag_rounded,
                maxLength: 20,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9 .#\-\/,]')),
                ],
              ),
              const SizedBox(height: 16),
              _buildModalTextField(
                controller: locationController,
                label: 'Location / Address',
                hint: 'e.g. Kampala, Uganda',
                icon: Icons.location_on_rounded,
                maxLength: 40,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9 .&()\-\/,]')),
                ],
              ),
              const SizedBox(height: 16),
              _buildModalTextField(
                controller: phoneController,
                label: 'Phone Number / Contact',
                hint: 'e.g. +256 701 234567',
                icon: Icons.phone_rounded,
                keyboardType: TextInputType.phone,
                maxLength: 25,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9 +\-\/(),]')),
                ],
              ),
              const SizedBox(height: 16),
              _buildModalTextField(
                controller: phone2Controller,
                label: 'Phone Number / Contact 2nd (Optional)',
                hint: 'e.g. +256 780 654321',
                icon: Icons.phone_rounded,
                keyboardType: TextInputType.phone,
                maxLength: 25,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9 +\-\/(),]')),
                ],
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: () async {
                  try {
                    await DatabaseHelper.instance.saveSetting("receipt_shop_name", nameController.text.trim());
                    await DatabaseHelper.instance.saveSetting("receipt_shop_number", numberController.text.trim());
                    await DatabaseHelper.instance.saveSetting("receipt_location", locationController.text.trim());
                    await DatabaseHelper.instance.saveSetting("receipt_phone", phoneController.text.trim());
                    await DatabaseHelper.instance.saveSetting("receipt_phone2", phone2Controller.text.trim());

                    // Verify the save was successful by reading back
                    final savedName = await DatabaseHelper.instance.getSetting("receipt_shop_name");
                    print("RECEIPT SETTINGS SAVED: shop_name='$savedName', phone='${phoneController.text.trim()}', phone2='${phone2Controller.text.trim()}'");

                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Receipt settings saved successfully!'),
                          backgroundColor: AppColors.primaryGreen,
                        ),
                      );
                    }
                  } catch (e) {
                    print("ERROR saving receipt settings: $e");
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to save: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                    return;
                  }

                  // Upload receipt settings to cloud for desktop sync
                  await SupasService.instance.uploadReceiptSettings();
                  _handleBackup();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                child: const Text(
                  'Save receipt settings',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          ),
        ),
      ),
    );
  }

  Widget _buildModalTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    int? maxLength,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLength: maxLength,
          inputFormatters: inputFormatters,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: hint,
            counterText: "",
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
            prefixIcon: Icon(icon, color: AppColors.primaryGreen, size: 20),
            filled: true,
            fillColor: Colors.grey.shade50,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade200),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primaryGreen, width: 1.5),
            ),
          ),
        ),
      ],
    );
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
            _buildDebtSummaryCard(),
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
                  icon: status == DesktopStatus.online ? Icons.desktop_windows : Icons.desktop_access_disabled,
                  iconColor: color,
                  onTap: () async {
                    await SupasService.instance.checkDesktopPresence();
                  },
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
              title: 'Receipt Print Information',
              icon: Icons.receipt_long_rounded,
              iconColor: AppColors.primaryGreen,
              onTap: _showReceiptInfoDialog,
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
            _buildDebtActionCard(),
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
              'VERSION 2.2.0+5',
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
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textColor ?? AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDebtSummaryCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryGreen, Color(0xFF166534)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGreen.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Unsettled Debt',
                style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.account_balance_wallet, color: Colors.white, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              'UGX ${NumberFormat("#,###").format(_totalDebt)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Keep track of pending customer payments',
            style: TextStyle(color: Colors.white60, fontSize: 11),
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
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.payments_outlined, color: Colors.white70, size: 15),
                    SizedBox(width: 6),
                    Text(
                      'Collected Debt Today',
                      style: TextStyle(
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
                    style: const TextStyle(
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
    );
  }

  Widget _buildDebtActionCard() {
    return Container(
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
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primaryGreen.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.history_edu, color: AppColors.primaryGreen),
        ),
        title: const Text('Debt Management', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('View and settle customer debts', style: TextStyle(fontSize: 12)),
        trailing: PopupMenuButton<int>(
          icon: const Icon(Icons.more_vert, color: Colors.grey),
          onSelected: (value) async {
            if (value == 0) {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DebtHistoryScreen(initialIndex: 0)),
              );
              _loadDebtData();
            } else if (value == 1) {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DebtHistoryScreen(initialIndex: 1)),
              );
              _loadDebtData();
            }
          },
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 0,
              child: Row(
                children: [
                  Icon(Icons.pending_actions, size: 20, color: Colors.orange),
                  SizedBox(width: 12),
                  Text('Active Debts'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 1,
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 20, color: AppColors.primaryGreen),
                  SizedBox(width: 12),
                  Text('Settled Debts'),
                ],
              ),
            ),
          ],
        ),
        onTap: () {
           Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DebtHistoryScreen()),
            );
        },
      ),
    );
  }
}

