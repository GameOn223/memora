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
  for (var i = 0; i < all.length; i++) {
    final expected = i + 1;
    if (all[i].version != expected) {
      throw StateError(
        'Migration ${all[i].runtimeType} has version ${all[i].version}, '
        'expected $expected',
      );
    }
  }

  final current = db.userVersion;
  if (current > all.length) {
    throw StateError('Database was created by a newer version of Memora');
  }

  for (final migration in all.skip(current)) {
    db.transaction(() {
      migration.up(db);
      db.userVersion = migration.version;
    }, immediate: true);
  }
}
