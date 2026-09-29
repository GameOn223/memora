import 'package:sqlite3/sqlite3.dart';

import '../transactions.dart';
import 'm0001_initial.dart';

/// One step in the schema history.
///
/// Migrations are numbered from 1 with no gaps. A migration is never edited
/// after it ships. Change the schema by adding the next one.
abstract class Migration {
  const Migration();

  /// The schema version this migration produces. Stored in
  /// `PRAGMA user_version` once it has run.
  int get version;

  /// Applies the change. Runs inside a transaction that also bumps
  /// `user_version`, so a failure leaves the database as it was.
  void up(Database db);
}

/// Every migration, oldest first.
const migrations = <Migration>[M0001Initial()];

/// Brings [db] up to the newest version in [all].
///
/// Reads `PRAGMA user_version` and applies each pending migration in its own
/// transaction. Throws a [StateError] when the database was created by a newer
/// build of the app, or when [all] isn't numbered 1, 2, 3 and so on.
void runMigrations(Database db, [List<Migration> all = migrations]) {
  checkMigrationOrder(all);
  checkNotNewerThanBuild(db, all);
  applyPending(db, all, db.userVersion);
}

/// Throws unless [all] is numbered 1, 2, 3 and so on with no gaps.
void checkMigrationOrder(List<Migration> all) {
  for (var i = 0; i < all.length; i++) {
    final expected = i + 1;
    if (all[i].version != expected) {
      throw StateError(
        'Migration ${all[i].runtimeType} has version ${all[i].version}, '
        'expected $expected',
      );
    }
  }
}

/// Throws when [db] is at a higher version than this build knows about.
///
/// Call this before writing anything to the file, including the switch to
/// WAL, so an older build leaves a newer database exactly as it found it.
void checkNotNewerThanBuild(Database db, [List<Migration> all = migrations]) {
  if (db.userVersion > all.length) {
    throw StateError('Database was created by a newer version of Memora');
  }
}

/// Applies every migration in [all] numbered above [from].
///
/// [from] is the caller's last read of `PRAGMA user_version`, which can be
/// stale: the UI isolate and a background worker open the same file at the
/// same time and both read it before either one writes. Each migration takes
/// the write lock with `BEGIN IMMEDIATE` and reads the version again inside
/// that transaction, so the connection that loses the race skips work the
/// winner already did instead of failing on a table that now exists.
void applyPending(Database db, List<Migration> all, int from) {
  for (final migration in all.skip(from)) {
    db.transaction(() {
      if (db.userVersion >= migration.version) return;
      migration.up(db);
      db.userVersion = migration.version;
    }, immediate: true);
  }
}
