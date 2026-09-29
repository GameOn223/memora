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

  test('a memory that carries the name asked about wins', () async {
    final scores = await reranker.rerank('reliance bill', const [
      RerankCandidate(
        id: 'talks-about-it',
        text: 'Bill splitting chat that mentions reliance',
      ),
      RerankCandidate(
        id: 'carries-it',
        text: 'Electricity bill',
        entities: ['Reliance'],
      ),
    ]);

    expect(scores.map((s) => s.id), ['carries-it', 'talks-about-it']);
    expect(scores.first.score, closeTo(0.15 + 0.25, 1e-9));
  });

  test('two names in one question cap the name bonus', () async {
    final scores = await reranker.rerank('reliance and airtel and jio', const [
      RerankCandidate(
        id: 'a',
        text: 'nothing else',
        entities: ['Reliance', 'Airtel', 'Jio'],
      ),
    ]);
    expect(scores.single.score, closeTo(FusionReranker.maxEntityBonus, 1e-9));
  });

  test('a category word in the question lifts that category', () async {
    final scores = await reranker.rerank('my receipts', const [
      RerankCandidate(id: 'note', text: 'A note', category: 'document'),
      RerankCandidate(id: 'r', text: 'Nature Basket', category: 'receipt'),
    ]);

    expect(scores.map((s) => s.id), ['r', 'note']);
    expect(scores.first.score, closeTo(FusionReranker.categoryBonus, 1e-9));
  });

  test('recency only breaks ties', () async {
    final scores = await reranker.rerank('bill', [
      RerankCandidate(
        id: 'old',
        text: 'Electricity bill',
        takenAt: DateTime(2025, 1, 1),
      ),
      RerankCandidate(
        id: 'new',
        text: 'Electricity bill',
        takenAt: DateTime(2026, 9, 1),
      ),
      RerankCandidate(
        id: 'better',
        text: 'Electricity bill for the flat',
        priorScore: 0.05,
        takenAt: DateTime(2024, 1, 1),
      ),
    ]);

    expect(scores.map((s) => s.id), ['better', 'new', 'old']);
    expect(
      scores[1].score - scores[2].score,
      closeTo(FusionReranker.recencyBonus / 2, 1e-9),
      reason: 'the three dates split the bonus evenly',
    );
  });
}
