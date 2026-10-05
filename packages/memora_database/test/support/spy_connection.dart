import 'package:sqlite3/sqlite3.dart';

/// Wraps a connection and calls [beforeRead] before every query a store runs.
///
/// Tests use it to commit from a second connection partway through a store
/// method, which is what a background worker does while the UI reads. Anything
/// other than reading, running statements and checking `autocommit` throws, so
/// a store reaching for something else shows up straight away.
class SpyConnection implements Database {
  SpyConnection(this._inner, {this.beforeRead});

  final Database _inner;

  /// Called with the number of reads already done, before the next one.
  final void Function(int reads)? beforeRead;

  /// Whether each read so far ran inside a transaction.
  final List<bool> readsInTransaction = [];

  @override
  ResultSet select(String sql, [List<Object?> parameters = const []]) {
    _onRead();
    return _inner.select(sql, parameters);
  }

  @override
  PreparedStatement prepare(
    String sql, {
    bool persistent = false,
    bool vtab = true,
    bool checkNoTail = false,
  }) {
    _onRead();
    return _inner.prepare(
      sql,
      persistent: persistent,
      vtab: vtab,
      checkNoTail: checkNoTail,
    );
  }

  @override
  void execute(String sql, [List<Object?> parameters = const []]) =>
      _inner.execute(sql, parameters);

  @override
  bool get autocommit => _inner.autocommit;

  void _onRead() {
    final done = readsInTransaction.length;
    readsInTransaction.add(!_inner.autocommit);
    beforeRead?.call(done);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'SpyConnection does not forward ${invocation.memberName}',
  );
}
