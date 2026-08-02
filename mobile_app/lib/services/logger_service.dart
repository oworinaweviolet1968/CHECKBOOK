import 'dart:developer' as developer;

/// Structured logger service replacing raw print calls across the application.
class AppLogger {
  static void info(String message, {String tag = 'App'}) {
    developer.log(message, name: tag, level: 800);
  }

  static void warning(String message, {String tag = 'App', Object? error, StackTrace? stackTrace}) {
    developer.log(message, name: tag, level: 900, error: error, stackTrace: stackTrace);
  }

  static void error(String message, {String tag = 'App', Object? error, StackTrace? stackTrace}) {
    developer.log(message, name: tag, level: 1000, error: error, stackTrace: stackTrace);
  }
}
