import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'database_helper.dart';
import 'supabase_service.dart';
import '../widgets/passcode_modal.dart';

class PasscodeService {
  static final PasscodeService instance = PasscodeService._init();
  PasscodeService._init();

  final LocalAuthentication _localAuth = LocalAuthentication();

  final ValueNotifier<bool> isLocked = ValueNotifier(true);
  final ValueNotifier<bool> isBiometricsEnabled = ValueNotifier(false);
  final ValueNotifier<bool> lockOnLaunch = ValueNotifier(true);

  String? _savedPasscode;

  Future<void> init() async {
    _savedPasscode = await DatabaseHelper.instance.getSetting('passcode');
    if (_savedPasscode != null && _savedPasscode!.isEmpty) {
      _savedPasscode = null;
    }

    final bioSetting = await DatabaseHelper.instance.getSetting('biometrics_enabled');
    isBiometricsEnabled.value = bioSetting == 'true';

    final launchSetting = await DatabaseHelper.instance.getSetting('lock_on_launch');
    lockOnLaunch.value = launchSetting != 'false'; // Default to true if not set

    if (_savedPasscode == null) {
      isLocked.value = false;
    } else {
      isLocked.value = lockOnLaunch.value;
    }
  }

  Future<bool> canCheckBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck || isSupported;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics() async {
    try {
      final canBio = await canCheckBiometrics();
      if (!canBio) return false;

      final didAuth = await _localAuth.authenticate(
        localizedReason: 'Authenticate to view financial metrics',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (didAuth) {
        isLocked.value = false;
      }
      return didAuth;
    } catch (e) {
      debugPrint('Biometrics auth error: $e');
      return false;
    }
  }

  Future<bool> verifyPasscode(String passcode) async {
    if (_savedPasscode == null) return true;
    if (_savedPasscode == passcode) {
      isLocked.value = false;
      return true;
    }
    return false;
  }

  Future<void> setPasscode(String passcode) async {
    await DatabaseHelper.instance.saveSetting('passcode', passcode);
    _savedPasscode = passcode;
    isLocked.value = true;
    await SupasService.instance.uploadReceiptSettings();
  }

  Future<void> toggleBiometrics(bool enable) async {
    isBiometricsEnabled.value = enable;
    await DatabaseHelper.instance.saveSetting('biometrics_enabled', enable.toString());
  }

  Future<void> toggleLockOnLaunch(bool enable) async {
    lockOnLaunch.value = enable;
    await DatabaseHelper.instance.saveSetting('lock_on_launch', enable.toString());
  }

  void lock() {
    if (_savedPasscode != null) {
      isLocked.value = true;
    }
  }

  Future<void> reset() async {
    await DatabaseHelper.instance.saveSetting('passcode', '');
    _savedPasscode = null;
    isLocked.value = false;
    isBiometricsEnabled.value = false;
    await DatabaseHelper.instance.saveSetting('biometrics_enabled', 'false');
    await SupasService.instance.uploadReceiptSettings();
  }

  bool get hasPasscode => _savedPasscode != null;

  /// Main authentication prompt.
  /// Tries biometrics if enabled, otherwise shows the passcode PIN dialog.
  Future<bool> authenticate(BuildContext context) async {
    if (!hasPasscode) {
      isLocked.value = false;
      return true;
    }

    if (isBiometricsEnabled.value) {
      final success = await authenticateWithBiometrics();
      if (success) return true;
    }

    if (!context.mounted) return false;
    return await showPasscodeModal(context);
  }

  Future<bool> showPasscodeModal(BuildContext context) async {
    return await PasscodeModal.show(context);
  }
}
