import 'dart:math';

class RetryPolicy {
  static const int initialDelayMs = 1000;
  static const int maxDelayMs = 60000;
  static final Random _random = Random();

  static int calculateBackoffMs(int retryCount) {
    final delay = initialDelayMs * (1 << min(retryCount, 10));
    final jitter = _random.nextInt(1000);
    return min(delay + jitter, maxDelayMs);
  }

  static bool isRetryableStatusCode(int statusCode) {
    return statusCode >= 500 || statusCode == 429 || statusCode == 408;
  }
}
