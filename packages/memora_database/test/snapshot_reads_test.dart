import 'package:memora_database/memora_database.dart';
import 'package:test/test.dart';

import 'support/fixtures.dart';
import 'support/spy_connection.dart';

/// A store method that runs several queries has to see one snapshot of the
/// database. A background worker commits while the UI reads, and without a
/// read transaction a memory can land in two slices of the same answer or in
/// none of them.
void main() {
  late MemoraDatabase ui;
  late MemoraDatabase worker;
  final now = DateTime.utc(2026, 9, 15, 10);

  setUp(() {
    final path = tempDatabasePath();
    ui = MemoraDatabase.open(path);
    addTearDown(ui.close);
    worker = MemoraDatabase.open(path);
    addTearDown(worker.close);
  });

  test('queueItems keeps a claimed memory in the list once', () async {
    final id = await seedMemory(ui, takenAt: DateTime.utc(2026, 7, 1));

    // Between the processing query and the waiting query, a worker claims
    // the only memory in the queue.
    final spy = SpyConnection(
      ui.connection,
      beforeRead: (reads) {
        if (reads == 1) {
          worker.connection.execute(
            "UPDATE memories SET status = 'processing', lease_until = ? "
            'WHERE id = ?',
            [now.millisecondsSinceEpoch + 600000, id],
          );
        }
      },
    );

    final items = await SqliteQueueStore(spy).queueItems();

    expect(items.map((i) => i.memory.id), [id]);
    expect(items.single.position, 1);
    expect(spy.readsInTransaction, everyElement(isTrue));
  });

  test('getDetails reads facts written by one understanding', () async {
    final id = await seedMemory(ui);
    await ui.memories.saveUnderstanding(
      id,
      understanding(),
      facts(
        entities: [entity('company', 'Reliance')],
        attributes: [amount(1842)],
        keywords: ['reliance', 'electricity'],
      ),
      now,
    );

    // A reprocess replaces every fact after the entities have been read.
    final spy = SpyConnection(
      ui.connection,
      beforeRead: (reads) {
        if (reads == 2) {
          worker.connection
            ..execute('DELETE FROM keywords WHERE memory_id = ?', [id])
            ..execute('DELETE FROM attributes WHERE memory_id = ?', [id]);
        }
      },
    );

    final details = (await SqliteMemoryStore(spy).getDetails(id))!;

    expect(details.entities.map((e) => e.value), ['Reliance']);
    expect(details.attributes, hasLength(1));
    expect(details.keywords, ['reliance', 'electricity']);
    expect(spy.readsInTransaction, everyElement(isTrue));
  });

  test('cards keep a memory deleted halfway through the read', () async {
    final id = await seedMemory(ui);
    await ui.memories.saveUnderstanding(
      id,
      understanding(),
      facts(attributes: [amount(1842)]),
      now,
    );

    final spy = SpyConnection(
      ui.connection,
      beforeRead: (reads) {
        if (reads == 1) {
          worker.connection.execute('DELETE FROM memories WHERE id = ?', [id]);
        }
      },
    );

    final cards = await SqliteSearchStore(spy).cards([id]);

    expect(cards.map((c) => c.id), [id]);
    expect(cards.single.facts, isNotEmpty);
    expect(spy.readsInTransaction, everyElement(isTrue));
  });
}
