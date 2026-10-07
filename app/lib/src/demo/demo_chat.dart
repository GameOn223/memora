import 'dart:async';

import 'package:memora_core/memora_core.dart';

import 'demo_stores.dart';

/// A scripted answer: text, cited memories, presentation and tool trace.
class _Script {
  const _Script({
    required this.text,
    required this.references,
    required this.presentation,
    required this.trace,
  });

  final String text;
  final List<(String, double)> references;
  final MessagePresentation presentation;
  final List<ToolTraceEntry> trace;
}

const _allBills = [
  ('m6', 0.96),
  ('m9', 0.91),
  ('b6', 0.88),
  ('b5', 0.84),
  ('b3', 0.8),
  ('b2', 0.78),
  ('b1', 0.76),
  ('m1', 0.74),
];

const _listBills = _Script(
  text:
      'I found 8 Reliance electricity bills, from January to September 2026. '
      'They total ₹14,208.',
  references: _allBills,
  presentation: MessagePresentation(
    sourceLabel: '8 memories · entity + semantic',
  ),
  trace: [
    ToolTraceEntry(
      tool: 'search_by_entity',
      arguments: {'value': 'Reliance', 'type': 'company'},
      summary: '',
    ),
    ToolTraceEntry(
      tool: 'search_metadata',
      arguments: {'category': 'utility_bill'},
      summary: '',
    ),
    ToolTraceEntry(
      tool: 'search_semantic',
      arguments: {'query': 'electricity bill'},
      summary: '8 candidates',
    ),
    ToolTraceEntry(
      tool: 'rerank',
      arguments: {'model': 'local / score-fusion'},
      summary: '8 kept',
    ),
  ],
);

const _highest = _Script(
  text:
      'The highest was August 2026, about 18% above your monthly average of '
      '₹1,776.',
  references: [
    ('m1', 0.9),
    ('m6', 0.99),
    ('m9', 0.9),
    ('b6', 0.9),
    ('b5', 0.9),
    ('b3', 0.9),
    ('b2', 0.9),
    ('b1', 0.9),
  ],
  presentation: MessagePresentation(
    layout: SourceLayout.table,
    headline: '₹2,103',
    headlineNote: 'Verified against the original image',
    tableAttribute: 'amount',
    highlightMemoryId: 'm6',
    sourceLabel: '8 memories · highest amount',
    verification: VerificationState.verified,
  ),
  trace: [
    ToolTraceEntry(
      tool: 'aggregate_results',
      arguments: {'op': 'max', 'attribute': 'amount'},
      summary: '₹2,103',
    ),
  ],
);

const _aboveTwoThousand = _Script(
  text: 'Three of the eight were above ₹2,000.',
  references: [('m6', 0.99), ('b2', 0.97), ('b1', 0.95)],
  presentation: MessagePresentation(sourceLabel: '3 memories · amount filter'),
  trace: [
    ToolTraceEntry(
      tool: 'search_metadata',
      arguments: {'entity': 'Reliance', 'amount_min': 2000},
      summary: '3 matches',
    ),
  ],
);

/// Chat engine for the demo. It answers the design's conversation about
/// Reliance bills and falls back to a plain text match for anything else.
class DemoChatEngine implements ChatEngine {
  DemoChatEngine({
    required this.db,
    required this.conversations,
    required this.router,
    this.step = const Duration(milliseconds: 350),
  });

  final DemoDatabase db;
  final ConversationStore conversations;
  final CapabilityRouter router;

  /// Pause between progress events, so the thinking row is visible.
  /// Delay between the steps of a turn. Tests shorten it.
  Duration step;

  /// When set, the next [ask] fails with a retryable error.
  bool failNextAsk = false;

  /// Questions received, in order.
  final List<String> asked = [];

  /// Focus memory passed with each question.
  final List<String?> focusIds = [];

  /// Seeds the conversation shown in the design.
  Future<void> seed() async {
    final start = db.at(0, '09:50');
    const id = 'c1';
    await conversations.createConversation(
      id,
      'show me all my reliance bills',
      start,
    );
    await conversations.addMessage(
      ChatMessage(
        id: 'c1-u1',
        conversationId: id,
        role: MessageRole.user,
        content: 'show me all my reliance bills',
        createdAt: start,
      ),
    );
    await conversations.addMessage(
      _assistant(
        id,
        'c1-a1',
        _listBills,
        start.add(const Duration(seconds: 6)),
      ),
    );
    await conversations.addMessage(
      ChatMessage(
        id: 'c1-u2',
        conversationId: id,
        role: MessageRole.user,
        content: 'which one was highest?',
        createdAt: start.add(const Duration(minutes: 1)),
      ),
    );
    await conversations.addMessage(
      _assistant(
        id,
        'c1-a2',
        _highest,
        start.add(const Duration(minutes: 1, seconds: 5)),
      ),
    );
  }

  ChatMessage _assistant(
    String conversationId,
    String id,
    _Script script,
    DateTime at, {
    bool searchOnly = false,
  }) {
    final p = script.presentation;
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      role: MessageRole.assistant,
      content: script.text,
      createdAt: at,
      references: [
        for (final (i, (memoryId, relevance)) in script.references.indexed)
          MessageReference(
            memoryId: memoryId,
            position: i,
            relevance: relevance,
          ),
      ],
      toolTrace: script.trace,
      presentation: searchOnly
          ? MessagePresentation(
              layout: p.layout,
              headline: p.headline,
              tableAttribute: p.tableAttribute,
              highlightMemoryId: p.highlightMemoryId,
              sourceLabel: p.sourceLabel,
              searchOnly: true,
            )
          : p,
      provider: searchOnly ? null : 'groq',
      model: searchOnly ? null : 'llama-3.3-70b',
    );
  }

  @override
  Future<Conversation> startConversation({String? title}) {
    return conversations.createConversation(
      db.nextId('c'),
      title ?? 'New conversation',
      db.clock.now(),
    );
  }

  @override
  Stream<ChatProgress> ask(
    String conversationId,
    String text, {
    String? focusMemoryId,
  }) async* {
    asked.add(text);
    focusIds.add(focusMemoryId);
    await conversations.addMessage(
      ChatMessage(
        id: db.nextId('u'),
        conversationId: conversationId,
        role: MessageRole.user,
        content: text,
        createdAt: db.clock.now(),
      ),
    );
    if (failNextAsk) {
      failNextAsk = false;
      await Future<void>.delayed(step);
      yield const ChatFailed('Groq did not respond. Try again.');
      return;
    }
    final searchOnly = (await availability()).searchOnly;
    final script = _scriptFor(text, focusMemoryId);
    for (final entry in script.trace) {
      await Future<void>.delayed(step);
      yield ChatToolUsed(entry);
    }
    await Future<void>.delayed(step);
    final message = _assistant(
      conversationId,
      db.nextId('a'),
      script,
      db.clock.now(),
      searchOnly: searchOnly,
    );
    // A word at a time, the way a provider that streams arrives. The saved
    // message still lands at the end and is the one kept.
    if (streamAnswer) {
      for (final piece in _words(message.content)) {
        await Future<void>.delayed(step);
        yield ChatAnswerDelta(piece);
      }
    }
    await conversations.addMessage(message);
    yield ChatAnswered(message);
  }

  /// Whether answers arrive a piece at a time. Off by default so the tests
  /// written before streaming existed still describe what they meant.
  bool streamAnswer = false;

  /// Words with their trailing space, so joining them is the original.
  static List<String> _words(String text) {
    final parts = <String>[];
    for (final word in text.split(' ')) {
      parts.add(parts.isEmpty ? word : ' $word');
    }
    return parts;
  }

  _Script _scriptFor(String text, String? focusMemoryId) {
    final q = text.toLowerCase();
    if (focusMemoryId != null) {
      final m = db.memories[focusMemoryId];
      final facts = db.attributes[focusMemoryId] ?? const [];
      final amount = facts.where((a) => a.type == 'amount').firstOrNull;
      return _Script(
        text: amount == null
            ? 'This is ${m?.summary ?? 'an image you added'}.'
            : 'This is ${m?.summary ?? 'an image you added'}, for '
                  '${amount.value}.',
        references: [(focusMemoryId, 1)],
        presentation: const MessagePresentation(sourceLabel: 'Source'),
        trace: [
          ToolTraceEntry(
            tool: 'get_memory',
            arguments: {'id': focusMemoryId},
            summary: '1 memory',
          ),
        ],
      );
    }
    if (q.contains('2000') || q.contains('2,000') || q.contains('above')) {
      return _aboveTwoThousand;
    }
    if (q.contains('highest') || q.contains('most') || q.contains('max')) {
      return _highest;
    }
    if (q.contains('reliance') || q.contains('bill')) return _listBills;

    final words = q
        .split(RegExp(r'[^a-z0-9₹]+'))
        .where((w) => w.length > 2)
        .toSet();
    final hits = db.memories.values.where((m) {
      final haystack = [
        m.summary ?? '',
        m.category ?? '',
        ...?db.keywords[m.id],
      ].join(' ').toLowerCase();
      return words.any(haystack.contains);
    }).toList();
    if (hits.isEmpty) {
      return _Script(
        text: 'No memories matched.',
        references: const [],
        presentation: const MessagePresentation(),
        trace: [
          ToolTraceEntry(
            tool: 'search_memories',
            arguments: {'text': text},
            summary: '0 candidates',
          ),
        ],
      );
    }
    return _Script(
      text: hits.length == 1
          ? 'Found 1 memory.'
          : 'Found ${hits.length} memories.',
      references: [for (final m in hits.take(8)) (m.id, 0.8)],
      presentation: MessagePresentation(
        sourceLabel:
            '${hits.length} ${hits.length == 1 ? 'memory' : 'memories'} · text',
      ),
      trace: [
        ToolTraceEntry(
          tool: 'search_memories',
          arguments: {'text': text},
          summary: '${hits.length} candidates',
        ),
      ],
    );
  }

  @override
  Future<ChatAvailability> availability() async {
    final status = (await router.statuses())[Capability.chat];
    if (status == null || !status.available) {
      return const ChatAvailability.searchOnly();
    }
    return ChatAvailability.model(
      providerName: status.provider!.displayName,
      modelId: status.modelId!,
    );
  }
}
