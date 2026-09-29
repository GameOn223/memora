import '../ai/capabilities.dart';
import '../text/normalize.dart';

/// The on-device reranker: the first-stage score plus a bonus for query
/// words that appear in each candidate.
///
/// Each query word found in the candidate text adds [wordBonus], up to
/// [maxBonus]. A word matches a candidate word that equals it or, for words
/// of three or more letters, starts with it, the same way full-text search
/// treats prefixes.
class FusionReranker implements RerankService {
  const FusionReranker();

  static const wordBonus = 0.15;
  static const maxBonus = 0.6;

  static final _words = RegExp(r'[\p{L}\p{M}\p{N}]+', unicode: true);

  @override
  Future<List<RerankScore>> rerank(
    String query,
    List<RerankCandidate> candidates,
  ) async {
    final queryWords = searchTokens(query);
    final scored = <(RerankScore, int)>[];
    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      final words = {
        for (final m in _words.allMatches(foldForMatch(candidate.text))) m[0]!,
      };
      final matches = queryWords.where((q) {
        return words.any((w) => w == q || (q.length >= 3 && w.startsWith(q)));
      }).length;
      final bonus = matches * wordBonus;
      scored.add((
        RerankScore(
          candidate.id,
          candidate.priorScore + (bonus > maxBonus ? maxBonus : bonus),
        ),
        i,
      ));
    }
    scored.sort((a, b) {
      final byScore = b.$1.score.compareTo(a.$1.score);
      return byScore != 0 ? byScore : a.$2.compareTo(b.$2);
    });
    return [for (final (score, _) in scored) score];
  }
}
