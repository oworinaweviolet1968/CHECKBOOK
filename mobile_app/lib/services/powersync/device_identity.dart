import '../database_helper.dart';

class DeviceIdentity {
  static String? _cachedDeviceId;

  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;

    try {
      final db = await DatabaseHelper.instance.database;
      final res = await db.query(
        'settings',
        where: 'key = ?',
        whereArgs: ['device_id'],
      );

      if (res.isNotEmpty && res.first['value'] != null) {
        _cachedDeviceId = res.first['value'] as String;
        return _cachedDeviceId!;
      }

      final newId = DatabaseHelper.generateUUID();
      await db.insert('settings', {
        'key': 'device_id',
        'value': newId,
      });
      _cachedDeviceId = newId;
      return _cachedDeviceId!;
    } catch (_) {
      final fallback = DatabaseHelper.generateUUID();
      _cachedDeviceId = fallback;
      return fallback;
    }
  }
}
