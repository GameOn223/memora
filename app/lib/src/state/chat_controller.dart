import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:memora_core/memora_core.dart';

import 'data_version.dart';
import 'services.dart';

/// What the Ask screen shows.
@immutable
class ChatViewState {
  const ChatViewState({
    this.conversationId,
    this.messages = const [],
    this.sources = const {},
    this.thinking = false,
    this.progress,
    this.error,
    this.retryable = false,
    this.lastQuestion,
    this.focusMemoryId,
    this.loaded = false,
  });

  final String? conversationId;
  final List<ChatMessage> messages;

  /// Details for every memory cited by a message, by id.
  final Map<String, MemoryDetails> sources;
  final bool thinking;

  /// The latest tool summary while thinking, if there is one yet.
  final String? progress;
  final String? error;
  final bool retryable;
  final String? lastQuestion;

  /// Set by "Ask about this" on the detail screen.
  final String? focusMemoryId;

  /// False until the first load finishes, so the screen can stay quiet.
  final bool loaded;

  bool get isEmpty => messages.isEmpty && !thinking;

  ChatViewState copyWith({
    String? conversationId,
    List<ChatMessage>? messages,
    Map<String, MemoryDetails>? sources,
    bool? thinking,
    String? progress,
    String? error,
    bool? retryable,
    String? lastQuestion,
    String? focusMemoryId,
    bool? loaded,
    bool clearProgress = false,
    bool clearError = false,
    bool clearFocus = false,
    bool clearConversation = false,
  }) {
    return ChatViewState(
      conversationId: clearConversation
          ? null
          : conversationId ?? this.conversationId,
      messages: messages ?? this.messages,
      sources: sources ?? this.sources,
      thinking: thinking ?? this.thinking,
      progress: clearProgress ? null : progress ?? this.progress,
      error: clearError ? null : error ?? this.error,
      retryable: retryable ?? this.retryable,
      lastQuestion: lastQuestion ?? this.lastQuestion,
      focusMemoryId: clearFocus ? null : focusMemoryId ?? this.focusMemoryId,
      loaded: loaded ?? this.loaded,
    );
  }
}

final chatControllerProvider = NotifierProvider<ChatController, ChatViewState>(
  ChatController.new,
);

class ChatController extends Notifier<ChatViewState> {
  StreamSubscription<ChatProgress>? _subscription;
  int _askToken = 0;

  @override
  ChatViewState build() {
    ref.onDispose(() => unawaited(_subscription?.cancel()));
    scheduleMicrotask(openLatest);
    return const ChatViewState();
  }

  /// Opens the most recent conversation, or starts an empty one.
  Future<void> openLatest() async {
    final services = ref.read(appServicesProvider);
    final conversations = await services.conversations.listConversations();
    if (!ref.mounted) return;
    if (conversations.isEmpty) {
      state = state.copyWith(loaded: true);
      return;
    }
    await open(conversations.first.id);
  }

  Future<void> open(String conversationId) async {
    final services = ref.read(appServicesProvider);
    final messages = await services.conversations.messages(conversationId);
    if (!ref.mounted) return;
    state = state.copyWith(
      conversationId: conversationId,
      messages: messages,
      loaded: true,
      thinking: false,
      clearError: true,
      clearProgress: true,
      clearFocus: true,
    );
    await _loadSources(messages);
  }

  /// Starts a fresh conversation, optionally about one memory.
  void startNew({String? focusMemoryId}) {
    unawaited(_subscription?.cancel());
    _subscription = null;
    state = ChatViewState(loaded: true, focusMemoryId: focusMemoryId);
  }

  Future<void> send(String text) async {
    final question = text.trim();
    if (question.isEmpty || state.thinking) return;
    // Claim the turn before the first await, so a second tap can't start a
    // second conversation.
    state = state.copyWith(
      thinking: true,
      lastQuestion: question,
      clearError: true,
      clearProgress: true,
      loaded: true,
    );
    final services = ref.read(appServicesProvider);
    var conversationId = state.conversationId;
    if (conversationId == null) {
      final conversation = await services.chat.startConversation(
        title: question,
      );
      if (!ref.mounted) return;
      conversationId = conversation.id;
    }
    final pending = ChatMessage(
      id: 'pending-${DateTime.now().microsecondsSinceEpoch}',
      conversationId: conversationId,
      role: MessageRole.user,
      content: question,
      createdAt: ref.read(clockProvider).now(),
    );
    state = state.copyWith(
      conversationId: conversationId,
      messages: [...state.messages, pending],
    );
    await _ask(conversationId, question);
  }

  /// Asks the last question again after a failure.
  Future<void> retry() async {
    final question = state.lastQuestion;
    final conversationId = state.conversationId;
    if (question == null || conversationId == null || state.thinking) return;
    state = state.copyWith(
      thinking: true,
      clearError: true,
      clearProgress: true,
    );
    await _ask(conversationId, question);
  }

  Future<void> _ask(String conversationId, String question) async {
    final services = ref.read(appServicesProvider);
    final focus = state.focusMemoryId;
    // Drop the previous turn without waiting for its generator to unwind.
    final token = ++_askToken;
    unawaited(_subscription?.cancel());
    final completer = Completer<void>();
    _subscription = services.chat
        .ask(conversationId, question, focusMemoryId: focus)
        .listen(
          (progress) async {
            if (!ref.mounted || token != _askToken) return;
            switch (progress) {
              case ChatToolUsed(:final entry):
                state = state.copyWith(
                  progress: entry.summary.isEmpty
                      ? entry.tool
                      : '${entry.tool} · ${entry.summary}',
                );
              case ChatAnswered():
                final messages = await services.conversations.messages(
                  conversationId,
                );
                if (!ref.mounted) return;
                state = state.copyWith(
                  messages: messages,
                  thinking: false,
                  clearProgress: true,
                  clearFocus: true,
                );
                await _loadSources(messages);
                await ref.read(dataVersionProvider.notifier).check();
              case ChatFailed(:final message, :final retryable):
                state = state.copyWith(
                  thinking: false,
                  error: message,
                  retryable: retryable,
                  clearProgress: true,
                );
            }
          },
          onError: (Object error) {
            // cancelOnError skips onDone, so release the caller here too.
            if (!completer.isCompleted) completer.complete();
            if (!ref.mounted || token != _askToken) return;
            state = state.copyWith(
              thinking: false,
              error: 'Something went wrong. Try again.',
              retryable: true,
              clearProgress: true,
            );
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
          cancelOnError: true,
        );
    await completer.future;
  }

  Future<void> _loadSources(List<ChatMessage> messages) async {
    final services = ref.read(appServicesProvider);
    final wanted = {
      for (final message in messages)
        for (final reference in message.references) reference.memoryId,
    }..removeWhere(state.sources.containsKey);
    if (wanted.isEmpty) return;
    final loaded = <String, MemoryDetails>{};
    for (final id in wanted) {
      final details = await services.memories.getDetails(id);
      if (details != null) loaded[id] = details;
    }
    if (!ref.mounted || loaded.isEmpty) return;
    state = state.copyWith(sources: {...state.sources, ...loaded});
  }
}

/// Conversations for the history sheet, newest first.
final conversationsProvider = FutureProvider<List<Conversation>>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.watch(appServicesProvider).conversations.listConversations();
});
