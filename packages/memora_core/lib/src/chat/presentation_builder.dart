import 'package:meta/meta.dart';

import '../model/conversation.dart';
import '../ports/stores.dart';
import 'aggregation.dart';
import 'query_labels.dart';
import 'query_parser.dart';

/// A figure shown above the sources that came from one memory's attribute.
/// Only these can be checked against the original image.
@immutable
class HeadlineSource {
  const HeadlineSource({
    required this.memoryId,
    required this.attributeType,
    required this.value,
  });

  final String memoryId;
  final String attributeType;
  final String value;
}

@immutable
class PresentationDraft {
  const PresentationDraft(this.presentation, {this.source});

  final MessagePresentation presentation;
  final HeadlineSource? source;
}

/// Chooses how an answer's sources are shown. See docs/architecture.md,
/// section 9.3.
class PresentationBuilder {
  const PresentationBuilder(this._search);

  final SearchStore _search;

  static final _comparisonWords = RegExp(
    r'(?<![a-z])(compare|comparison|versus|vs|highest|lowest|most|least|'
    r'cheapest|expensive|biggest|smallest|largest|difference|each|every|'
    r'trend|breakdown|per month|month by month|between)(?![a-z])',
  );

  static final _valueQuestion = RegExp(
    r'(?<![a-z])(how much|how many|what.{0,20}(amount|total|price|cost|fare|'
    r'bill|due)|amount|total|price|cost|fare|balance|due)(?![a-z])',
  );

  Future<PresentationDraft> build({
    required String question,
    required List<String> citedIds,
    AggregateOutcome? aggregate,
    bool aggregateWasLast = false,
    Set<String> sources = const {},
  }) async {
    final asked = question.toLowerCase();
    final label = sourceLabel(citedIds.length, sources);
    final fromAggregate = aggregateWasLast && (aggregate?.hasValue ?? false);

    var attribute = aggregate?.attribute ?? 'amount';
    var table = fromAggregate;
    String? headline;
    String? highlight;
    HeadlineSource? source;

    if (fromAggregate) {
      headline = aggregate!.display;
      final single =
          aggregate.op == AggregateOp.max ||
          aggregate.op == AggregateOp.min ||
          aggregate.op == AggregateOp.latest;
      highlight = single ? aggregate.memoryId : null;
      if (single && aggregate.memoryId != null && aggregate.attribute != null) {
        source = HeadlineSource(
          memoryId: aggregate.memoryId!,
          attributeType: aggregate.attribute!,
          value: headline!,
        );
      }
      if (aggregate.op == AggregateOp.count) table = false;
    }

    if (citedIds.length >= 2 && _comparisonWords.hasMatch(asked)) {
      final shared = await _search.attributeValues(citedIds, attribute);
      if ({for (final v in shared) v.memoryId}.length >= 2) table = true;
    }

    if (headline == null &&
        citedIds.length == 1 &&
        _valueQuestion.hasMatch(asked)) {
      final values = await _search.attributeValues(citedIds, 'amount');
      if (values.isNotEmpty) {
        final value = values.first;
        headline = value.attribute.value;
        attribute = 'amount';
        source = HeadlineSource(
          memoryId: value.memoryId,
          attributeType: 'amount',
          value: headline,
        );
      }
    }

    return PresentationDraft(
      MessagePresentation(
        layout: table ? SourceLayout.table : SourceLayout.strip,
        headline: headline,
        tableAttribute: table ? attribute : null,
        highlightMemoryId: highlight,
        sourceLabel: label,
      ),
      source: source,
    );
  }
}
