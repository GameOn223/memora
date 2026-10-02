import '../model/retrieval.dart';

/// Merges ranked lists with reciprocal rank fusion.
///
/// Each list adds `1 / (k + rank)` for every id it contains, with ranks
/// starting at 1. Only ranks matter, so scores from different strategies
/// never need calibrating against each other. An id repeated within one list
/// counts once, and ties keep the order in which ids first appeared.
List<ScoredId> reciprocalRankFusion(
  List<List<ScoredId>> rankings, {
  int k = 60,
}) {
  final scores = <String, double>{};
  for (final ranking in rankings) {
    final seen = <String>{};
    var rank = 0;
    for (final item in ranking) {
      if (!seen.add(item.id)) continue;
      rank++;
      scores[item.id] = (scores[item.id] ?? 0) + 1 / (k + rank);
    }
  }
  final order = scores.keys.toList();
  final position = {for (var i = 0; i < order.length; i++) order[i]: i};
  order.sort((a, b) {
    final byScore = scores[b]!.compareTo(scores[a]!);
    return byScore != 0 ? byScore : position[a]!.compareTo(position[b]!);
  });
  return [for (final id in order) ScoredId(id, scores[id]!)];
}
