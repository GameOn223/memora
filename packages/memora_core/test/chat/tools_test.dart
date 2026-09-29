import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

import '../fakes/fake_stores.dart';

void main() {
  late FakeMemora db;
  late AiHarness ai;
  late Map<String, MemoraTool> tools;
  late ToolContext context;
  final now = DateTime(2026, 9, 15, 10);

  Future<void> setUpTools({EmbeddingService? embeddings}) async {
    ai = await AiHarness.create(embeddings: embeddings);
    final retrieval = DefaultRetrievalEngine(
      search: db,
      vectors: db,
      router: ai.router,
    );
    tools = {
      for (final tool in ToolRegistry.build(
        retrieval: retrieval,
        search: db,
        vectors: db,
        memories: db,
        router: ai.router,
      ))
        tool.name: tool,
    };
  }

  setUp(() async {
    db = FakeMemora()
      ..seed(
        id: 'jul',
        summary: 'Reliance electricity bill for July',
        category: 'utility_bill',
        takenAt: DateTime(2026, 7, 5),
        entities: [entity('Reliance')],
        attributes: [amount(1690)],
        extractedText: 'x' * 2000,
        keywords: ['electricity'],
      )
      ..seed(
        id: 'aug',
        summary: 'Reliance electricity bill for August',
        category: 'utility_bill',
        takenAt: DateTime(2026, 8, 5),
        entities: [entity('Reliance')],
        attributes: [amount(2103), dateAttribute('due_date', '2026-08-31')],
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
        id: 'flight',
        summary: 'IndiGo flight to Goa',
        category: 'booking',
        takenAt: DateTime(2026, 9, 10),
        entities: [entity('IndiGo')],
        attributes: [textAttribute('booking_reference', 'K4T9RB')],
      );
    await db.createConversation('c1', 'Bills', now);
    await db.createConversation('c2', 'Other', now);
    context = ToolContext(
      conversationId: 'c1',
      now: now,
      conversations: db,
      ids: SequentialIds(),
    );
    await setUpTools();
  });

  Future<ToolSuccess> ok(String name, Map<String, Object?> args) async {
    final result = await tools[name]!.run(args, context);
    if (result is ToolError) fail('$name failed: ${result.message}');
    return result as ToolSuccess;
  }

  Future<String> error(String name, Map<String, Object?> args) async {
    final result = await tools[name]!.run(args, context);
    if (result is ToolSuccess) fail('$name should have failed: ${result.json}');
    return (result as ToolError).message;
  }

  test('the registry offers every tool from the architecture', () {
    expect(tools.keys.toSet(), {
      'search_memories',
      'search_metadata',
      'search_text',
      'search_semantic',
      'search_by_date',
      'search_by_entity',
      'search_by_attribute',
      'get_memory',
      'get_related_memories',
      'filter_results',
      'aggregate_results',
    });
    for (final tool in tools.values) {
      final definition = tool.definition;
      expect(definition.name, tool.name);
      expect(definition.description, isNotEmpty);
      expect(definition.parameters['type'], 'object');
      expect(definition.parameters['properties'], isA<Map<String, Object?>>());
    }
  });

  group('validation', () {
    test('numbers, dates and required text', () async {
      expect(
        await error('search_memories', {'amount_min': 'lots'}),
        'amount_min must be a number',
      );
      expect(
        await error('search_memories', {'date_from': '31/08/2026'}),
        'date_from must be a date in YYYY-MM-DD format',
      );
      expect(
        await error('search_memories', {'limit': 'ten'}),
        'limit must be a whole number',
      );
      expect(await error('search_text', {}), 'text is required');
      expect(await error('search_text', {'text': 42}), 'text must be a string');
      expect(await error('get_memory', {}), 'id is required');
      expect(
        await error('aggregate_results', {'op': 'median'}),
        'op must be one of max, min, sum, avg, count, latest',
      );
    });

    test('ranges must be in order', () async {
      expect(
        await error('search_memories', {'amount_min': 500, 'amount_max': 100}),
        'amount_min must not be greater than amount_max',
      );
      expect(
        await error('search_by_date', {
          'date_from': '2026-09-01',
          'date_to': '2026-08-01',
        }),
        'date_from must be on or before date_to',
      );
    });

    test('filter-only tools need a filter', () async {
      expect(
        await error('search_metadata', {}),
        startsWith('Give at least one filter'),
      );
      expect(
        await error('search_by_date', {}),
        'Give date_from, date_to or both',
      );
    });

    test('limits are capped at 50 and numeric strings are accepted', () async {
      final result = await ok('search_memories', {
        'categories': ['utility_bill'],
        'amount_min': '1800',
        'limit': 500,
      });
      expect(result.json['count'], 2);
    });
  });

  group('searches', () {
    test('return compact cards and save a result set', () async {
      final result = await ok('search_by_entity', {'value': 'reliance'});

      expect(result.json['count'], 3);
      final memories = (result.json['memories']! as List)
          .cast<Map<String, Object?>>();
      expect(memories.first, {
        'id': 'sep',
        'taken': '2026-09-05',
        'summary': 'Reliance electricity bill for September',
        'category': 'utility_bill',
        'facts': {'amount': '₹1,842'},
      });
      expect(result.memoryIds, ['sep', 'aug', 'jul']);
      expect(result.traceSummary, '3 candidates');
      expect(result.sources, {'entity'});

      final saved = (await db.getResultSet(result.resultSetId!))!;
      expect(result.json['result_set_id'], saved.id);
      expect(saved.conversationId, 'c1');
      expect(saved.memoryIds, ['sep', 'aug', 'jul']);
      expect(saved.description, 'entity=reliance');
      expect(saved.createdAt, now);
    });

    test('search_memories combines text and filters', () async {
      final result = await ok('search_memories', {
        'text': 'august',
        'entity': 'Reliance',
        'amount_min': 2000,
        'currency': 'inr',
      });
      expect(result.memoryIds, ['aug']);
      expect(result.sources, {'entity', 'amount', 'text'});
      final saved = (await db.getResultSet(result.resultSetId!))!;
      expect(
        saved.description,
        'text=august, entity=Reliance, amount_min=2000, currency=INR',
      );
      expect(result.scores['aug'], 1.0);
    });

    test('search_by_date and search_by_attribute', () async {
      final september = await ok('search_by_date', {
        'date_from': '2026-09-01',
        'date_to': '2026-09-30',
      });
      expect(september.memoryIds, ['flight', 'sep']);

      final byReference = await ok('search_by_attribute', {
        'type': 'booking_reference',
        'equals': 'k4t9rb',
      });
      expect(byReference.memoryIds, ['flight']);

      final dueInAugust = await ok('search_by_attribute', {
        'type': 'due_date',
        'date_from': '2026-08-01',
        'date_to': '2026-08-31',
      });
      expect(dueInAugust.memoryIds, ['aug']);
    });

    test('an empty search saves no result set', () async {
      final result = await ok('search_by_entity', {'value': 'Airtel'});
      expect(result.json['count'], 0);
      expect(result.json['result_set_id'], isNull);
      expect(await db.latestResultSet('c1'), isNull);
    });

    test('semantic search explains when embeddings are off', () async {
      expect(
        await error('search_semantic', {'text': 'power bill'}),
        contains('search_text'),
      );
    });

    test('semantic search works with embeddings', () async {
      final embeddings = FakeEmbeddingService();
      await setUpTools(embeddings: embeddings);
      for (final id in ['jul', 'aug', 'sep', 'flight']) {
        await db.upsert(
          id,
          FakeEmbeddingService.vectorFor(
            db.rows[id]!.summary!,
            embeddings.model.dimensions,
          ),
          embeddings.model,
          now,
        );
      }

      final result = await ok('search_semantic', {'text': 'flight goa'});
      expect(result.memoryIds.first, 'flight');
      expect(result.sources, {'semantic'});
    });
  });

  group('get_memory', () {
    test('returns full details with long text truncated', () async {
      final result = await ok('get_memory', {'id': 'jul'});
      final json = result.json;
      expect(json['id'], 'jul');
      expect(json['taken'], '2026-07-05');
      expect(json['summary'], 'Reliance electricity bill for July');
      expect(json['category'], 'utility_bill');
      expect((json['extracted_text']! as String).length, 1500);
      expect(json['entities'], [
        {'type': 'company', 'value': 'Reliance'},
      ]);
      expect(json['attributes'], [
        {
          'type': 'amount',
          'value': '₹1,690',
          'label': 'total',
          'currency': 'INR',
        },
      ]);
      expect(json['keywords'], ['electricity']);
      expect(result.memoryIds, ['jul']);
    });

    test('unknown ids are a tool error', () async {
      expect(await error('get_memory', {'id': 'nope'}), contains('nope'));
    });
  });

  test('get_related_memories finds memories sharing entities', () async {
    final result = await ok('get_related_memories', {'id': 'aug'});
    expect(result.memoryIds.toSet(), {'jul', 'sep'});
    expect(result.sources, {'related'});
    expect(await db.latestResultSet('c1'), isNotNull);
  });

  group('result sets', () {
    test('aggregate and filter reuse the latest set by default', () async {
      final search = await ok('search_metadata', {
        'categories': ['utility_bill'],
      });

      final highest = await ok('aggregate_results', {'op': 'max'});
      expect(highest.json, {
        'op': 'max',
        'attribute': 'amount',
        'value': 2103,
        'display': '₹2,103',
        'currency': 'INR',
        'memory_id': 'aug',
      });
      expect(highest.traceSummary, '₹2,103');
      expect(highest.aggregate!.memoryId, 'aug');
      expect(highest.memoryIds, ['aug']);

      final filtered = await ok('filter_results', {'amount_min': 1800});
      expect(filtered.memoryIds, ['sep', 'aug']);
      expect(filtered.traceSummary, '2 of 3 kept');
      final narrowed = (await db.latestResultSet('c1'))!;
      expect(narrowed.id, filtered.resultSetId);
      expect(narrowed.description, 'category=utility_bill; amount_min=1800');

      final lowest = await ok('aggregate_results', {'op': 'min'});
      expect(lowest.json['memory_id'], 'sep');

      final fromFirst = await ok('aggregate_results', {
        'op': 'min',
        'result_set_id': search.resultSetId,
      });
      expect(fromFirst.json['memory_id'], 'jul');
    });

    test('sums only the most common currency and reports the rest', () async {
      db.seed(
        id: 'usd',
        summary: 'Hosting invoice',
        category: 'utility_bill',
        takenAt: DateTime(2026, 9, 1),
        attributes: [amount(20, currency: 'USD')],
      );
      await ok('search_metadata', {
        'categories': ['utility_bill'],
      });

      final sum = await ok('aggregate_results', {'op': 'sum'});

      expect(sum.json['value'], 5635);
      expect(sum.json['display'], '₹5,635');
      expect(sum.json['skipped_other_currency'], 1);
      expect(sum.json['memory_ids'], ['sep', 'aug', 'jul']);
    });

    test('count needs no attribute and names no memory', () async {
      await ok('search_by_entity', {'value': 'Reliance'});
      final count = await ok('aggregate_results', {'op': 'count'});
      expect(count.json, {'op': 'count', 'value': 3, 'display': '3'});
      expect(count.memoryIds, isEmpty);
    });

    test('explains missing sets and missing values', () async {
      expect(
        await error('filter_results', {'amount_min': 1}),
        'There are no earlier results to work with. Search first.',
      );
      expect(
        await error('aggregate_results', {
          'op': 'max',
          'result_set_id': 'missing',
        }),
        'No result set with id "missing" in this conversation.',
      );

      await ok('search_by_entity', {'value': 'IndiGo'});
      expect(
        await error('aggregate_results', {'op': 'max'}),
        "The memory in this result set doesn't have an amount.",
      );
    });

    test('a set from another conversation is not reachable', () async {
      final other = ToolContext(
        conversationId: 'c2',
        now: now,
        conversations: db,
        ids: SequentialIds(),
      );
      final search = await tools['search_by_entity']!.run({
        'value': 'Reliance',
      }, other) as ToolSuccess;

      expect(
        await error('aggregate_results', {
          'op': 'count',
          'result_set_id': search.resultSetId,
        }),
        contains('in this conversation'),
      );
    });
  });
}
