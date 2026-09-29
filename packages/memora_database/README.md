# memora_database

SQLite storage for Memora. This package implements the storage ports defined in `memora_core` (`MemoryStore`, `QueueStore`, `SearchStore`, `VectorStore`, `ConversationStore` and `SettingsStore`) on top of [`package:sqlite3`](https://pub.dev/packages/sqlite3). It's pure Dart, so every test runs on a laptop against a real SQLite build.

The design is described in [docs/architecture.md](../../docs/architecture.md), section 6. Read that first if you're changing the schema.

## Using it

```dart
final db = MemoraDatabase.open('/path/to/files/memora.db');

final outcome = await db.memories.insertCaptured(newMemories, DateTime.now());
final next = await db.queue.claimNext(DateTime.now(), const Duration(minutes: 10));
final hits = await db.search.fullText('electricity bill');

db.close();
```

`MemoraDatabase.openInMemory()` gives you a private database with the full schema, which is what the tests use.

Opening a database turns on foreign keys, sets `busy_timeout` to 5000 ms and `synchronous` to `NORMAL`, switches file databases to WAL, and then runs any pending migrations. Open one `MemoraDatabase` per isolate. The UI and a background worker can each hold their own connection to the same file.

## What lives where

| File | Contents |
|------|----------|
| `lib/src/memora_database.dart` | Opening, pragmas, migrations, and the store getters |
| `lib/src/migrations/` | The migration runner and one file per schema version |
| `lib/src/sqlite_memory_store.dart` | Memories, facts, deletes, and the FTS row kept in step with AI output |
| `lib/src/sqlite_queue_store.dart` | Lease-based claiming and the queue screen listing |
| `lib/src/sqlite_search_store.dart` | Structured filters, FTS5 search, cards and aggregation values |
| `lib/src/sqlite_vector_store.dart` | Vector storage and brute-force nearest-neighbour search |
| `lib/src/sqlite_conversation_store.dart` | Conversations, messages, references and result sets |
| `lib/src/sqlite_settings_store.dart` | JSON settings |
| `lib/src/fts_query.dart` | Turns user text into a safe FTS5 `MATCH` expression |
| `lib/src/codec.dart` | Timestamps, vector blobs and JSON column helpers |

A few behaviors worth knowing about:

- Timestamps are stored as UTC milliseconds and read back as UTC `DateTime` values.
- Search results never include rows whose status is `deleted`.
- User text never reaches FTS5 directly. `ftsMatchExpression` splits it into letter and digit tokens and quotes each one.
- Vectors are L2-normalized when stored and the query is normalized too, so search scores are cosine similarity. Only vectors with the exact model id, version and dimensions are compared.
- With a file database, a vector scan over more than 2,000 rows runs in `Isolate.run` on its own read-only connection. In-memory databases always scan inline.
- Writes that point at a memory which no longer exists (saving an understanding, adding a processing record, storing a vector or a message reference) quietly do nothing. A worker can finish after the user deleted what it was working on, and that shouldn't crash anything.

## Migrations

The schema version is kept in `PRAGMA user_version`. `runMigrations` in `lib/src/migrations/migration.dart` reads it and applies every newer migration, each one in its own transaction that also bumps `user_version`. If a migration throws, its transaction rolls back and the database stays at the previous version. A database whose version is higher than the newest migration this build knows about is refused with a `StateError` before anything is written to the file, including the switch to WAL, so an older app leaves a newer database exactly as it found it.

Two connections can open the same file at once, which happens whenever the UI starts while a background worker is running. Each migration takes the write lock with `BEGIN IMMEDIATE` and reads `user_version` again inside that transaction, so the connection that loses the race skips what the winner already applied instead of failing on a table that now exists.

Migrations run with foreign keys off. The runner sets `PRAGMA foreign_keys = OFF` before it takes the write lock, since the pragma is ignored inside a transaction, and turns it back on when the run finishes either way. That matters because a migration that rebuilds a table drops the old one, and with foreign keys on, that drop cascades into everything that referenced it: entities, attributes, keywords, embeddings and message references all disappear. In exchange, a migration has to leave the references intact. `PRAGMA foreign_key_check` runs inside the same transaction, and anything dangling throws a `StateError` that rolls the migration back.

To change the schema:

1. Never edit a migration that has shipped. Users already have databases built by it.
2. Add `lib/src/migrations/m000N_short_name.dart` with a class that extends `Migration`, returns `N` from `version` and does its work in `up`.
3. Append it to the `migrations` list. Versions must run 1, 2, 3 and so on with no gaps, and the runner checks that.
4. Add a test that migrates from the previous version. Build a database at version `N - 1` with `runMigrations(db, migrations.take(N - 1).toList())`, insert rows that look like real data, run `runMigrations(db)`, and check that the data survived and the new schema is in place.
5. Update section 6 of docs/architecture.md.

A sketch of that test:

```dart
test('m0002 keeps existing memories', () {
  final db = sqlite3.openInMemory()..execute('PRAGMA foreign_keys = ON');
  addTearDown(db.close);
  runMigrations(db, migrations.take(1).toList());
  db.execute("INSERT INTO memories (...) VALUES (...)");

  runMigrations(db);

  expect(db.userVersion, 2);
  expect(db.select('SELECT COUNT(*) AS n FROM memories').single['n'], 1);
});
```

To rebuild a table, follow SQLite's [table rebuild steps](https://www.sqlite.org/lang_altertable.html#otheralter): create the new table under a temporary name, copy the rows over, drop the old table, then rename the new one. Don't touch `PRAGMA foreign_keys` yourself. The runner has already turned it off in the one place where that works, and it checks the references for you before the migration commits.

## Running the tests

From this directory:

```sh
dart test
dart format --output=none --set-exit-if-changed .
dart analyze --fatal-infos
```

The first run builds the `sqlite3` package's native hook, which downloads a prebuilt SQLite library for your platform. After that the tests run offline.

The tests use `sqlite3.openInMemory()` for most cases and temporary files for anything that needs WAL, a second connection or an isolate. One test searches 5,000 random 384-dimension vectors and expects it to take less than 1.5 seconds. When the `CI` environment variable is set and the machine is slower than that, the test is skipped with a message instead of failing.
