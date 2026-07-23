import 'package:flutter/foundation.dart';
import 'database_helper.dart';
import 'supabase_service.dart';

class PasscodeService {
  static final PasscodeService instance = PasscodeService._init();
  PasscodeService._init();

  final ValueNotifier<bool> isLocked = ValueNotifier(true);
  String? _savedPasscode;

  Future<void> init() async {
    _savedPasscode = await DatabaseHelper.instance.getSetting('passcode');
    if (_savedPasscode != null && _savedPasscode!.isEmpty) {
      _savedPasscode = null;
    }
    // If no passcode is set, it's effectively "unlocked" but we usually 
    // force a "Create Passcode" flow from the UI.
    // For now, if no passcode exists, we don't lock.
    if (_savedPasscode == null) {
      isLocked.value = false;
    } else {
      isLocked.value = true;
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

  void lock() {
    if (_savedPasscode != null) {
      isLocked.value = true;
    }
  }

  Future<void> reset() async {
    await DatabaseHelper.instance.saveSetting('passcode', '');
    _savedPasscode = null;
    isLocked.value = false;
    await SupasService.instance.uploadReceiptSettings();
  }

  bool get hasPasscode => _savedPasscode != null;
}

