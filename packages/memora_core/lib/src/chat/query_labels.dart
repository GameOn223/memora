/// Short descriptions of searches for traces, result sets and captions.
library;

import '../model/retrieval.dart';
import '../text/dates.dart';

/// `1 memory` or `3 memories`.
String memoriesCount(int count) => count == 1 ? '1 memory' : '$count memories';

/// `1 candidate` or `8 candidates`, as shown in "How this was found".
String candidatesCount(int count) =>
    count == 1 ? '1 candidate' : '$count candidates';

/// The word used for a strategy in source captions.
String strategyLabel(RetrievalStrategy strategy) => switch (strategy) {
  RetrievalStrategy.structured => 'filters',
  RetrievalStrategy.text => 'text',
  RetrievalStrategy.semantic => 'semantic',
};

/// A caption above sources such as `8 memories · entity + semantic`. Null
/// when there are no sources.
String? sourceLabel(int count, Iterable<String> parts) {
  if (count == 0) return null;
  final unique = <String>{...parts};
  return unique.isEmpty
      ? memoriesCount(count)
      : '${memoriesCount(count)} · ${unique.join(' + ')}';
}

/// The last day inside an exclusive range end, for display.
DateTime _lastDay(DateTime end) => DateTime(end.year, end.month, end.day - 1);

/// Tool-style arguments describing a query, for a trace entry.
Map<String, Object?> queryArguments(RetrievalQuery query) {
  final range = query.takenBetween;
  final args = <String, Object?>{
    if (query.hasText) 'text': query.text!.trim(),
    if (query.categories.isNotEmpty)
      'category': (query.categories.toList()..sort()).join(', '),
    if (range?.start != null) 'date_from': isoDate(range!.start!),
    if (range?.end != null) 'date_to': isoDate(_lastDay(range!.end!)),
    if (query.within != null) 'within': query.within!.length,
  };
  for (final entity in query.entities) {
    args['entity'] = entity.value;
    if (entity.type != null) args['entity_type'] = entity.type;
  }
  for (final attribute in query.attributes) {
    final prefix = attribute.type;
    if (attribute.min != null) args['${prefix}_min'] = _number(attribute.min!);
    if (attribute.max != null) args['${prefix}_max'] = _number(attribute.max!);
    if (attribute.equals != null) args[prefix] = attribute.equals;
    if (attribute.currency != null) args['currency'] = attribute.currency;
    final dates = attribute.dateRange;
    if (dates?.start != null) args['${prefix}_from'] = isoDate(dates!.start!);
    if (dates?.end != null) {
      args['${prefix}_to'] = isoDate(_lastDay(dates!.end!));
    }
  }
  return args;
}

/// A one-line description of a query for a result set, such as
/// `category=utility_bill, entity=Reliance`.
String describeQuery(RetrievalQuery query) {
  final args = queryArguments(query);
  if (args.isEmpty) return 'all memories';
  return [for (final e in args.entries) '${e.key}=${e.value}'].join(', ');
}

Object _number(double value) =>
    value == value.roundToDouble() ? value.round() : value;
