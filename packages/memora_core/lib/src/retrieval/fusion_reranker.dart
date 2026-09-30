import '../ai/capabilities.dart';
import '../text/category_words.dart';
import '../text/normalize.dart';

/// The on-device reranker: the first-stage score plus exact name matches, a
/// category match and a small recency tie-break. See docs/architecture.md,
/// section 8.2.
///
/// A candidate that carries no entities, category or date is still scored on
/// word overlap, so this works with whatever a store can supply.
class FusionReranker implements RerankService {
  const FusionReranker();

  /// Added for each query word found in the candidate text. A word matches a
  /// candidate word that equals it or, for words of three or more letters,
  /// starts with it, the way full-text search treats prefixes.
  static const wordBonus = 0.15;
  static const maxWordBonus = 0.6;

  /// Added for each name in the question that this memory actually carries.
  static const entityBonus = 0.25;
  static const maxEntityBonus = 0.5;

  /// Added when the question names this memory's category.
  static const categoryBonus = 0.2;

  /// The most the newest candidate can gain over the oldest.
  ///
  /// Recency breaks ties and nothing more, so this has to stay under the gap
  /// reciprocal rank fusion leaves between neighbouring positions. With k =
  /// 60 that gap is 1/61 - 1/62, about 2.6e-4 at the top and about 1.2e-4 at
  /// the bottom of the reranked window. A bonus as large as the gap reorders
  /// results that differ only in rank, which put the one semantic match
  /// behind three memories that matched nothing.
  static const recencyBonus = 0.00001;

  static final _words = RegExp(r'[\p{L}\p{M}\p{N}]+', unicode: true);

  @override
  Future<List<RerankScore>> rerank(
    String query,
    List<RerankCandidate> candidates,
  ) async {
    final queryWords = searchTokens(query);
    final asked = foldForMatch(query);
    final wantedCategories = categoriesForWords(queryWords);
    final recency = _recency(candidates);

    final scored = <(RerankScore, int)>[];
    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      final words = {
        for (final m in _words.allMatches(foldForMatch(candidate.text))) m[0]!,
      };
      final wordMatches = queryWords.where((q) {
        return words.any((w) => w == q || (q.length >= 3 && w.startsWith(q)));
      }).length;
      final entityMatches = candidate.entities
          .where((e) => e.trim().isNotEmpty && asked.contains(foldForMatch(e)))
          .length;
      var score =
          candidate.priorScore +
          _cap(wordMatches * wordBonus, maxWordBonus) +
          _cap(entityMatches * entityBonus, maxEntityBonus);
      if (candidate.category != null &&
          wantedCategories.contains(candidate.category)) {
        score += categoryBonus;
      }
      score += recencyBonus * (recency[candidate.id] ?? 0);
      scored.add((RerankScore(candidate.id, score), i));
    }
    scored.sort((a, b) {
      final byScore = b.$1.score.compareTo(a.$1.score);
      return byScore != 0 ? byScore : a.$2.compareTo(b.$2);
    });
    return [for (final (score, _) in scored) score];
  }

  static double _cap(double value, double limit) =>
      value > limit ? limit : value;

  /// Where each candidate sits between the oldest (0) and the newest (1) of
  /// the ones that carry a date.
  Map<String, double> _recency(List<RerankCandidate> candidates) {
    final dated = [
      for (final c in candidates)
        if (c.takenAt != null) c,
    ]..sort((a, b) => a.takenAt!.compareTo(b.takenAt!));
    if (dated.length < 2) return const {};
    return {
      for (var i = 0; i < dated.length; i++)
        dated[i].id: i / (dated.length - 1),
    };
  }
}
