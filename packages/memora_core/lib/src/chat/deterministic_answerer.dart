import 'package:meta/meta.dart';

import '../model/conversation.dart';
import '../model/retrieval.dart';
import '../ports/platform.dart';
import '../ports/stores.dart';
import '../services/contracts.dart';
import '../text/dates.dart';
import 'aggregation.dart';
import 'query_labels.dart';
import 'query_parser.dart';

/// A reply built from search alone, for when no chat model is available.
@immutable
class DeterministicAnswer {
  const DeterministicAnswer({
    required this.text,
    required this.hits,
    required this.presentation,
    required this.trace,
    required this.query,
    this.aggregate,
  });

  final String text;
  final List<RankedMemory> hits;
  final MessagePresentation presentation;

  /// What was searched, in the same shape as agent tool calls.
  final List<ToolTraceEntry> trace;

  /// The query that ran, including any `within` restriction.
  final RetrievalQuery query;
  final AggregateOutcome? aggregate;
}

/// Answers questions with [QueryParser], hybrid search and aggregates. The
/// replies are plain and clearly labeled as search-only. See
/// docs/architecture.md, section 9.2.
class DeterministicAnswerer {
  DeterministicAnswerer({
    required this._retrieval,
    required this._search,
    required this._clock,
    this._parser = const QueryParser(),
  });

  final RetrievalEngine _retrieval;
  final SearchStore _search;
  final Clock _clock;
  final QueryParser _parser;

  /// Answers [text]. [within] restricts the search, for follow-ups on the
  /// previous results or a single focused memory.
  Future<DeterministicAnswer> answer(String text, {Set<String>? within}) async {
    final parsed = _parser.parse(text, now: _clock.now());
    final query = within == null
        ? parsed.query
        : parsed.query.copyWith(within: within);
    final result = await _retrieval.search(query);
    final hits = result.hits;
    final trace = [
      ToolTraceEntry(
        tool: 'search_memories',
        arguments: queryArguments(query),
        summary: candidatesCount(hits.length),
      ),
    ];
    final label = sourceLabel(hits.length, [
      for (final strategy in RetrievalStrategy.values)
        if (result.strategiesUsed.contains(strategy)) strategyLabel(strategy),
    ]);

    DeterministicAnswer reply(
      String text, {
      MessagePresentation? presentation,
      AggregateOutcome? aggregate,
    }) => DeterministicAnswer(
      text: text,
      hits: hits,
      presentation:
          presentation ??
          MessagePresentation(sourceLabel: label, searchOnly: true),
      trace: trace,
      query: query,
      aggregate: aggregate,
    );

    if (hits.isEmpty) return reply('No memories matched.');

    final found = 'Found ${memoriesCount(hits.length)}';
    final intent = parsed.aggregate;
    if (intent == null) return reply('$found.');

    final ids = [for (final hit in hits) hit.card.id];
    final byId = {for (final hit in hits) hit.card.id: hit.card};
    final outcome = await Aggregator(_search).run(
      ids,
      intent.op,
      attribute:
          intent.op == AggregateOp.count || intent.op == AggregateOp.latest
          ? null
          : intent.attribute,
    );
    trace.add(
      ToolTraceEntry(
        tool: 'aggregate_results',
        arguments: {
          'op': intent.op.name,
          if (outcome.attribute != null) 'attribute': outcome.attribute,
        },
        summary: outcome.display ?? 'no values',
      ),
    );

    final attribute = intent.attribute.replaceAll('_', ' ');
    if (!outcome.hasValue) {
      final article = RegExp('^[aeiou]').hasMatch(attribute) ? 'an' : 'a';
      return reply(
        hits.length == 1
            ? "$found, but it doesn't have $article $attribute."
            : '$found, but none of them have $article $attribute.',
        aggregate: outcome,
      );
    }

    switch (intent.op) {
      case AggregateOp.count:
        return reply(
          '$found.',
          presentation: MessagePresentation(
            headline: outcome.display,
            sourceLabel: label,
            searchOnly: true,
          ),
          aggregate: outcome,
        );
      case AggregateOp.latest:
        final card = byId[outcome.memoryId]!;
        final name = card.summary?.trim().isNotEmpty == true
            ? card.summary!.trim()
            : 'a memory';
        return reply(
          '$found. The latest is $name from ${displayDate(card.takenAt)}.',
          presentation: MessagePresentation(
            highlightMemoryId: card.id,
            sourceLabel: label,
            searchOnly: true,
          ),
          aggregate: outcome,
        );
      case AggregateOp.max ||
          AggregateOp.min ||
          AggregateOp.sum ||
          AggregateOp.avg:
        final word = switch (intent.op) {
          AggregateOp.max => 'highest',
          AggregateOp.min => 'lowest',
          AggregateOp.sum => 'total',
          _ => 'average',
        };
        final single = outcome.memoryId == null ? null : byId[outcome.memoryId];
        final when = single == null ? '' : ' (${displayMonth(single.takenAt)})';
        final skippedNote = switch (outcome.skipped) {
          0 => '',
          1 => ' 1 $attribute in another currency was left out.',
          final n => ' $n ${attribute}s in other currencies were left out.',
        };
        return reply(
          '$found. The $word $attribute is ${outcome.display}$when.'
          '$skippedNote',
          presentation: MessagePresentation(
            layout: SourceLayout.table,
            tableAttribute: intent.attribute,
            headline: outcome.display,
            highlightMemoryId: single?.id,
            sourceLabel: label,
            searchOnly: true,
          ),
          aggregate: outcome,
        );
    }
  }
}
