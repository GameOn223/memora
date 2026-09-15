import 'package:memora_core/memora_core.dart';

import 'fake_memora_state.dart';

const _identifierTypes = [
  'booking_reference',
  'order_number',
  'invoice_number',
  'tracking_number',
];

final _docTokens = RegExp(r'[\p{L}\p{M}\p{N}]+', unicode: true);

/// In-memory [SearchStore]. Full-text scoring counts matching tokens, which
/// is enough to rank obvious matches above weak ones.
mixin FakeSearchStore on FakeMemoraState implements SearchStore {
  /// Every text query passed to [fullText], for assertions.
  final List<String> fullTextQueries = [];

  bool _matchesAttribute(MemoryRow r, AttributeFilter f) {
    return r.attributes.any((a) {
      if (a.type != f.type) return false;
      if (f.currency != null &&
          a.currency?.toUpperCase() != f.currency!.toUpperCase()) {
        return false;
      }
      if (f.min != null && (a.valueNum == null || a.valueNum! < f.min!)) {
        return false;
      }
      if (f.max != null && (a.valueNum == null || a.valueNum! > f.max!)) {
        return false;
      }
      if (f.dateRange != null) {
        final date = a.valueDate == null ? null : parseIsoDate(a.valueDate!);
        if (date == null || !f.dateRange!.contains(date)) return false;
      }
      if (f.equals != null &&
          a.value.toLowerCase() != f.equals!.toLowerCase()) {
        return false;
      }
      return true;
    });
  }

  bool _matchesEntity(MemoryRow r, EntityFilter f) {
    final needle = foldForMatch(f.value);
    return r.entities.any(
      (e) =>
          (f.type == null || e.type == f.type) &&
          e.normalizedValue.contains(needle),
    );
  }

  int _newestFirst(MemoryRow a, MemoryRow b) {
    final byTaken = b.takenAt.compareTo(a.takenAt);
    return byTaken != 0 ? byTaken : b.seq.compareTo(a.seq);
  }

  @override
  Future<List<String>> structured(
    RetrievalQuery query, {
    int limit = 500,
  }) async {
    final matches = liveRows.where((r) {
      if (query.within != null && !query.within!.contains(r.id)) return false;
      if (query.categories.isNotEmpty &&
          !query.categories.contains(r.category)) {
        return false;
      }
      if (query.statuses.isNotEmpty && !query.statuses.contains(r.status)) {
        return false;
      }
      if (query.takenBetween != null &&
          !query.takenBetween!.contains(r.takenAt)) {
        return false;
      }
      if (!query.entities.every((f) => _matchesEntity(r, f))) return false;
      return query.attributes.every((f) => _matchesAttribute(r, f));
    }).toList()..sort(_newestFirst);
    return [for (final r in matches.take(limit)) r.id];
  }

  @override
  Future<List<ScoredId>> fullText(
    String text, {
    Set<String>? within,
    int limit = 50,
  }) async {
    fullTextQueries.add(text);
    final tokens = searchTokens(text);
    if (tokens.isEmpty) return const [];
    final scored = <(MemoryRow, double)>[];
    for (final r in liveRows) {
      if (within != null && !within.contains(r.id)) continue;
      final doc = foldForMatch(
        [
          r.summary ?? '',
          r.extractedText ?? '',
          r.visualDescription ?? '',
          r.keywords.join(' '),
          r.entities.map((e) => e.value).join(' '),
        ].join(' '),
      );
      var score = 0.0;
      for (final match in _docTokens.allMatches(doc)) {
        final word = match[0]!;
        if (tokens.any(
          (t) => word == t || (t.length >= 3 && word.startsWith(t)),
        )) {
          score += 1;
        }
      }
      if (score > 0) scored.add((r, score));
    }
    scored.sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      return byScore != 0 ? byScore : _newestFirst(a.$1, b.$1);
    });
    return [for (final (r, s) in scored.take(limit)) ScoredId(r.id, s)];
  }

  @override
  Future<List<MemoryCard>> cards(List<String> ids) async => [
    for (final id in ids)
      if (rows[id] case final r? when r.status != ProcessingStatus.deleted)
        MemoryCard(
          id: r.id,
          takenAt: r.takenAt,
          status: r.status,
          summary: r.summary,
          category: r.category,
          thumbnailPath: r.thumbnailPath,
          facts: _facts(r),
        ),
  ];

  Map<String, String> _facts(MemoryRow r) {
    final facts = <String, String>{};
    for (final a in r.attributes) {
      if (a.type == 'amount') {
        facts['amount'] = a.value;
        break;
      }
    }
    for (final a in r.attributes) {
      if (a.valueDate != null) {
        facts[a.type] = a.value;
        break;
      }
    }
    for (final a in r.attributes) {
      if (_identifierTypes.contains(a.type)) {
        facts[a.type] = a.value;
        break;
      }
    }
    return facts;
  }

  @override
  Future<List<AttributeValue>> attributeValues(
    List<String> ids,
    String type,
  ) async => [
    for (final id in ids)
      if (rows[id] case final r?)
        for (final a in r.attributes)
          if (a.type == type)
            AttributeValue(memoryId: id, attribute: a, takenAt: r.takenAt),
  ];

  @override
  Future<List<ScoredId>> sharingEntities(
    String memoryId, {
    int limit = 20,
  }) async {
    final source = rows[memoryId];
    if (source == null) return const [];
    final values = {for (final e in source.entities) e.normalizedValue};
    final scored = <(MemoryRow, int)>[];
    for (final r in liveRows) {
      if (r.id == memoryId) continue;
      final shared = r.entities
          .map((e) => e.normalizedValue)
          .toSet()
          .intersection(values)
          .length;
      if (shared > 0) scored.add((r, shared));
    }
    scored.sort((a, b) {
      final byShared = b.$2.compareTo(a.$2);
      return byShared != 0 ? byShared : _newestFirst(a.$1, b.$1);
    });
    return [
      for (final (r, s) in scored.take(limit)) ScoredId(r.id, s.toDouble()),
    ];
  }
}
