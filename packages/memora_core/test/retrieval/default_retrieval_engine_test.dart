import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

import '../fakes/fake_stores.dart';

class _BrokenReranker implements RerankService {
  @override
  Future<List<RerankScore>> rerank(
    String query,
    List<RerankCandidate> candidates,
  ) async => throw const AiTransientException('Reranker down');
}

void main() {
  late FakeMemora db;
  final model = FakeEmbeddingService().model;

  setUp(() async {
    db = FakeMemora();
    void add(
      String id,
      String summary,
      String category,
      DateTime taken, {
      List<StoredAttribute> attributes = const [],
      bool embed = true,
    }) {
      db.seed(
        id: id,
        summary: summary,
        category: category,
        takenAt: taken,
        entities: [if (summary.startsWith('Reliance')) entity('Reliance')],
        attributes: attributes,
      );
      if (embed) {
        db.rows[id]!.vectors[vectorKey(model)] = (
          vector: FakeEmbeddingService.vectorFor(summary, model.dimensions),
          model: model,
        );
      }
    }

    add(
      'jul',
      'Reliance electricity bill for July',
      'utility_bill',
      DateTime(2026, 7, 5),
      attributes: [amount(1690)],
    );
    add(
      'aug',
      'Reliance electricity bill for August',
      'utility_bill',
      DateTime(2026, 8, 5),
      attributes: [amount(2103)],
    );
    add(
      'sep',
      'Reliance electricity bill for September',
      'utility_bill',
      DateTime(2026, 9, 5),
      attributes: [amount(1842)],
      embed: false,
    );
    add(
      'mac',
      'MacBook Air price comparison',
      'comparison',
      DateTime(2026, 8, 20),
      attributes: [amount(124900)],
    );
    add('flight', 'IndiGo flight to Goa', 'booking', DateTime(2026, 9, 10));
  });

  Future<(DefaultRetrievalEngine, AiHarness)> engine({
    EmbeddingService? embeddings,
    RerankService? reranker,
  }) async {
    final ai = await AiHarness.create(
      embeddings: embeddings,
      reranker: reranker,
    );
    return (
      DefaultRetrievalEngine(search: db, vectors: db, router: ai.router),
      ai,
    );
  }

  List<String> ids(RetrievalResult r) => [for (final h in r.hits) h.card.id];

  Set<RetrievalStrategy> foundBy(RetrievalResult r, String id) =>
      r.hits.firstWhere((h) => h.card.id == id).foundBy;

  test('a filters-only query keeps the structured order', () async {
    final embeddings = FakeEmbeddingService();
    final (retrieval, _) = await engine(embeddings: embeddings);

    final result = await retrieval.search(
      const RetrievalQuery(categories: {'utility_bill'}),
    );

    expect(ids(result), ['sep', 'aug', 'jul']);
    expect(result.strategiesUsed, {RetrievalStrategy.structured});
    expect(foundBy(result, 'aug'), {RetrievalStrategy.structured});
    expect(result.hits.first.card.facts['amount'], '₹1,842');
    expect(db.fullTextQueries, isEmpty);
    expect(embeddings.calls, isEmpty);
  });

  test('a text query fuses full text and semantic results', () async {
    final embeddings = FakeEmbeddingService();
    final (retrieval, _) = await engine(embeddings: embeddings);

    final result = await retrieval.search(
      const RetrievalQuery(text: 'electricity'),
    );

    expect(result.strategiesUsed, {
      RetrievalStrategy.text,
      RetrievalStrategy.semantic,
    });
    expect(ids(result).take(2).toSet(), {'jul', 'aug'});
    expect(ids(result)[2], 'sep');
    expect(ids(result).toSet(), {'jul', 'aug', 'sep', 'mac', 'flight'});
    expect(foundBy(result, 'aug'), {
      RetrievalStrategy.text,
      RetrievalStrategy.semantic,
    });
    expect(foundBy(result, 'sep'), {RetrievalStrategy.text});
    expect(foundBy(result, 'mac'), {RetrievalStrategy.semantic});
    expect(embeddings.purposes.single, EmbeddingPurpose.query);
    expect(embeddings.calls.single, ['electricity']);
  });

  test('semantic search is skipped without embeddings', () async {
    final (retrieval, _) = await engine();

    final result = await retrieval.search(
      const RetrievalQuery(text: 'electricity'),
    );

    expect(result.strategiesUsed, {RetrievalStrategy.text});
    expect(ids(result), ['sep', 'aug', 'jul']);
  });

  test('semantic search is skipped when embedding fails', () async {
    final embeddings = FakeEmbeddingService()
      ..failWith = const AiTransientException('down');
    final (retrieval, _) = await engine(embeddings: embeddings);

    final result = await retrieval.search(
      const RetrievalQuery(text: 'electricity'),
    );

    expect(result.strategiesUsed, {RetrievalStrategy.text});
    expect(ids(result), hasLength(3));
  });

  test('filters that match nothing short-circuit', () async {
    final embeddings = FakeEmbeddingService();
    final (retrieval, _) = await engine(embeddings: embeddings);

    final result = await retrieval.search(
      const RetrievalQuery(categories: {'receipt'}, text: 'electricity'),
    );

    expect(result.hits, isEmpty);
    expect(result.strategiesUsed, {RetrievalStrategy.structured});
    expect(db.fullTextQueries, isEmpty);
    expect(embeddings.calls, isEmpty);
  });

  test('text is searched only inside the filtered candidates', () async {
    final (retrieval, _) = await engine(embeddings: FakeEmbeddingService());

    final result = await retrieval.search(
      const RetrievalQuery(
        categories: {'utility_bill'},
        text: 'august',
        attributes: [AttributeFilter(type: 'amount', min: 1000)],
      ),
    );

    expect(ids(result).first, 'aug');
    expect(ids(result), isNot(contains('mac')));
    expect(foundBy(result, 'aug'), {
      RetrievalStrategy.structured,
      RetrievalStrategy.text,
      RetrievalStrategy.semantic,
    });
  });

  test('filtered candidates stay when the text matches none of them', () async {
    final (retrieval, _) = await engine();

    final result = await retrieval.search(
      const RetrievalQuery(categories: {'utility_bill'}, text: 'zebra'),
    );

    expect(ids(result), ['sep', 'aug', 'jul']);
    expect(foundBy(result, 'jul'), {RetrievalStrategy.structured});
  });

  test('respects the limit', () async {
    final (retrieval, _) = await engine();

    final structured = await retrieval.search(
      const RetrievalQuery(categories: {'utility_bill'}, limit: 2),
    );
    final text = await retrieval.search(
      const RetrievalQuery(text: 'reliance bill', limit: 1),
    );

    expect(ids(structured), ['sep', 'aug']);
    expect(text.hits, hasLength(1));
  });

  test('uses the selected reranker', () async {
    final reranker = ReversingReranker();
    final (retrieval, _) = await engine(reranker: reranker);

    final result = await retrieval.search(
      const RetrievalQuery(text: 'electricity'),
    );

    expect(reranker.queries, ['electricity']);
    expect(ids(result), ['jul', 'aug', 'sep']);
  });

  test('falls back to fusion reranking when the reranker fails', () async {
    final (retrieval, _) = await engine(reranker: _BrokenReranker());

    final result = await retrieval.search(
      const RetrievalQuery(text: 'electricity'),
    );

    expect(ids(result), ['sep', 'aug', 'jul']);
  });

  test('an empty query lists the newest memories', () async {
    final (retrieval, _) = await engine();

    final result = await retrieval.search(const RetrievalQuery(limit: 2));

    expect(ids(result), ['flight', 'sep']);
    expect(result.strategiesUsed, {RetrievalStrategy.structured});
  });

  group('filters that match more memories than fit', () {
    setUp(() {
      // 600 receipts, and the one we want is the oldest of them, so it falls
      // outside any "newest N" window.
      for (var i = 0; i < 600; i++) {
        db.seed(
          id: 'r$i',
          summary: i == 0
              ? 'Kerosene lantern receipt'
              : 'Grocery receipt number $i',
          category: 'receipt',
          takenAt: DateTime(2026, 1, 1).add(Duration(hours: i)),
        );
      }
    });

    test('stay hard constraints above the old 500 default', () async {
      final ai = await AiHarness.create();
      final retrieval = DefaultRetrievalEngine(
        search: db,
        vectors: db,
        router: ai.router,
      );

      final result = await retrieval.search(
        const RetrievalQuery(categories: {'receipt'}, text: 'kerosene'),
      );

      expect(ids(result), ['r0']);
    });

    test('are checked again after searching when they overflow', () async {
      final ai = await AiHarness.create();
      final retrieval = DefaultRetrievalEngine(
        search: db,
        vectors: db,
        router: ai.router,
        structuredLimit: 50,
      );

      final matching = await retrieval.search(
        const RetrievalQuery(categories: {'receipt'}, text: 'kerosene'),
      );
      expect(ids(matching), ['r0']);
      expect(foundBy(matching, 'r0'), contains(RetrievalStrategy.structured));

      // The same words in a memory of another category must still be filtered
      // out.
      db.seed(
        id: 'note',
        summary: 'Kerosene lantern note',
        category: 'document',
        takenAt: DateTime(2026, 6, 1),
      );
      final filtered = await retrieval.search(
        const RetrievalQuery(categories: {'receipt'}, text: 'kerosene'),
      );
      expect(ids(filtered), ['r0']);

      // A query whose words match nothing still falls back to the filtered
      // list rather than returning nothing.
      final fallback = await retrieval.search(
        const RetrievalQuery(categories: {'receipt'}, text: 'zebra', limit: 3),
      );
      expect(fallback.hits, hasLength(3));
    });
  });
}
