import '../ai/capabilities.dart';
import '../ai/errors.dart';
import '../ai/router.dart';
import '../model/retrieval.dart';
import '../ports/stores.dart';
import '../services/contracts.dart';
import 'fusion_reranker.dart';
import 'rank_fusion.dart';

/// Hybrid search over structured filters, full text and vectors.
///
/// Filters are hard constraints. Text and semantic results are ranked lists
/// inside them, fused with reciprocal rank fusion and then reranked. See
/// docs/architecture.md, section 8.2.
class DefaultRetrievalEngine implements RetrievalEngine {
  DefaultRetrievalEngine({
    required this._search,
    required this._vectors,
    required this._router,
    this._fallbackReranker = const FusionReranker(),
    this.structuredLimit = defaultStructuredLimit,
  });

  /// How many fused results are reranked.
  static const rerankDepth = 30;

  /// How many results each text strategy contributes before fusion.
  static const strategyLimit = 50;

  /// How many memories a filter may match before the engine stops holding
  /// them all and checks the filters after searching instead.
  static const defaultStructuredLimit = 5000;

  /// Lower it in tests to exercise the path where a filter matches more
  /// memories than fit.
  final int structuredLimit;

  final SearchStore _search;
  final VectorStore _vectors;
  final CapabilityRouter _router;
  final RerankService _fallbackReranker;

  @override
  Future<RetrievalResult> search(RetrievalQuery query) async {
    final used = <RetrievalStrategy>{};
    final foundBy = <String, Set<RetrievalStrategy>>{};
    final text = query.hasText ? query.text!.trim() : null;

    void mark(List<ScoredId> ranking, RetrievalStrategy strategy) {
      for (final hit in ranking) {
        (foundBy[hit.id] ??= {}).add(strategy);
      }
    }

    var structuredRanking = const <ScoredId>[];
    Set<String>? candidates;
    var truncated = false;
    if (query.hasFilters || text == null) {
      final ids = await _search.structured(query, limit: structuredLimit);
      used.add(RetrievalStrategy.structured);
      structuredRanking = [for (final id in ids) ScoredId(id, 0)];
      if (query.hasFilters) {
        if (ids.length >= structuredLimit) {
          // More memories match the filters than one query can carry. Search
          // the whole library and check the filters afterwards instead, so
          // they stay hard constraints rather than "the newest N of them".
          truncated = true;
        } else {
          candidates = ids.toSet();
          if (candidates.isEmpty) {
            return RetrievalResult(hits: const [], strategiesUsed: used);
          }
        }
      }
    }

    final rankings = <List<ScoredId>>[];
    if (text != null) {
      if (query.strategies.contains(RetrievalStrategy.text)) {
        final hits = await _search.fullText(
          text,
          within: candidates,
          limit: strategyLimit,
        );
        used.add(RetrievalStrategy.text);
        rankings.add(hits);
        mark(hits, RetrievalStrategy.text);
      }
      if (query.strategies.contains(RetrievalStrategy.semantic)) {
        final hits = await _semantic(text, candidates);
        if (hits != null) {
          used.add(RetrievalStrategy.semantic);
          rankings.add(hits);
          mark(hits, RetrievalStrategy.semantic);
        }
      }
    }
    final textFoundNothing = rankings.every((r) => r.isEmpty);
    if (text == null ||
        (textFoundNothing && (candidates != null || truncated))) {
      rankings
        ..clear()
        ..add(structuredRanking);
    }
    if (query.hasFilters) mark(structuredRanking, RetrievalStrategy.structured);

    final limit = query.effectiveLimit;
    final depth = text == null
        ? limit
        : (limit > rerankDepth ? limit : rerankDepth);
    var fused = reciprocalRankFusion(rankings).take(depth).toList();
    if (truncated && fused.isNotEmpty) {
      final allowed = (await _search.structured(
        query.copyWith(within: {for (final f in fused) f.id}),
        limit: fused.length,
      )).toSet();
      fused = [
        for (final f in fused)
          if (allowed.contains(f.id)) f,
      ];
      for (final f in fused) {
        (foundBy[f.id] ??= {}).add(RetrievalStrategy.structured);
      }
    }
    if (fused.isEmpty) {
      return RetrievalResult(hits: const [], strategiesUsed: used);
    }

    final cards = await _search.cards([for (final f in fused) f.id]);
    final prior = {for (final f in fused) f.id: f.score};
    final ordered = text == null
        ? [for (final card in cards) (card, prior[card.id] ?? 0.0)]
        : await _rerank(text, cards, prior);

    return RetrievalResult(
      hits: [
        for (final (card, score) in ordered.take(limit))
          RankedMemory(
            card: card,
            score: score,
            foundBy: foundBy[card.id] ?? const {RetrievalStrategy.structured},
          ),
      ],
      strategiesUsed: used,
    );
  }

  Future<List<ScoredId>?> _semantic(String text, Set<String>? within) async {
    try {
      final embeddings = await _router.embeddings();
      final vectors = await embeddings.service.embed([
        text,
      ], purpose: EmbeddingPurpose.query);
      if (vectors.isEmpty) return null;
      return await _vectors.search(
        vectors.first,
        embeddings.service.model,
        within: within,
        limit: strategyLimit,
      );
    } on CapabilityUnavailableException {
      return null;
    } on Exception {
      // Semantic search is an extra. Text and filters still answer.
      return null;
    }
  }

  Future<List<(MemoryCard, double)>> _rerank(
    String text,
    List<MemoryCard> cards,
    Map<String, double> prior,
  ) async {
    final candidates = [
      for (final card in cards)
        RerankCandidate(
          id: card.id,
          text: cardSearchText(card),
          priorScore: prior[card.id] ?? 0,
        ),
    ];
    RerankService reranker;
    try {
      reranker = (await _router.reranker()).service;
    } on CapabilityUnavailableException {
      reranker = _fallbackReranker;
    }
    List<RerankScore> scores;
    try {
      scores = await reranker.rerank(text, candidates);
    } on Exception {
      scores = await _fallbackReranker.rerank(text, candidates);
    }

    final byId = {for (final card in cards) card.id: card};
    final position = {for (var i = 0; i < scores.length; i++) scores[i].id: i};
    final ranked = [
      for (final s in scores)
        if (byId[s.id] != null) (byId[s.id]!, s.score),
    ];
    ranked.sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      return byScore != 0
          ? byScore
          : position[a.$1.id]!.compareTo(position[b.$1.id]!);
    });
    final seen = {for (final (card, _) in ranked) card.id};
    return [
      ...ranked,
      for (final card in cards)
        if (!seen.contains(card.id)) (card, prior[card.id] ?? 0.0),
    ];
  }

  /// The text a reranker sees for a card: summary, category and key facts.
  static String cardSearchText(MemoryCard card) => [
    card.summary ?? '',
    (card.category ?? '').replaceAll('_', ' '),
    for (final fact in card.facts.entries)
      '${fact.key.replaceAll('_', ' ')} ${fact.value}',
  ].where((part) => part.isNotEmpty).join('. ');
}
