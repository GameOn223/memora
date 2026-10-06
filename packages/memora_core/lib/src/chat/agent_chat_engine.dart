import 'dart:convert';

import '../ai/capabilities.dart';
import '../ai/errors.dart';
import '../ai/router.dart';
import '../ai/settings.dart';
import '../model/conversation.dart';
import '../ports/platform.dart';
import '../ports/stores.dart';
import '../services/contracts.dart';
import 'aggregation.dart';
import 'answer_verifier.dart';
import 'citations.dart';
import 'deterministic_answerer.dart';
import 'presentation_builder.dart';
import 'query_labels.dart';
import 'query_parser.dart';
import 'system_prompt.dart';
import 'tools/tool.dart';
import 'tools/tool_registry.dart';

/// Answers questions with a chat model and the read-only tools, and falls
/// back to search when no chat model is available. See
/// docs/architecture.md, section 9.
class AgentChatEngine implements ChatEngine {
  AgentChatEngine({
    required this._conversations,
    required this._router,
    required this._retrieval,
    required this._search,
    required this._vectors,
    required this._memories,
    required this._images,
    required this._aiSettings,
    required this._clock,
    required this._ids,
    this._maxToolRounds = 6,
    this._localeTag = 'en-IN',
    this._defaultCurrency = 'INR',
    this._parser = const QueryParser(),
  });

  /// How many earlier messages go into the prompt.
  static const historyLength = 12;

  /// How long a conversation title may be.
  static const titleLength = 48;

  /// How many sources an answer may cite.
  static const maxReferences = 12;

  static const newConversationTitle = 'New conversation';

  final ConversationStore _conversations;
  final CapabilityRouter _router;
  final RetrievalEngine _retrieval;
  final SearchStore _search;
  final VectorStore _vectors;
  final MemoryStore _memories;
  final ImageFiles _images;
  final AiSettingsRepository _aiSettings;
  final Clock _clock;
  final IdGenerator _ids;
  final int _maxToolRounds;
  final String _localeTag;
  final String _defaultCurrency;
  final QueryParser _parser;

  static final _pointsBack = RegExp(
    r'(?<![a-z])(of (?:those|them|these)|among (?:those|them|these)|'
    r'from (?:those|them|these)|in (?:those|them|these)|those ones?|'
    r'these ones?|that one|this one|the same(?: ones?)?)(?![a-z])',
  );

  @override
  Future<Conversation> startConversation({String? title}) {
    final trimmed = (title ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    final name = trimmed.isEmpty
        ? newConversationTitle
        : (trimmed.length > titleLength
              ? trimmed.substring(0, titleLength).trimRight()
              : trimmed);
    return _conversations.createConversation(_ids.next(), name, _clock.now());
  }

  @override
  Future<ChatAvailability> availability() async {
    try {
      final chat = await _router.chat();
      return ChatAvailability.model(
        providerName: chat.provider.displayName,
        modelId: chat.modelId,
      );
    } on CapabilityUnavailableException {
      return const ChatAvailability.searchOnly();
    }
  }

  @override
  Stream<ChatProgress> ask(
    String conversationId,
    String text, {
    String? focusMemoryId,
  }) async* {
    final question = text.trim();
    await _conversations.addMessage(
      ChatMessage(
        id: _ids.next(),
        conversationId: conversationId,
        role: MessageRole.user,
        content: question,
        createdAt: _clock.now(),
      ),
    );

    Resolved<ChatService>? chat;
    try {
      chat = await _router.chat();
    } on CapabilityUnavailableException {
      chat = null;
    }

    if (chat == null) {
      yield* _searchOnly(conversationId, question, focusMemoryId);
    } else {
      yield* _withModel(chat, conversationId, question, focusMemoryId);
    }
  }

  /// True when a question leans on the memories found last time: it either
  /// points back at them ("of those, which was highest?") or asks for
  /// nothing new of its own ("which one was highest?").
  ///
  /// A question that brings its own words or filters, such as "how many
  /// receipts do I have?", is a fresh search even right after another one.
  static bool refersToEarlierResults(String question, ParsedQuery parsed) {
    if (_pointsBack.hasMatch(question.trim().toLowerCase())) return true;
    return !parsed.query.hasFilters && parsed.query.text == null;
  }

  /// Answers from hybrid search alone. Used when no chat model is available
  /// and when one gave up on tools, which [provider] and [model] record.
  Stream<ChatProgress> _searchOnly(
    String conversationId,
    String question,
    String? focusMemoryId, {
    String? provider,
    String? model,
  }) async* {
    Set<String>? within;
    if (focusMemoryId != null) {
      within = {focusMemoryId};
    } else if (refersToEarlierResults(
      question,
      _parser.parse(question, now: _clock.now()),
    )) {
      final active = await _conversations.latestResultSet(conversationId);
      if (active != null && active.memoryIds.isNotEmpty) {
        within = active.memoryIds.toSet();
      }
    }

    final answer = await DeterministicAnswerer(
      retrieval: _retrieval,
      search: _search,
      clock: _clock,
      parser: _parser,
    ).answer(question, within: within);
    for (final entry in answer.trace) {
      yield ChatToolUsed(entry);
    }

    final messageId = _ids.next();
    final ids = [for (final hit in answer.hits) hit.card.id];
    if (ids.isNotEmpty) {
      await _conversations.saveResultSet(
        ResultSet(
          id: _ids.next(),
          conversationId: conversationId,
          messageId: messageId,
          description: describeQuery(answer.query),
          memoryIds: ids,
          createdAt: _clock.now(),
        ),
      );
    }
    final best = answer.hits.fold(0.0, (a, h) => h.score > a ? h.score : a);
    final message = ChatMessage(
      id: messageId,
      conversationId: conversationId,
      role: MessageRole.assistant,
      content: answer.text,
      createdAt: _clock.now(),
      references: [
        for (var i = 0; i < answer.hits.length && i < maxReferences; i++)
          MessageReference(
            memoryId: answer.hits[i].card.id,
            position: i,
            relevance: best > 0 ? answer.hits[i].score / best : null,
          ),
      ],
      toolTrace: answer.trace,
      presentation: answer.presentation,
      provider: provider,
      model: model,
    );
    await _conversations.addMessage(message);
    yield ChatAnswered(message);
  }

  Stream<ChatProgress> _withModel(
    Resolved<ChatService> chat,
    String conversationId,
    String question,
    String? focusMemoryId,
  ) async* {
    final assistantId = _ids.next();
    final tools = ToolRegistry.build(
      retrieval: _retrieval,
      search: _search,
      vectors: _vectors,
      memories: _memories,
      router: _router,
    );
    final byName = {for (final tool in tools) tool.name: tool};
    // Each tool call gets its own timestamp, strictly after the one before,
    // so two searches in the same turn can't tie and leave "the latest
    // result set" ambiguous.
    DateTime? stamped;
    ToolContext nextContext() {
      final now = _clock.now();
      stamped = stamped == null || now.isAfter(stamped!)
          ? now
          : stamped!.add(const Duration(milliseconds: 1));
      return ToolContext(
        conversationId: conversationId,
        now: stamped!,
        conversations: _conversations,
        ids: _ids,
        messageId: assistantId,
      );
    }

    final trace = <ToolTraceEntry>[];
    final scores = <String, double>{};
    final sources = <String>{};
    var lastHits = const <String>[];
    AggregateOutcome? aggregate;
    var aggregateWasLast = false;
    String? answerText;
    ChatMessage answered;

    try {
      final history = await _conversations.messages(conversationId);
      final entries = <ChatEntry>[
        for (final message
            in history.length > historyLength
                ? history.sublist(history.length - historyLength)
                : history)
          if (message.role == MessageRole.user)
            UserEntry(message.content)
          else
            AssistantEntry(text: message.content),
      ];
      final focus = focusMemoryId == null
          ? null
          : (await _search.cards([focusMemoryId])).firstOrNull;
      final system = SystemPrompt.build(
        now: _clock.now(),
        localeTag: _localeTag,
        defaultCurrency: _defaultCurrency,
        activeSet: await _conversations.latestResultSet(conversationId),
        focus: focus,
      );
      final definitions = [for (final tool in tools) tool.definition];

      for (var round = 0; round <= _maxToolRounds; round++) {
        final turn = await chat.service.complete(
          // A copy, so an adapter that keeps the request does not see the
          // entries this loop adds later.
          ChatRequest(
            system: system,
            entries: [...entries],
            tools: definitions,
          ),
        );
        if (turn.toolCalls.isEmpty) {
          answerText = turn.text.trim();
          break;
        }
        // The last round has no room left to use what a tool would return.
        if (round == _maxToolRounds) break;
        entries.add(AssistantEntry(text: turn.text, toolCalls: turn.toolCalls));
        for (final call in turn.toolCalls) {
          final tool = byName[call.name];
          final result = tool == null
              ? ToolError('There is no tool called "${call.name}".')
              : await tool.run(call.arguments, nextContext());
          final entry = ToolTraceEntry(
            tool: call.name,
            arguments: call.arguments,
            summary: switch (result) {
              ToolSuccess(:final traceSummary) => traceSummary,
              ToolError(:final message) => message,
            },
          );
          trace.add(entry);
          yield ChatToolUsed(entry);

          switch (result) {
            case ToolSuccess():
              scores.addAll(result.scores);
              sources.addAll(result.sources);
              if (result.memoryIds.isNotEmpty) lastHits = result.memoryIds;
              aggregateWasLast = result.aggregate != null;
              if (result.aggregate != null) aggregate = result.aggregate;
              entries.add(
                ToolResultEntry(
                  callId: call.id,
                  toolName: call.name,
                  content: jsonEncode(result.json),
                ),
              );
            case ToolError():
              aggregateWasLast = false;
              entries.add(
                ToolResultEntry(
                  callId: call.id,
                  toolName: call.name,
                  content: jsonEncode({'error': result.message}),
                  isError: true,
                ),
              );
          }
        }
      }
      var cited = <String>[];
      if (answerText == null || answerText.isEmpty) {
        final closest = lastHits.take(5).toList();
        answerText = closest.isEmpty
            ? 'I could not find an answer in your memories. Try asking in '
                  'another way.'
            : 'I could not settle on an answer, but these are the closest '
                  'matches.';
        cited = closest;
      } else {
        cited = await _existing(parseCitations(answerText));
      }
      if (cited.isEmpty && aggregate != null) {
        cited = await _existing(aggregate.memoryIds);
      }

      final draft = await PresentationBuilder(_search).build(
        question: question,
        citedIds: cited,
        aggregate: aggregate,
        aggregateWasLast: aggregateWasLast,
        sources: sources,
      );
      final verified =
          await AnswerVerifier(
            router: _router,
            memories: _memories,
            images: _images,
            aiSettings: _aiSettings,
          ).verify(
            text: stripCitations(answerText),
            presentation: draft.presentation,
            source: draft.source,
          );

      answered = ChatMessage(
        id: assistantId,
        conversationId: conversationId,
        role: MessageRole.assistant,
        content: verified.text,
        createdAt: _clock.now(),
        references: [
          for (var i = 0; i < cited.length && i < maxReferences; i++)
            MessageReference(
              memoryId: cited[i],
              position: i,
              relevance: scores[cited[i]],
            ),
        ],
        toolTrace: trace,
        presentation: verified.presentation,
        provider: chat.provider.id,
        model: chat.modelId,
      );
      await _conversations.addMessage(answered);
    } on ToolCallingUnavailableException {
      // The model was offered tools and could not call one, so nothing was
      // looked up. The deterministic answer is grounded in the memories;
      // whatever the model wrote instead is not.
      yield* _searchOnly(
        conversationId,
        question,
        focusMemoryId,
        provider: chat.provider.id,
        model: chat.modelId,
      );
      return;
    } on AiException catch (e) {
      yield ChatFailed(
        _friendlyFailure(e, chat.provider.displayName),
        retryable: e is AiTransientException,
      );
      return;
    } on Object {
      // Building or saving the answer failed. The question stays saved, so
      // the user can try again.
      yield const ChatFailed('Something went wrong while answering that.');
      return;
    }

    yield ChatAnswered(answered);
  }

  /// Keeps only the ids that still name a memory, in the order given.
  Future<List<String>> _existing(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final found = {
      for (final memory in await _memories.getMemories(ids)) memory.id,
    };
    return [
      for (final id in ids)
        if (found.contains(id)) id,
    ];
  }

  String _friendlyFailure(AiException error, String providerName) =>
      switch (error) {
        AiTransientException() => '$providerName did not respond. Try again.',
        AiConfigurationException() =>
          '$providerName refused the request. Check the API key and model '
              'in settings.',
        AiContentException() =>
          '$providerName could not answer this question. Try rewording it.',
      };
}
