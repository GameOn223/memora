import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

void main() {
  test('scores each list by 1 / (k + rank)', () {
    final fused = reciprocalRankFusion([
      const [ScoredId('a', 9), ScoredId('b', 3)],
    ]);
    expect(fused.map((s) => s.id), ['a', 'b']);
    expect(fused[0].score, closeTo(1 / 61, 1e-12));
    expect(fused[1].score, closeTo(1 / 62, 1e-12));
  });

  test('items found by several strategies rise to the top', () {
    final fused = reciprocalRankFusion([
      const [ScoredId('a', 1), ScoredId('b', 1), ScoredId('c', 1)],
      const [ScoredId('c', 1), ScoredId('d', 1)],
    ]);
    expect(fused.first.id, 'c');
    expect(fused.first.score, closeTo(1 / 63 + 1 / 61, 1e-12));
    expect(fused.map((s) => s.id).toSet(), {'a', 'b', 'c', 'd'});
  });

  test('ties keep the order of first appearance', () {
    final fused = reciprocalRankFusion([
      const [ScoredId('x', 1)],
      const [ScoredId('y', 1)],
      const [ScoredId('z', 1)],
    ]);
    expect(fused.map((s) => s.id), ['x', 'y', 'z']);
  });

  test('a repeated id in one list only counts once', () {
    final fused = reciprocalRankFusion([
      const [ScoredId('a', 1), ScoredId('a', 1), ScoredId('b', 1)],
    ]);
    expect(fused.map((s) => s.id), ['a', 'b']);
    expect(fused[1].score, closeTo(1 / 62, 1e-12));
  });

  test('k is configurable and empty input gives nothing', () {
    expect(reciprocalRankFusion(const []), isEmpty);
    final fused = reciprocalRankFusion([
      const [ScoredId('a', 1)],
    ], k: 1);
    expect(fused.single.score, 0.5);
  });
}
