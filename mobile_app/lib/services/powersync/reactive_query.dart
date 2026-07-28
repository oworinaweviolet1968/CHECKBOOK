import 'dart:async';

class ReactiveQueryEngine {
  static final StreamController<String> _tableChangeController = StreamController<String>.broadcast();

  static Stream<String> get onTableChanged => _tableChangeController.stream;

  static void notifyTableChanged(String tableName) {
    _tableChangeController.add(tableName);
  }

  static Stream<T> watchQuery<T>({
    required String tableName,
    required Future<T> Function() fetcher,
  }) async* {
    yield await fetcher();
    await for (final changedTable in _tableChangeController.stream) {
      if (changedTable == tableName || changedTable == '*' || changedTable == 'all') {
        yield await fetcher();
      }
    }
  }
}
