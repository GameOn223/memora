import 'package:sqlite3/sqlite3.dart';

/// Transaction helpers for a raw connection.
extension Transactions on Database {
  /// Runs [body] inside a transaction and commits when it returns.
  ///
  /// Any exception rolls the transaction back and is rethrown. [body] must be
  /// synchronous so no other code can use the connection halfway through.
  /// When a transaction is already open, [body] joins it.
  ///
  /// Set [immediate] to take the write lock up front, which avoids a busy
  /// error halfway through when another connection starts writing.
  T transaction<T>(T Function() body, {bool immediate = false}) {
    if (!autocommit) return body();
    execute(immediate ? 'BEGIN IMMEDIATE' : 'BEGIN');
    try {
      final result = body();
      if (result is Future) {
        throw ArgumentError('Transaction bodies must be synchronous');
      }
      execute('COMMIT');
      return result;
    } catch (_) {
      if (!autocommit) execute('ROLLBACK');
      rethrow;
    }
  }
}
