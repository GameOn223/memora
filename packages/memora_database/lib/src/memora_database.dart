import 'package:memora_core/memora_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'migrations/migration.dart';
import 'sqlite_memory_store.dart';

/// The Memora SQLite database and the stores built on it.
///
/// Open one per isolate. Every store shares the same connection, which is
/// synchronous, so store methods finish their SQL before they return.
class MemoraDatabase {
  MemoraDatabase._(this.connection, this.path);

  /// Opens (or creates) the database file at [path] and runs any pending
  /// migrations. Uses WAL so a background worker can write while the UI
  /// reads.
  factory MemoraDatabase.open(String path) =>
      MemoraDatabase._configure(sqlite3.open(path), path);

  /// Opens a private in-memory database with the full schema. Used by tests.
  factory MemoraDatabase.openInMemory() =>
      MemoraDatabase._configure(sqlite3.openInMemory(), null);

  factory MemoraDatabase._configure(Database db, String? path) {
    try {
      db
        ..execute('PRAGMA foreign_keys = ON')
        ..execute('PRAGMA busy_timeout = 5000')
        ..execute('PRAGMA synchronous = NORMAL');
      if (path != null) db.execute('PRAGMA journal_mode = WAL');
      runMigrations(db);
    } catch (_) {
      db.close();
      rethrow;
    }
    return MemoraDatabase._(db, path);
  }

  /// The underlying connection. App code should go through the stores. This
  /// is here for tests and maintenance tooling.
  final Database connection;

  /// The file behind this database, or null when it lives in memory.
  final String? path;

  /// The schema version, read from `PRAGMA user_version`.
  int get schemaVersion => connection.userVersion;

  /// Memories and the facts derived from them.
  late final MemoryStore memories = SqliteMemoryStore(connection);

  /// Closes the connection. The stores can't be used afterwards.
  void close() => connection.close();
}
