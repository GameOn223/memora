import 'dart:typed_data';

import 'package:memora_core/memora_core.dart';

import 'fake_memora_state.dart';

/// In-memory [VectorStore] doing exact dot-product search.
mixin FakeVectorStore on FakeMemoraState implements VectorStore {
  @override
  Future<void> upsert(
    String memoryId,
    Float32List vector,
    EmbeddingModelInfo model,
    DateTime now,
  ) async {
    rows[memoryId]?.vectors[vectorKey(model)] = (
      vector: Float32List.fromList(vector),
      model: model,
    );
    touch();
  }

  double _dot(Float32List a, Float32List b) {
    var sum = 0.0;
    for (var i = 0; i < a.length && i < b.length; i++) {
      sum += a[i] * b[i];
    }
    return sum;
  }

  @override
  Future<List<ScoredId>> search(
    Float32List query,
    EmbeddingModelInfo model, {
    Set<String>? within,
    int limit = 50,
  }) async => _search(query, model, within: within, limit: limit);

  List<ScoredId> _search(
    Float32List query,
    EmbeddingModelInfo model, {
    Set<String>? within,
    String? exclude,
    required int limit,
  }) {
    final key = vectorKey(model);
    final scored = <ScoredId>[];
    for (final r in liveRows) {
      if (r.id == exclude) continue;
      if (within != null && !within.contains(r.id)) continue;
      final stored = r.vectors[key];
      if (stored == null) continue;
      scored.add(ScoredId(r.id, _dot(query, stored.vector)));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.take(limit).toList();
  }

  @override
  Future<List<ScoredId>> neighbours(
    String memoryId,
    EmbeddingModelInfo model, {
    int limit = 10,
  }) async {
    final stored = rows[memoryId]?.vectors[vectorKey(model)];
    if (stored == null) return const [];
    return _search(stored.vector, model, exclude: memoryId, limit: limit);
  }

  @override
  Future<List<String>> missingFor(
    EmbeddingModelInfo model, {
    int limit = 100,
  }) async {
    final key = vectorKey(model);
    final missing =
        rows.values
            .where(
              (r) =>
                  r.status == ProcessingStatus.ready &&
                  !r.vectors.containsKey(key),
            )
            .toList()
          ..sort((a, b) => a.seq.compareTo(b.seq));
    return [for (final r in missing.take(limit)) r.id];
  }

  @override
  Future<int> countFor(EmbeddingModelInfo model) async {
    final key = vectorKey(model);
    return rows.values.where((r) => r.vectors.containsKey(key)).length;
  }
}
