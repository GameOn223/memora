import '../../ai/errors.dart';
import '../../ai/router.dart';
import '../../model/conversation.dart';
import '../../model/retrieval.dart';
import '../../ports/stores.dart';
import '../../retrieval/rank_fusion.dart';
import '../../services/contracts.dart';
import '../../text/dates.dart';
import '../query_labels.dart';
import 'tool.dart';

/// Shared behavior for tools that search and save a result set.
abstract class SearchTool extends MemoraTool {
  const SearchTool(this.retrieval);

  final RetrievalEngine retrieval;

  /// How long extracted text may be when a single memory is returned.
  static const extractedTextLimit = 1500;

  Future<ToolResult> runSearch(
    RetrievalQuery query,
    ToolContext context, {
    Set<String> sources = const {},
    String? description,
  }) async {
    final result = await retrieval.search(query);
    return saveHits(
      [for (final hit in result.hits) hit.card],
      [for (final hit in result.hits) hit.score],
      context,
      description: description ?? describeQuery(query),
      sources: {
        ...sources,
        for (final strategy in result.strategiesUsed)
          if (strategy != RetrievalStrategy.structured) strategyLabel(strategy),
      },
    );
  }

  /// Turns cards into the tool's JSON and stores them as the conversation's
  /// active result set. An empty result saves nothing, so follow-up
  /// questions still work on the last set that had something in it.
  Future<ToolSuccess> saveHits(
    List<MemoryCard> cards,
    List<double> scores,
    ToolContext context, {
    required String description,
    Set<String> sources = const {},
  }) async {
    final ids = [for (final card in cards) card.id];
    final best = scores.fold(0.0, (a, b) => b > a ? b : a);
    final relevance = {
      for (var i = 0; i < cards.length; i++)
        cards[i].id: best > 0
            ? (scores[i] / best).clamp(0.0, 1.0).toDouble()
            : 1.0,
    };
    String? resultSetId;
    if (ids.isNotEmpty) {
      resultSetId = context.ids.next();
      await context.conversations.saveResultSet(
        ResultSet(
          id: resultSetId,
          conversationId: context.conversationId,
          messageId: context.messageId,
          description: description,
          memoryIds: ids,
          createdAt: context.now,
        ),
      );
    }
    return ToolSuccess(
      {
        'result_set_id': resultSetId,
        'count': ids.length,
        'memories': [for (final card in cards) card.toToolJson()],
      },
      traceSummary: candidatesCount(ids.length),
      memoryIds: ids,
      resultSetId: resultSetId,
      scores: relevance,
      sources: sources,
    );
  }

  /// Labels for the source caption, from the filters that were used.
  static Set<String> filterLabels(RetrievalQuery query) => {
    if (query.entities.isNotEmpty) 'entity',
    if (query.categories.isNotEmpty) 'category',
    if (query.takenBetween != null) 'date',
    if (query.attributes.isNotEmpty) 'amount',
  };
}

class SearchMemoriesTool extends SearchTool {
  const SearchMemoriesTool(super.retrieval);

  @override
  String get name => 'search_memories';

  @override
  String get description =>
      'Search saved memories by meaning, words and filters at once. This is '
      'the tool to reach for first.';

  @override
  Map<String, Object?> get parameters => ToolSchemas.object({
    'text': ToolSchemas.text,
    'categories': ToolSchemas.categories,
    'entity': ToolSchemas.entity,
    'entity_type': ToolSchemas.entityType,
    'amount_min': ToolSchemas.amountMin,
    'amount_max': ToolSchemas.amountMax,
    'currency': ToolSchemas.currency,
    'date_from': ToolSchemas.dateFrom,
    'date_to': ToolSchemas.dateTo,
    'limit': ToolSchemas.limit,
  });

  @override
  Future<ToolResult> execute(ToolArgs args, ToolContext context) {
    final query = RetrievalQuery(
      text: args.string('text'),
      categories: args.strings('categories').toSet(),
      entities: [?args.entityFilter()],
      attributes: [?args.amountFilter()],
      takenBetween: args.dateRange(),
      limit: args.limit(),
    );
    return runSearch(query, context, sources: SearchTool.filterLabels(query));
  }
}

class SearchMetadataTool extends SearchTool {
  const SearchMetadataTool(super.retrieval);

  @override
  String get name => 'search_metadata';

  @override
  String get description =>
      'Search by filters only, with no words to match. Use it for questions '
      'like "all bills from August".';

  @override
  Map<String, Object?> get parameters => ToolSchemas.object({
    'categories': ToolSchemas.categories,
    'entity': ToolSchemas.entity,
    'entity_type': ToolSchemas.entityType,
    'amount_min': ToolSchemas.amountMin,
    'amount_max': ToolSchemas.amountMax,
    'currency': ToolSchemas.currency,
    'date_from': ToolSchemas.dateFrom,
    'date_to': ToolSchemas.dateTo,
    'limit': ToolSchemas.limit,
  });

  @override
  Future<ToolResult> execute(ToolArgs args, ToolContext context) {
    final query = RetrievalQuery(
      categories: args.strings('categories').toSet(),
      entities: [?args.entityFilter()],
      attributes: [?args.amountFilter()],
      takenBetween: args.dateRange(),
      strategies: const {RetrievalStrategy.structured},
      limit: args.limit(),
    );
    if (!query.hasFilters) {
      throw const ToolArgumentException(
        'Give at least one filter: categories, entity, amount_min, '
        'amount_max, date_from or date_to.',
      );
    }
    return runSearch(query, context, sources: SearchTool.filterLabels(query));
  }
}

class SearchTextTool extends SearchTool {
  const SearchTextTool(super.retrieval);

  @override
  String get name => 'search_text';

  @override
  String get description =>
      'Find memories whose text contains these words. Use it for exact '
      'words, names and reference numbers.';

  @override
  Map<String, Object?> get parameters => ToolSchemas.object(
    {'text': ToolSchemas.text, 'limit': ToolSchemas.limit},
    required: ['text'],
  );

  @override
  Future<ToolResult> execute(ToolArgs args, ToolContext context) {
    return runSearch(
      RetrievalQuery(
        text: args.requiredString('text'),
        strategies: const {RetrievalStrategy.text},
        limit: args.limit(),
      ),
      context,
    );
  }
}

class SearchSemanticTool extends SearchTool {
  const SearchSemanticTool(super.retrieval);

  @override
  String get name => 'search_semantic';

  @override
  String get description =>
      'Find memories that mean something similar, even when they use other '
      'words.';

  @override
  Map<String, Object?> get parameters => ToolSchemas.object(
    {'text': ToolSchemas.text, 'limit': ToolSchemas.limit},
    required: ['text'],
  );

  @override
  Future<ToolResult> execute(ToolArgs args, ToolContext context) async {
    final text = args.requiredString('text');
    final result = await retrieval.search(
      RetrievalQuery(
        text: text,
        strategies: const {RetrievalStrategy.semantic},
        limit: args.limit(),
      ),
    );
    if (!result.strategiesUsed.contains(RetrievalStrategy.semantic)) {
      return const ToolError(
        'Semantic search needs an embedding model, and none is set up right '
        'now. Use search_text instead.',
      );
    }
    return saveHits(
      [for (final hit in result.hits) hit.card],
      [for (final hit in result.hits) hit.score],
      context,
      description: 'semantic=$text',
      sources: const {'semantic'},
    );
  }
}

class SearchByDateTool extends SearchTool {
  const SearchByDateTool(super.retrieval);

  @override
  String get name => 'search_by_date';

  @override
  String get description =>
      'Find memories saved from images taken in a date range.';

  @override
  Map<String, Object?> get parameters => ToolSchemas.object({
    'date_from': ToolSchemas.dateFrom,
    'date_to': ToolSchemas.dateTo,
    'categories': ToolSchemas.categories,
    'limit': ToolSchemas.limit,
  });

  @override
  Future<ToolResult> execute(ToolArgs args, ToolContext context) {
    final range = args.dateRange();
    if (range == null) {
      throw const ToolArgumentException('Give date_from, date_to or both');
    }
    final query = RetrievalQuery(
      categories: args.strings('categories').toSet(),
      takenBetween: range,
      strategies: const {RetrievalStrategy.structured},
      limit: args.limit(),
    );
    return runSearch(query, context, sources: const {'date'});
  }
}

class SearchByEntityTool extends SearchTool {
  const SearchByEntityTool(super.retrieval);

  @override
  String get name => 'search_by_entity';

  @override
  String get description =>
      'Find memories that mention a company, person, place or product.';

  @override
  Map<String, Object?> get parameters => ToolSchemas.object(
    {
      'value': ToolSchemas.entity,
      'type': ToolSchemas.entityType,
      'limit': ToolSchemas.limit,
    },
    required: ['value'],
  );

  @override
  Future<ToolResult> execute(ToolArgs args, ToolContext context) {
    final query = RetrievalQuery(
      entities: [
        EntityFilter(
          value: args.requiredString('value', maxLength: 80),
          type: args.string('type'),
        ),
      ],
      strategies: const {RetrievalStrategy.structured},
      limit: args.limit(),
    );
    return runSearch(query, context, sources: const {'entity'});
  }
}

class SearchByAttributeTool extends SearchTool {
  const SearchByAttributeTool(super.retrieval);

  @override
  String get name => 'search_by_attribute';

  @override
  String get description =>
      'Find memories by a stored fact, such as amount, due_date, '
      'booking_reference or order_number. Give a range for numbers and '
      'dates, or an exact value.';

  @override
  Map<String, Object?> get parameters => ToolSchemas.object(
    {
      'type': {
        'type': 'string',
        'description':
            'Attribute name, for example amount, due_date or order_number.',
      },
      'min': {'type': 'number', 'description': 'Smallest numeric value.'},
      'max': {'type': 'number', 'description': 'Largest numeric value.'},
      'currency': ToolSchemas.currency,
      'equals': {
        'type': 'string',
        'description': 'Exact value, matched without case.',
      },
      'date_from': {
        'type': 'string',
        'description': 'Earliest value for a date attribute, as YYYY-MM-DD.',
      },
      'date_to': {
        'type': 'string',
        'description': 'Latest value for a date attribute, as YYYY-MM-DD.',
      },
      'limit': ToolSchemas.limit,
    },
    required: ['type'],
  );

  @override
  Future<ToolResult> execute(ToolArgs args, ToolContext context) {
    final min = args.number('min');
    final max = args.number('max');
    if (min != null && max != null && min > max) {
      throw const ToolArgumentException('min must not be greater than max');
    }
    final query = RetrievalQuery(
      attributes: [
        AttributeFilter(
          type: args.requiredString('type', maxLength: 60),
          min: min,
          max: max,
          currency: args.currency(),
          equals: args.string('equals'),
          dateRange: args.dateRange(),
        ),
      ],
      strategies: const {RetrievalStrategy.structured},
      limit: args.limit(),
    );
    return runSearch(query, context, sources: const {'attribute'});
  }
}

class GetMemoryTool extends MemoraTool {
  const GetMemoryTool(this._memories);

  final MemoryStore _memories;

  @override
  String get name => 'get_memory';

  @override
  String get description =>
      'Read one memory in full, including its extracted text and every '
      'stored fact.';

  @override
  Map<String, Object?> get parameters => ToolSchemas.object(
    {
      'id': {
        'type': 'string',
        'description': 'Memory id from a search result.',
      },
    },
    required: ['id'],
  );

  @override
  Future<ToolResult> execute(ToolArgs args, ToolContext context) async {
    final id = args.requiredString('id', maxLength: 64);
    final details = await _memories.getDetails(id);
    if (details == null) {
      return ToolError(
        'No memory with id "$id". Use an id from a search result.',
      );
    }
    final memory = details.memory;
    final text = memory.extractedText ?? '';
    return ToolSuccess(
      {
        'id': memory.id,
        'taken': isoDate(memory.takenAt),
        'summary': ?memory.summary,
        'category': ?memory.category,
        'visual_description': ?memory.visualDescription,
        'extracted_text': text.length > SearchTool.extractedTextLimit
            ? text.substring(0, SearchTool.extractedTextLimit)
            : text,
        'entities': [
          for (final e in details.entities) {'type': e.type, 'value': e.value},
        ],
        'attributes': [
          for (final a in details.attributes)
            {
              'type': a.type,
              'value': a.value,
              'label': ?a.label,
              'currency': ?a.currency,
            },
        ],
        'keywords': details.keywords,
      },
      traceSummary: 'details',
      memoryIds: [memory.id],
      scores: {memory.id: 1},
    );
  }
}

class GetRelatedMemoriesTool extends SearchTool {
  const GetRelatedMemoriesTool(
    super.retrieval, {
    required this._search,
    required this._vectors,
    required this._router,
  });

  final SearchStore _search;
  final VectorStore _vectors;
  final CapabilityRouter _router;

  @override
  String get name => 'get_related_memories';

  @override
  String get description =>
      'Find memories close to one you already have, by meaning and by the '
      'names they share.';

  @override
  Map<String, Object?> get parameters => ToolSchemas.object(
    {
      'id': {'type': 'string', 'description': 'Memory id to start from.'},
      'limit': ToolSchemas.limit,
    },
    required: ['id'],
  );

  @override
  Future<ToolResult> execute(ToolArgs args, ToolContext context) async {
    final id = args.requiredString('id', maxLength: 64);
    final limit = args.limit(fallback: 10);
    final rankings = <List<ScoredId>>[];
    try {
      final embeddings = await _router.embeddings();
      rankings.add(
        await _vectors.neighbours(id, embeddings.service.model, limit: limit),
      );
    } on CapabilityUnavailableException {
      // Shared entities still find related memories.
    }
    rankings.add(await _search.sharingEntities(id, limit: limit));
    if (rankings.every((r) => r.isEmpty)) {
      return ToolError('Nothing is related to "$id" yet.');
    }
    final fused = reciprocalRankFusion(rankings).take(limit).toList();
    final cards = await _search.cards([for (final f in fused) f.id]);
    final scores = {for (final f in fused) f.id: f.score};
    return saveHits(
      cards,
      [for (final card in cards) scores[card.id] ?? 0],
      context,
      description: 'related to $id',
      sources: const {'related'},
    );
  }
}
