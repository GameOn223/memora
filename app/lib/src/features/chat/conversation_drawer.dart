import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:memora_core/memora_core.dart';

import '../../state/chat_controller.dart';
import '../../state/data_version.dart';
import '../../state/services.dart';
import '../../theme/memora_colors.dart';
import '../../theme/memora_icons.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../../widgets/caps_label.dart';
import '../../widgets/fading_rule.dart';
import '../../widgets/memora_icon_button.dart';
import '../../widgets/tap_area.dart';

/// Slides the conversation drawer in from the left edge.
Future<void> showConversationDrawer(BuildContext context) {
  return showGeneralDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    barrierLabel: 'Close conversations',
    barrierColor: context.colors.scrim.withValues(alpha: 0.6),
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (context, animation, secondaryAnimation) => const Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [ConversationDrawer()],
    ),
    transitionBuilder: (context, animation, secondaryAnimation, child) =>
        SlideTransition(
          position: Tween(
            begin: const Offset(-1, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut)),
          child: child,
        ),
  );
}

/// Past conversations, pinned ones first, with what can be done to each.
class ConversationDrawer extends ConsumerWidget {
  const ConversationDrawer({super.key});

  /// Panel width, narrowed on small screens so the scrim stays visible.
  static const double maxWidth = 318;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final padding = MediaQuery.paddingOf(context);
    final conversations = ref.watch(conversationsProvider).value ?? const [];
    final current = ref.watch(chatControllerProvider).conversationId;
    // The drawer opens as its own route, which has no Material above it.
    // Text drawn without one falls back to the engine's default style, which
    // is yellow and double underlined. The panel paints its own background,
    // so this Material is here only to supply that missing default.
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: math.min(maxWidth, MediaQuery.sizeOf(context).width * 0.86),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.surface,
            border: Border(right: BorderSide(color: c.line)),
            boxShadow: Shadows.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  Space.s4,
                  padding.top + Space.s4,
                  Space.s2,
                  0,
                ),
                child: Row(
                  children: [
                    const Expanded(child: CapsLabel('Conversations')),
                    MemoraIconButton(
                      icon: MemoraIcons.x,
                      semanticLabel: 'Close conversations',
                      box: 30,
                      iconSize: 16,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              TapArea(
                onTap: () {
                  ref.read(chatControllerProvider.notifier).startNew();
                  Navigator.of(context).pop();
                },
                semanticLabel: 'New conversation',
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.s4,
                    Space.s3,
                    Space.s4,
                    Space.s3,
                  ),
                  child: Row(
                    children: [
                      Icon(MemoraIcons.plus, size: 15, color: c.accent),
                      const SizedBox(width: Space.s3),
                      Text(
                        'New conversation',
                        style: MemoraText.style(
                          13.5,
                          medium: true,
                          color: c.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Space.s2),
              const FadingRule(fade: 24),
              Expanded(
                child: conversations.isEmpty
                    ? const _EmptyDrawer()
                    : ListView.builder(
                        padding: EdgeInsets.fromLTRB(
                          0,
                          Space.s2,
                          0,
                          Space.s6 + padding.bottom,
                        ),
                        itemCount: conversations.length,
                        itemBuilder: (context, i) => _ConversationRow(
                          conversation: conversations[i],
                          current: conversations[i].id == current,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `Today`, `Yesterday`, `12 Sep`, or `12 Sep 2025` in an earlier year.
String lastUsedLabel(DateTime when, DateTime now) {
  final local = when.toLocal();
  final day = DateTime(local.year, local.month, local.day);
  if (day == DateTime(now.year, now.month, now.day)) return 'Today';
  if (day == DateTime(now.year, now.month, now.day - 1)) return 'Yesterday';
  final format = local.year == now.year ? 'd MMM' : 'd MMM y';
  return DateFormat(format).format(local);
}

/// What a screen reader reads for one row.
String conversationRowLabel(
  Conversation conversation, {
  required bool current,
  required DateTime now,
}) {
  return [
    conversation.title,
    if (conversation.pinned) 'pinned',
    if (current) 'open',
    'last used ${lastUsedLabel(conversation.updatedAt, now).toLowerCase()}',
  ].join(', ');
}

class _ConversationRow extends ConsumerWidget {
  const _ConversationRow({required this.conversation, required this.current});

  final Conversation conversation;

  /// True for the conversation the Ask screen is showing.
  final bool current;

  Future<void> _refresh(WidgetRef ref) =>
      ref.read(dataVersionProvider.notifier).check();

  Future<void> _setPinned(WidgetRef ref, {required bool pinned}) async {
    final services = ref.read(appServicesProvider);
    await services.conversations.setConversationPinned(
      conversation.id,
      pinned,
      ref.read(clockProvider).now(),
    );
    await _refresh(ref);
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final title = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(title: conversation.title),
    );
    if (title == null || title == conversation.title) return;
    final services = ref.read(appServicesProvider);
    await services.conversations.renameConversation(
      conversation.id,
      title,
      ref.read(clockProvider).now(),
    );
    await _refresh(ref);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this conversation?'),
        content: Text(
          '"${conversation.title}" is removed from this phone. Its messages '
          'go with it. The memories it cited are left alone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final services = ref.read(appServicesProvider);
    await services.conversations.deleteConversation(conversation.id);
    // The open conversation just went away, so Ask starts over instead of
    // showing messages that are no longer stored.
    if (current) ref.read(chatControllerProvider.notifier).startNew();
    await _refresh(ref);
  }

  Future<void> _showMenu(BuildContext context, WidgetRef ref) async {
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(
          box.localToGlobal(Offset.zero, ancestor: overlay),
          box.localToGlobal(
            box.size.bottomRight(Offset.zero),
            ancestor: overlay,
          ),
        ),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'pin',
          child: Text(conversation.pinned ? 'Unpin' : 'Pin'),
        ),
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
    if (!context.mounted) return;
    switch (action) {
      case 'pin':
        await _setPinned(ref, pinned: !conversation.pinned);
      case 'rename':
        await _rename(context, ref);
      case 'delete':
        await _delete(context, ref);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final now = ref.watch(clockProvider).now();
    return ColoredBox(
      color: current ? c.accentTint : c.surface,
      child: Row(
        children: [
          // Accent as a line: it marks the open conversation without a fill.
          Container(
            width: 2,
            height: 26,
            color: current ? c.accent : c.accent.withValues(alpha: 0),
          ),
          Expanded(
            child: TapArea(
              onTap: () {
                unawaited(
                  ref
                      .read(chatControllerProvider.notifier)
                      .open(conversation.id),
                );
                Navigator.of(context).pop();
              },
              semanticLabel: conversationRowLabel(
                conversation,
                current: current,
                now: now,
              ),
              selected: current,
              minSize: 0,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.s3,
                  Space.s3,
                  Space.s2,
                  Space.s3,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (conversation.pinned) ...[
                          Icon(
                            MemoraIcons.pushPin,
                            size: 11,
                            color: c.accentInk,
                          ),
                          const SizedBox(width: 5),
                        ],
                        Expanded(
                          child: Text(
                            conversation.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: MemoraText.style(
                              13.5,
                              color: current ? c.accentInk : c.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Space.s1),
                    CapsLabel(
                      lastUsedLabel(conversation.updatedAt, now),
                      size: 9,
                      spacing: 0.9,
                    ),
                  ],
                ),
              ),
            ),
          ),
          MemoraIconButton(
            icon: MemoraIcons.dotsThreeVertical,
            semanticLabel: 'More for ${conversation.title}',
            box: 30,
            iconSize: 16,
            onPressed: () => unawaited(_showMenu(context, ref)),
          ),
          const SizedBox(width: Space.s2),
        ],
      ),
    );
  }
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.title});

  final String title;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.title,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final title = _controller.text.trim();
    if (title.isEmpty) return;
    Navigator.of(context).pop(title);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Rename conversation'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _save(),
        decoration: const InputDecoration(hintText: 'Conversation title'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _save, child: const Text('Rename')),
      ],
    );
  }
}

class _EmptyDrawer extends StatelessWidget {
  const _EmptyDrawer();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s4, Space.s8, Space.s4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(MemoraIcons.chatsCircle, size: 20, color: c.accent),
          const SizedBox(height: Space.s4),
          Text(
            'No conversations yet.',
            style: MemoraText.style(14, medium: true, color: c.text),
          ),
          const SizedBox(height: Space.s2),
          Text(
            'Ask something about your memories and it shows up here, ready '
            'to carry on later.',
            style: MemoraText.style(12.5, height: 1.5, color: c.muted),
          ),
        ],
      ),
    );
  }
}
