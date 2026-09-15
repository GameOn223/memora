import 'package:memora_database/memora_database.dart';
import 'package:memora_database/src/migrations/migration.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';

void main() {
  group('MemoraDatabase.openInMemory', () {
    late MemoraDatabase db;

    setUp(() => db = MemoraDatabase.openInMemory());
    tearDown(() => db.close());

    test('runs every migration', () {
      expect(db.schemaVersion, 1);
      expect(db.schemaVersion, migrations.last.version);
    });

    test('creates every table and the FTS index', () {
      final names = db.connection
          .select("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((row) => row['name'] as String)
          .toSet();
      expect(
        names,
        containsAll(<String>[
          'memories',
          'entities',
          'attributes',
          'keywords',
          'embeddings',
          'memories_fts',
          'conversations',
          'messages',
          'message_references',
          'result_sets',
          'processing_metadata',
          'settings',
        ]),
      );
      final fts = db.connection.select(
        "SELECT sql FROM sqlite_master WHERE name = 'memories_fts'",
      );
      expect(fts.single['sql'] as String, contains('fts5'));
      expect(fts.single['sql'] as String, contains('remove_diacritics 2'));
    });

    test('creates the indexes the queries rely on', () {
      final indexes = db.connection
          .select("SELECT name FROM sqlite_master WHERE type = 'index'")
          .map((row) => row['name'] as String)
          .toSet();
      expect(
        indexes,
        containsAll(<String>[
          'memories_status_taken_at',
          'memories_taken_at',
          'memories_category',
          'entities_memory_id',
          'entities_normalized_value',
          'attributes_memory_id',
          'attributes_type_value_num',
          'attributes_type_value_date',
          'keywords_keyword',
          'embeddings_model',
          'messages_conversation_created_at',
          'message_references_memory_id',
          'result_sets_conversation_created_at',
          'processing_metadata_memory_created_at',
        ]),
      );
    });

    test('turns on foreign keys and a busy timeout', () {
      expect(db.connection.select('PRAGMA foreign_keys').single.columnAt(0), 1);
      expect(
        db.connection.select('PRAGMA busy_timeout').single.columnAt(0),
        5000,
      );
    });

    test('enforces foreign keys', () {
      expect(
        () => db.connection.execute(
          'INSERT INTO entities (memory_id, type, value, normalized_value) '
          'VALUES (?, ?, ?, ?)',
          ['missing', 'company', 'Reliance', 'reliance'],
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('rejects unknown statuses', () {
      expect(
        () => db.connection.execute(
          'INSERT INTO memories (id, image_path, source, sha256, mime_type, '
          'width, height, byte_size, taken_at, added_at, updated_at, status) '
          "VALUES ('a', 'x.png', 'gallery', 'h', 'image/png', 1, 1, 1, 0, 0, "
          "0, 'lost')",
        ),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('MemoraDatabase.open', () {
    test('uses WAL and does not re-run migrations on reopen', () {
      final path = tempDatabasePath();
      final first = MemoraDatabase.open(path);
      expect(first.schemaVersion, 1);
      expect(
        first.connection.select('PRAGMA journal_mode').single.columnAt(0),
        'wal',
      );
      first.connection.execute(
        "INSERT INTO settings (key, value) VALUES ('theme', '\"dark\"')",
      );
      first.close();

      final second = MemoraDatabase.open(path);
      addTearDown(second.close);
      expect(second.schemaVersion, 1);
      expect(
        second.connection
            .select("SELECT value FROM settings WHERE key = 'theme'")
            .single['value'],
        '"dark"',
      );
    });

    test('refuses a database from a newer version', () {
      final path = tempDatabasePath();
      final raw = sqlite3.open(path)..userVersion = 99;
      raw.close();

      expect(
        () => MemoraDatabase.open(path),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            'Database was created by a newer version of Memora',
          ),
        ),
      );
    });
  });

  group('runMigrations', () {
    late Database raw;

    setUp(() => raw = sqlite3.openInMemory());
    tearDown(() => raw.close());

    test('applies only pending migrations', () {
      final one = _CountingMigration(1);
      final two = _CountingMigration(2);
      runMigrations(raw, [one]);
      runMigrations(raw, [one, two]);
      runMigrations(raw, [one, two]);

      expect(one.runs, 1);
      expect(two.runs, 1);
      expect(raw.userVersion, 2);
    });

    test('rolls back a failing migration and keeps the old version', () {
      runMigrations(raw, [_CountingMigration(1)]);

      expect(
        () => runMigrations(raw, [_CountingMigration(1), _FailingMigration()]),
        throwsA(isA<SqliteException>()),
      );
      expect(raw.userVersion, 1);
      expect(
        raw.select("SELECT name FROM sqlite_master WHERE name = 'half_done'"),
        isEmpty,
      );
    });

    test('rejects migrations that are not numbered in order', () {
      expect(
        () =>
            runMigrations(raw, [_CountingMigration(2), _CountingMigration(1)]),
        throwsA(isA<StateError>()),
      );
    });
  });
}

class _CountingMigration extends Migration {
  _CountingMigration(this.version);

  @override
  final int version;

  int runs = 0;

  @override
  void up(Database db) {
    runs++;
    db.execute('CREATE TABLE t$version (x INTEGER)');
  }
}

class _FailingMigration extends Migration {
  @override
  int get version => 2;

  @override
  void up(Database db) {
    db
      ..execute('CREATE TABLE half_done (x INTEGER)')
      ..execute('INSERT INTO nowhere VALUES (1)');
  }
}
