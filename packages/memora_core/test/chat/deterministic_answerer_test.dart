import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

import '../fakes/fake_stores.dart';

void main() {
  late FakeMemora db;
  late DeterministicAnswerer answerer;
  final clock = FixedClock(DateTime(2026, 9, 15, 10));

  setUp(() async {
    db = FakeMemora()
      ..seed(
        id: 'jul',
        summary: 'Reliance electricity bill for July',
        category: 'utility_bill',
        takenAt: DateTime(2026, 7, 5),
        entities: [entity('Reliance')],
        attributes: [amount(1690)],
      )
      ..seed(
        id: 'aug',
        summary: 'Reliance electricity bill for August',
        category: 'utility_bill',
        takenAt: DateTime(2026, 8, 5),
        entities: [entity('Reliance')],
        attributes: [
          amount(142, label: 'tax'),
          amount(2103),
        ],
      )
      ..seed(
        id: 'sep',
        summary: 'Reliance electricity bill for September',
        category: 'utility_bill',
        takenAt: DateTime(2026, 9, 5),
        entities: [entity('Reliance')],
        attributes: [amount(1842)],
      )
      ..seed(
        id: 'mac',
        summary: 'MacBook Air price comparison',
        category: 'comparison',
        takenAt: DateTime(2026, 8, 20),
        attributes: [amount(124900)],
      );
    final ai = await AiHarness.create();
    answerer = DeterministicAnswerer(
      retrieval: DefaultRetrievalEngine(
        search: db,
        vectors: db,
        router: ai.router,
      ),
      search: db,
      clock: clock,
    );
  });

  test('lists matches with a search-only strip', () async {
    final answer = await answerer.answer('show me reliance bills');

    expect(answer.text, 'Found 3 memories.');
    expect(answer.hits.map((h) => h.card.id).toSet(), {'jul', 'aug', 'sep'});
    expect(answer.presentation.searchOnly, isTrue);
    expect(answer.presentation.layout, SourceLayout.strip);
    expect(answer.presentation.headline, isNull);
    expect(answer.presentation.sourceLabel, '3 memories · filters + text');

    final search = answer.trace.single;
    expect(search.tool, 'search_memories');
    expect(search.arguments, {
      'text': 'reliance',
      'category': 'invoice, utility_bill',
    });
    expect(search.summary, '3 candidates');
  });

  test('the highest amount in a follow-up set', () async {
    final answer = await answerer.answer(
      'which one was highest?',
      within: {'jul', 'aug', 'sep'},
    );

    expect(
      answer.text,
      'Found 3 memories. The highest amount is ₹2,103 (Aug 2026).',
    );
    final p = answer.presentation;
    expect(p.layout, SourceLayout.table);
    expect(p.tableAttribute, 'amount');
    expect(p.headline, '₹2,103');
    expect(p.highlightMemoryId, 'aug');
    expect(p.searchOnly, isTrue);
    expect(answer.aggregate!.memoryId, 'aug');
    expect(answer.trace.map((t) => t.tool), [
      'search_memories',
      'aggregate_results',
    ]);
    expect(answer.trace.last.summary, '₹2,103');
  });

  test('the cheapest bill', () async {
    final answer = await answerer.answer('cheapest bill');
    expect(
      answer.text,
      'Found 3 memories. The lowest amount is ₹1,690 (Jul 2026).',
    );
    expect(answer.presentation.highlightMemoryId, 'jul');
  });

  test('a total uses one amount per memory, preferring the total', () async {
    final answer = await answerer.answer('total spent on bills');
    expect(answer.text, 'Found 3 memories. The total amount is ₹5,635.');
    expect(answer.presentation.headline, '₹5,635');
    expect(answer.presentation.highlightMemoryId, isNull);
  });

  test('an average', () async {
    final answer = await answerer.answer('average bill');
    expect(answer.text, 'Found 3 memories. The average amount is ₹1,878.33.');
  });

  test('a count', () async {
    final answer = await answerer.answer('how many bills');
    expect(answer.text, 'Found 3 memories.');
    expect(answer.presentation.headline, '3');
  });

  test('the latest one', () async {
    final answer = await answerer.answer('latest bill');
    expect(
      answer.text,
      'Found 3 memories. The latest is Reliance electricity bill for '
      'September from 5 Sep 2026.',
    );
    expect(answer.presentation.highlightMemoryId, 'sep');
  });

  test('says when nothing matched', () async {
    final answer = await answerer.answer('unicorn receipts');
    expect(answer.text, 'No memories matched.');
    expect(answer.hits, isEmpty);
    expect(answer.presentation.searchOnly, isTrue);
    expect(answer.presentation.sourceLabel, isNull);
  });

  test('only compares amounts in the most common currency', () async {
    db.seed(
      id: 'usd',
      summary: 'Netflix bill',
      category: 'utility_bill',
      takenAt: DateTime(2026, 9, 1),
      attributes: [amount(15.49, currency: 'USD')],
    );

    final answer = await answerer.answer('highest bill');

    expect(
      answer.text,
      'Found 4 memories. The highest amount is ₹2,103 (Aug 2026). '
      '1 amount in another currency was left out.',
    );
  });

  test('says when nothing has the attribute', () async {
    db.seed(
      id: 'chat',
      summary: 'Chat with Rahul',
      category: 'chat',
      takenAt: DateTime(2026, 9, 2),
    );
    final answer = await answerer.answer('highest chats');
    expect(answer.text, "Found 1 memory, but it doesn't have an amount.");
    expect(answer.presentation.headline, isNull);
  });
}
