import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:memora_core/memora_core.dart';

import '../../routing/router.dart';
import '../../state/chat_controller.dart';
import '../../state/settings.dart';
import '../../theme/memora_colors.dart';
import '../../theme/memora_icons.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../../widgets/caps_label.dart';
import '../../widgets/fading_rule.dart';
import '../../widgets/llm_loading_bar.dart';
import '../../widgets/memora_icon_button.dart';
import '../../widgets/motion.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/tap_area.dart';
import 'chat_message_view.dart';
import 'conversation_drawer.dart';

/// Ask Memora: the conversation, its sources, and the composer.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _scroll = ScrollController();
  final _input = TextEditingController();
  int _lastSignature = 0;

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text.trim();
    // Keep what was typed when the turn is refused.
    if (text.isEmpty || ref.read(chatControllerProvider).thinking) return;
    _input.clear();
    unawaited(ref.read(chatControllerProvider.notifier).send(text));
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final state = ref.watch(chatControllerProvider);
    final availability = ref.watch(chatAvailabilityProvider).value;
    final messages = visibleMessages(state.messages);
    // Keep the newest turn in view as messages, progress and errors land.
    // The streamed length is in here so the view follows the text as it is
    // written, rather than once at the end.
    final signature = Object.hash(
      messages.length,
      state.thinking,
      state.progress,
      state.error,
      state.streamed?.length,
    );
    if (signature != _lastSignature) {
      _lastSignature = signature;
      _scrollToEnd();
    }

    return ColoredBox(
      color: c.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(
            title: 'Ask Memora',
            onLeading: () => context.go(Routes.home),
            trailing: [
              Flexible(
                child: Text(
                  providerLabel(availability).toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MemoraText.caps(8.5, spacing: 1, color: c.dim),
                ),
              ),
              MemoraIconButton(
                icon: MemoraIcons.chatsCircle,
                semanticLabel: 'Conversations',
                box: 30,
                iconSize: 18,
                onPressed: () => unawaited(showConversationDrawer(context)),
              ),
            ],
          ),
          const FadingRule(),
          Expanded(
            child: messages.isEmpty && !state.thinking
                ? _EmptyConversation(
                    focusMemoryId: state.focusMemoryId,
                    onAsk: (text) {
                      _input.text = text;
                      _send();
                    },
                  )
                : ListView.separated(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(
                      Space.s6,
                      Space.s6,
                      Space.s6,
                      Space.s8,
                    ),
                    itemCount: messages.length + (_trailingCount(state)),
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: Space.s8),
                    itemBuilder: (context, i) {
                      if (i < messages.length) {
                        return ChatMessageView(
                          message: messages[i],
                          sources: state.sources,
                        );
                      }
                      if (state.thinking) {
                        // Text as it arrives, once there is any. The saved
                        // message replaces it when the turn lands.
                        if (state.streamed case final streamed?) {
                          return _StreamingAnswer(text: streamed);
                        }
                        // A retry keeps the error up and says it is trying,
                        // so a failure that comes straight back is still a
                        // visible change rather than a flicker.
                        if (state.retrying && state.error != null) {
                          return _ErrorRow(
                            message: state.error!,
                            retryable: true,
                            retrying: true,
                            onRetry: () {},
                          );
                        }
                        // Not "Searching N memories" until something has
                        // actually searched. Asking what two and five make
                        // does not go near the memories, and saying it did
                        // is a small lie that makes the app look confused.
                        return _ThinkingRow(text: state.progress ?? 'Thinking');
                      }
                      return _ErrorRow(
                        message: state.error!,
                        retryable: state.retryable,
                        retrying: false,
                        onRetry: () => unawaited(
                          ref.read(chatControllerProvider.notifier).retry(),
                        ),
                      );
                    },
                  ),
          ),
          // Right above the composer, where someone waiting is looking.
          const LlmLoadingBar(),
          _Composer(
            controller: _input,
            onSend: _send,
            enabled: !state.thinking,
          ),
        ],
      ),
    );
  }

  int _trailingCount(ChatViewState state) =>
      state.thinking || state.error != null ? 1 : 0;
}

/// Hides the local echo of a question that was asked again after a failure.
List<ChatMessage> visibleMessages(List<ChatMessage> messages) {
  final result = <ChatMessage>[];
  for (final message in messages) {
    final previous = result.lastOrNull;
    final duplicate =
        previous != null &&
        previous.role == MessageRole.user &&
        message.role == MessageRole.user &&
        previous.content == message.content;
    if (duplicate) {
      result[result.length - 1] = message;
    } else {
      result.add(message);
    }
  }
  return result;
}

/// The model behind Ask, shown in the header.
String providerLabel(ChatAvailability? availability) {
  if (availability == null) return '';
  if (availability.searchOnly) return 'Search only · no chat model';
  return '${availability.providerName} · ${availability.modelId}';
}

/// The answer while it is still being written.
///
/// Styled like the finished message so the text does not jump when the saved
/// one replaces it, with a pulse to say more is coming.
class _StreamingAnswer extends StatelessWidget {
  const _StreamingAnswer({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: MemoraText.style(14, height: 1.55, color: c.text)),
          const SizedBox(height: Space.s3),
          const PulseDot(),
        ],
      ),
    );
  }
}

class _ThinkingRow extends StatelessWidget {
  const _ThinkingRow({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      liveRegion: true,
      child: Row(
        children: [
          const PulseDot(),
          const SizedBox(width: Space.s3),
          Expanded(
            child: CapsLabel(text, size: 10, spacing: 1.1, color: c.muted),
          ),
        ],
      ),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({
    required this.message,
    required this.retryable,
    required this.retrying,
    required this.onRetry,
  });

  final String message;
  final bool retryable;

  /// True while the attempt is under way, which the button says and does
  /// not take another tap for.
  final bool retrying;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.accentLine),
      ),
      child: Row(
        children: [
          Icon(MemoraIcons.warningCircle, size: 17, color: c.accent),
          const SizedBox(width: Space.s4),
          Expanded(
            child: Text(
              message,
              style: MemoraText.style(12.5, height: 1.5, color: c.text),
            ),
          ),
          if (retryable) ...[
            const SizedBox(width: Space.s3),
            TapArea(
              onTap: retrying ? null : onRetry,
              semanticLabel: retrying ? 'Retrying' : 'Retry the question',
              minSize: 0,
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: Space.s3),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(color: retrying ? c.line : c.accent),
                ),
                child: retrying
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const PulseDot(),
                          const SizedBox(width: Space.s2),
                          Text(
                            'Retrying',
                            style: MemoraText.style(12, color: c.muted),
                          ),
                        ],
                      )
                    : Text(
                        'Retry',
                        style: MemoraText.style(
                          12,
                          medium: true,
                          color: c.accentInk,
                        ),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation({required this.focusMemoryId, required this.onAsk});

  final String? focusMemoryId;
  final ValueChanged<String> onAsk;

  static const suggestions = [
    'show me all my reliance bills',
    'which one was highest?',
    'what did I save yesterday?',
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        Space.s6,
        Space.s8,
        Space.s6,
        Space.s8,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(MemoraIcons.sparkle, size: 22, color: c.accent),
          const SizedBox(height: Space.s4),
          Text(
            focusMemoryId == null
                ? 'Ask about anything you saved.'
                : 'Ask about this memory.',
            style: MemoraText.style(
              20,
              medium: true,
              spacing: -0.4,
              height: 1.3,
              color: c.text,
            ),
          ),
          const SizedBox(height: Space.s3),
          Text(
            'Memora answers from your own images and shows which ones it '
            'used.',
            style: MemoraText.style(13, height: 1.55, color: c.muted),
          ),
          const SizedBox(height: Space.s8),
          const CapsLabel('Try asking'),
          const SizedBox(height: Space.s3),
          for (final suggestion in suggestions) ...[
            TapArea(
              onTap: () => onAsk(suggestion),
              semanticLabel: suggestion,
              minSize: 0,
              child: Container(
                margin: const EdgeInsets.only(bottom: Space.s2),
                padding: const EdgeInsets.symmetric(
                  horizontal: Space.s4,
                  vertical: Space.s3,
                ),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(Radii.md),
                  border: Border.all(color: c.lineSoft),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        suggestion,
                        style: MemoraText.style(13, color: c.muted),
                      ),
                    ),
                    Icon(MemoraIcons.arrowUpRight, size: 13, color: c.dim),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
    this.enabled = true,
  });

  final TextEditingController controller;
  final VoidCallback onSend;

  /// False while an answer is on its way.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final media = MediaQuery.of(context);
    final bottom = media.viewInsets.bottom > 0 ? 0.0 : media.padding.bottom;
    // The field grows with the text scale, and its tap target with it.
    final box = math.max(42.0, media.textScaler.scale(13.5) * 1.5 + 20);
    final row = math.max(kMinTapTarget, box);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.lineSoft)),
      ),
      child: SizedBox(
        height: Space.s4 + box + Space.s6 + bottom,
        child: Stack(
          children: [
            Positioned(
              left: Space.s4,
              right: Space.s4,
              top: Space.s4,
              height: box,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(Radii.md),
                  border: Border.all(color: c.line),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: Space.s4 + box / 2 - row / 2,
              height: row,
              child: Row(
                children: [
                  const SizedBox(width: Space.s4 + 14),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      maxLines: 1,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => onSend(),
                      cursorColor: c.accent,
                      style: MemoraText.style(13.5, color: c.text),
                      decoration: InputDecoration(
                        isDense: true,
                        isCollapsed: true,
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                        hintText: 'Ask something about your memories…',
                        hintStyle: MemoraText.style(13.5, color: c.dim),
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.s3),
                  TapArea(
                    onTap: enabled ? onSend : null,
                    semanticLabel: 'Send',
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: enabled ? c.accent : c.line),
                      ),
                      child: Icon(
                        MemoraIcons.arrowUp,
                        size: 16,
                        color: enabled ? c.accent : c.dim,
                      ),
                    ),
                  ),
                  const SizedBox(width: Space.s4 + 4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
