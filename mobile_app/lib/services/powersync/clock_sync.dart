class ClockSync {
  static int _clockOffsetMs = 0;

  static void updateClockOffset(int serverEpochMs) {
    final localNow = DateTime.now().millisecondsSinceEpoch;
    _clockOffsetMs = serverEpochMs - localNow;
  }

  static DateTime getAdjustedDateTime() {
    return DateTime.now().add(Duration(milliseconds: _clockOffsetMs));
  }

  static String getAdjustedTimestampIso() {
    return getAdjustedDateTime().toUtc().toIso8601String();
  }
}
