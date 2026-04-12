import 'package:flutter/foundation.dart';
import 'database_helper.dart';

class PasscodeService {
  static final PasscodeService instance = PasscodeService._init();
  PasscodeService._init();

  final ValueNotifier<bool> isLocked = ValueNotifier(true);
  String? _savedPasscode;

  Future<void> init() async {
    _savedPasscode = await DatabaseHelper.instance.getSetting('passcode');
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
  }

  void lock() {
    if (_savedPasscode != null) {
      isLocked.value = true;
    }
  }

  void reset() {
    _savedPasscode = null;
    isLocked.value = false;
  }

  bool get hasPasscode => _savedPasscode != null;
}
