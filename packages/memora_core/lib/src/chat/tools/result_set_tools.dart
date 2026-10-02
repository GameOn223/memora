import '../../model/conversation.dart';
import '../../model/retrieval.dart';
import '../../ports/stores.dart';
import '../aggregation.dart';
import '../query_labels.dart';
import '../query_parser.dart';
import 'search_tools.dart';
import 'tool.dart';

/// Finds the result set a tool should work on: the one named in the
/// arguments, or the conversation's most recent one.
Future<ResultSet> resolveResultSet(ToolArgs args, ToolContext context) async {
  final id = args.string('result_set_id', maxLength: 64);
  if (id != null) {
    final set = await context.conversations.getResultSet(id);
    if (set == null || set.conversationId != context.conversationId) {
      throw ToolArgumentException(
        'No result set with id "$id" in this conversation.',
      );
    }
    return set;
  }
  final latest = await context.conversations.latestResultSet(
    context.conversationId,
  );
  if (latest == null) {
    throw const ToolArgumentException(
      'There are no earlier results to work with. Search first.',
    );
  }
  return latest;
}

class FilterResultsTool extends SearchTool {
  const FilterResultsTool(super.retrieval);

  @override
  String get name => 'filter_results';

  @override
  String get description =>
      'Narrow the memories found earlier with more filters, without '
      'searching again.';

  @override
  Map<String, Object?> get parameters => ToolSchemas.object({
    'result_set_id': ToolSchemas.resultSetId,
    'categories': ToolSchemas.categories,
    'entity': ToolSchemas.entity,
    'entity_type': ToolSchemas.entityType,
    'amount_min': ToolSchemas.amountMin,
    'amount_max': ToolSchemas.amountMax,
    'currency': ToolSchemas.currency,
    'date_from': ToolSchemas.dateFrom,
    'date_to': ToolSchemas.dateTo,
  });

  @override
  Future<ToolResult> execute(ToolArgs args, ToolContext context) async {
    final set = await resolveResultSet(args, context);
    final filters = RetrievalQuery(
      categories: args.strings('categories').toSet(),
      entities: [?args.entityFilter()],
      attributes: [?args.amountFilter()],
      takenBetween: args.dateRange(),
      strategies: const {RetrievalStrategy.structured},
      limit: RetrievalQuery.maxLimit,
    );
    if (!filters.hasFilters) {
      throw const ToolArgumentException(
        'Give at least one filter: categories, entity, amount_min, '
        'amount_max, date_from or date_to.',
      );
    }
    final result = await runSearch(
      filters.copyWith(within: set.memoryIds.toSet()),
      context,
      sources: SearchTool.filterLabels(filters),
      description: '${set.description}; ${describeQuery(filters)}',
    );
    if (result is! ToolSuccess) return result;
    return ToolSuccess(
      result.json,
      traceSummary:
          '${result.memoryIds.length} of ${set.memoryIds.length} kept',
      memoryIds: result.memoryIds,
      resultSetId: result.resultSetId,
      scores: result.scores,
      sources: result.sources,
    );
  }
}

class AggregateResultsTool extends MemoraTool {
  const AggregateResultsTool(this._search);

  final SearchStore _search;

  @override
  String get name => 'aggregate_results';

  @override
  String get description =>
      'Take the largest, smallest, total, average, count or latest of a '
      'stored fact across the memories found earlier.';

  @override
  Map<String, Object?> get parameters => ToolSchemas.object(
    {
      'op': {
        'type': 'string',
        'enum': ['max', 'min', 'sum', 'avg', 'count', 'latest'],
        'description': 'Which figure to work out.',
      },
      'attribute': {
        'type': 'string',
        'description':
            'Fact to work on, such as amount or due_date. Defaults to amount. '
            'Leave it out with count to count the memories themselves.',
      },
      'result_set_id': ToolSchemas.resultSetId,
    },
    required: ['op'],
  );

  static const _ops = {
    'max': AggregateOp.max,
    'min': AggregateOp.min,
    'sum': AggregateOp.sum,
    'avg': AggregateOp.avg,
    'count': AggregateOp.count,
    'latest': AggregateOp.latest,
  };

  @override
  Future<ToolResult> execute(ToolArgs args, ToolContext context) async {
    final op = _ops[args.oneOf('op', _ops.keys.toList())]!;
    final set = await resolveResultSet(args, context);
    final given = args.string('attribute', maxLength: 60);
    final overMemories =
        given == null && (op == AggregateOp.count || op == AggregateOp.latest);
    final attribute = overMemories ? null : (given ?? 'amount');

    final outcome = await Aggregator(_search)
        .run(set.memoryIds, op, attribute: attribute);

    if (!outcome.hasValue) {
      final label = attributeLabel(attribute ?? 'amount');
      final count = set.memoryIds.length;
      return ToolError(switch (outcome.problem) {
        AggregateProblem.notNumeric =>
          '$label holds dates, so it has no total or average. Use max or '
              'min instead.',
        _ when count == 1 =>
          "The memory in this result set doesn't have ${articleFor(label)}.",
        _ =>
          'None of the $count memories in this result set have '
              '${articleFor(label)}.',
      });
    }
    return ToolSuccess(
      outcome.toToolJson(),
      traceSummary: outcome.display ?? '',
      memoryIds: op == AggregateOp.count ? const [] : outcome.memoryIds,
      aggregate: outcome,
    );
  }
}
