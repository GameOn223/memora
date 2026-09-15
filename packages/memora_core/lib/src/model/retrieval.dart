import 'package:meta/meta.dart';

import 'memory.dart';

/// An inclusive range of calendar dates, compared in local time.
@immutable
class DateRange {
  const DateRange({this.start, this.end})
    : assert(start != null || end != null, 'A range needs at least one bound');

  /// A whole calendar day in local time.
  factory DateRange.day(DateTime day) {
    final start = DateTime(day.year, day.month, day.day);
    return DateRange(start: start, end: start.add(const Duration(days: 1)));
  }

  /// A whole calendar month in local time.
  factory DateRange.month(int year, int month) =>
      DateRange(start: DateTime(year, month), end: DateTime(year, month + 1));

  /// A whole calendar year in local time.
  factory DateRange.year(int year) =>
      DateRange(start: DateTime(year), end: DateTime(year + 1));

  /// First instant included. Null means open-ended.
  final DateTime? start;

  /// First instant excluded. Null means open-ended.
  final DateTime? end;

  bool contains(DateTime instant) =>
      (start == null || !instant.isBefore(start!)) &&
      (end == null || instant.isBefore(end!));

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'DateRange($start, $end)';
}

/// Match memories that mention an entity.
@immutable
class EntityFilter {
  const EntityFilter({required this.value, this.type});

  final String value;

  /// Optional entity type such as `company`. Null matches any type.
  final String? type;

  @override
  bool operator ==(Object other) =>
      other is EntityFilter && other.value == value && other.type == type;

  @override
  int get hashCode => Object.hash(value, type);
}

/// Match memories with an attribute of a given type, optionally in a range.
@immutable
class AttributeFilter {
  const AttributeFilter({
    required this.type,
    this.min,
    this.max,
    this.currency,
    this.dateRange,
    this.equals,
  });

  /// For example `amount`, `due_date`, `order_number`.
  final String type;

  /// Inclusive lower bound on the numeric value.
  final double? min;

  /// Inclusive upper bound on the numeric value.
  final double? max;
  final String? currency;

  /// Range on the attribute's date value, for date attributes.
  final DateRange? dateRange;

  /// Exact match on the displayed value, case-insensitive.
  final String? equals;

  @override
  bool operator ==(Object other) =>
      other is AttributeFilter &&
      other.type == type &&
      other.min == min &&
      other.max == max &&
      other.currency == currency &&
      other.dateRange == dateRange &&
      other.equals == equals;

  @override
  int get hashCode => Object.hash(type, min, max, currency, dateRange, equals);
}

/// The search strategies hybrid retrieval can combine.
enum RetrievalStrategy { structured, text, semantic }

/// Everything a search can ask for. See docs/architecture.md, section 8.1.
@immutable
class RetrievalQuery {
  const RetrievalQuery({
    this.text,
    this.categories = const {},
    this.entities = const [],
    this.attributes = const [],
    this.takenBetween,
    this.statuses = const {},
    this.within,
    this.strategies = const {
      RetrievalStrategy.structured,
      RetrievalStrategy.text,
      RetrievalStrategy.semantic,
    },
    this.limit = 20,
  });

  static const maxLimit = 50;

  final String? text;
  final Set<String> categories;
  final List<EntityFilter> entities;
  final List<AttributeFilter> attributes;
  final DateRange? takenBetween;
  final Set<ProcessingStatus> statuses;

  /// Restrict results to these memory ids, used to narrow a result set.
  final Set<String>? within;
  final Set<RetrievalStrategy> strategies;
  final int limit;

  bool get hasText => text != null && text!.trim().isNotEmpty;

  bool get hasFilters =>
      categories.isNotEmpty ||
      entities.isNotEmpty ||
      attributes.isNotEmpty ||
      takenBetween != null ||
      statuses.isNotEmpty ||
      within != null;

  int get effectiveLimit => limit.clamp(1, maxLimit);

  RetrievalQuery copyWith({
    String? text,
    Set<String>? categories,
    List<EntityFilter>? entities,
    List<AttributeFilter>? attributes,
    DateRange? takenBetween,
    Set<String>? within,
    Set<RetrievalStrategy>? strategies,
    int? limit,
  }) {
    return RetrievalQuery(
      text: text ?? this.text,
      categories: categories ?? this.categories,
      entities: entities ?? this.entities,
      attributes: attributes ?? this.attributes,
      takenBetween: takenBetween ?? this.takenBetween,
      statuses: statuses,
      within: within ?? this.within,
      strategies: strategies ?? this.strategies,
      limit: limit ?? this.limit,
    );
  }
}

/// A memory id with a score from one strategy. Higher is better.
@immutable
class ScoredId {
  const ScoredId(this.id, this.score);

  final String id;
  final double score;

  @override
  bool operator ==(Object other) =>
      other is ScoredId && other.id == id && other.score == score;

  @override
  int get hashCode => Object.hash(id, score);

  @override
  String toString() => 'ScoredId($id, ${score.toStringAsFixed(4)})';
}

/// A compact view of a memory: what the chat model and source cards see.
@immutable
class MemoryCard {
  const MemoryCard({
    required this.id,
    required this.takenAt,
    required this.status,
    this.summary,
    this.category,
    this.thumbnailPath,
    this.facts = const {},
  });

  final String id;
  final DateTime takenAt;
  final ProcessingStatus status;
  final String? summary;
  final String? category;
  final String? thumbnailPath;

  /// Key attributes as display strings, for example `{'amount': '₹1,842'}`.
  final Map<String, String> facts;

  Map<String, Object?> toToolJson() => {
    'id': id,
    'taken': _isoDate(takenAt),
    'summary': ?summary,
    'category': ?category,
    if (facts.isNotEmpty) 'facts': facts,
  };
}

/// One search hit after fusion and reranking.
@immutable
class RankedMemory {
  const RankedMemory({
    required this.card,
    required this.score,
    required this.foundBy,
  });

  final MemoryCard card;
  final double score;

  /// Which strategies returned this memory. Feeds "How this was found".
  final Set<RetrievalStrategy> foundBy;
}

String _isoDate(DateTime d) {
  final local = d.toLocal();
  final m = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  return '${local.year}-$m-$day';
}
