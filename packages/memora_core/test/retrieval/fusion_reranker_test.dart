import 'package:memora_core/memora_core.dart';
import 'package:test/test.dart';

void main() {
  const reranker = FusionReranker();

  test('adds a bonus for each query word in the candidate text', () async {
    final scores = await reranker.rerank('reliance electricity bill', const [
      RerankCandidate(id: 'mac', text: 'MacBook comparison', priorScore: 0.05),
      RerankCandidate(
        id: 'bill',
        text: 'Reliance utility bill amount ₹2,103',
        priorScore: 0.01,
      ),
    ]);

    expect(scores.map((s) => s.id), ['bill', 'mac']);
    expect(scores[0].score, closeTo(0.01 + 0.30, 1e-9));
    expect(scores[1].score, closeTo(0.05, 1e-9));
  });

  test('matches word prefixes and folds accents', () async {
    final scores = await reranker.rerank('electric cafe', const [
      RerankCandidate(id: 'a', text: 'Electricity bill at Café Mocha'),
    ]);
    expect(scores.single.score, closeTo(0.30, 1e-9));
  });

  test('caps the bonus at 0.6', () async {
    final scores = await reranker.rerank(
      'one two three four five six seven',
      const [
        RerankCandidate(
          id: 'a',
          text: 'one two three four five six seven',
          priorScore: 0.1,
        ),
      ],
    );
    expect(scores.single.score, closeTo(0.7, 1e-9));
  });

  test('returns every candidate and keeps input order on ties', () async {
    final scores = await reranker.rerank('nothing matches', const [
      RerankCandidate(id: 'a', text: 'first'),
      RerankCandidate(id: 'b', text: 'second'),
      RerankCandidate(id: 'c', text: 'third'),
    ]);
    expect(scores.map((s) => s.id), ['a', 'b', 'c']);
  });
}
