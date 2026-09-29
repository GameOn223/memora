import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:memora_core/memora_core.dart';

import '../../routing/router.dart';
import '../../state/chat_controller.dart';
import '../../state/data_version.dart';
import '../../state/memories.dart';
import '../../state/services.dart';
import '../../theme/memora_colors.dart';
import '../../theme/memora_icons.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../../widgets/caps_label.dart';
import '../../widgets/memora_icon_button.dart';
import '../../widgets/memory_image.dart';
import '../../widgets/memory_labels.dart';
import '../../widgets/outline_action.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/status_dot.dart';
import '../../widgets/tags.dart';
import '../../widgets/tap_area.dart';
import 'memory_facts.dart';

/// Everything Memora knows about one image, and what to do with it.
class DetailScreen extends ConsumerStatefulWidget {
  const DetailScreen({super.key, required this.memoryId});

  final String memoryId;

  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  @override
  void initState() {
    super.initState();
    final services = ref.read(appServicesProvider);
    unawaited(
      services.memories.markViewed(
        widget.memoryId,
        ref.read(clockProvider).now(),
      ),
    );
  }

  Future<void> _delete(MemoryDetails details) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this memory?'),
        content: const Text(
          'The image, everything Memora extracted from it and its search '
          'entries are removed from this phone. This cannot be undone.',
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
    if (confirmed != true || !mounted) return;
    final services = ref.read(appServicesProvider);
    final files = await services.memories.deleteMemory(details.memory.id);
    if (files != null) await services.images.delete(files.all);
    await ref.read(dataVersionProvider.notifier).check();
    if (mounted) popOrHome(context);
  }

  Future<void> _reprocess(MemoryDetails details) async {
    final services = ref.read(appServicesProvider);
    await services.queue.requestReprocess(
      details.memory.id,
      ref.read(clockProvider).now(),
    );
    await services.scheduler.refresh();
    await ref.read(dataVersionProvider.notifier).check();
    if (mounted) context.go(Routes.queue);
  }

  Future<void> _retry(MemoryDetails details) async {
    final services = ref.read(appServicesProvider);
    await services.queue.retry(
      details.memory.id,
      ref.read(clockProvider).now(),
    );
    await services.scheduler.refresh();
    await ref.read(dataVersionProvider.notifier).check();
  }

  void _openImage(MemoryDetails details) {
    unawaited(
      showGeneralDialog<void>(
        context: context,
        barrierColor: Colors.black,
        barrierDismissible: true,
        barrierLabel: 'Close image',
        pageBuilder: (context, _, _) =>
            _FullImage(path: details.memory.imagePath),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final details = ref.watch(memoryDetailsProvider(widget.memoryId)).value;
    final bottom = MediaQuery.paddingOf(context).bottom;
    if (details == null) {
      return ColoredBox(
        color: c.bg,
        child: Column(
          children: [
            ScreenHeader(title: 'Memory', onLeading: () => context.pop()),
            const Spacer(),
          ],
        ),
      );
    }
    final memory = details.memory;
    final status = StatusStyle.of(memory.status, c);
    final rows = factRows(details);

    return ColoredBox(
      color: c.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(
            title: 'Memory',
            onLeading: () => popOrHome(context),
            trailing: [
              MemoraIconButton(
                icon: MemoraIcons.dotsThreeVertical,
                semanticLabel: 'More actions',
                box: 30,
                iconSize: 18,
                onPressed: () => unawaited(_showMenu(details)),
              ),
            ],
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.only(bottom: Space.s8 + bottom),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.s6),
                  child: TapArea(
                    onTap: () => _openImage(details),
                    semanticLabel: 'Open the original image',
                    minSize: 0,
                    child: SizedBox(
                      height: 258,
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(Radii.md),
                        ),
                        foregroundDecoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(Radii.md),
                          border: Border.all(color: c.line),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            MemoryImageView(
                              path: memory.imagePath,
                              stripe: 7,
                              cacheWidth: 1080,
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(
                                  Space.s4,
                                  Space.s6,
                                  Space.s4,
                                  Space.s4,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.bottomCenter,
                                    end: Alignment.topCenter,
                                    colors: [
                                      c.scrim,
                                      c.scrim.withValues(alpha: 0),
                                    ],
                                  ),
                                ),
                                child: CapsLabel(
                                  imageMeta(memory),
                                  size: 8,
                                  spacing: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.s6,
                    Space.s6,
                    Space.s6,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (memory.category != null) ...[
                            Tag(memory.category!),
                            const SizedBox(width: Space.s3),
                          ],
                          Tag(
                            status.label,
                            tone: memory.status == ProcessingStatus.ready
                                ? TagTone.accent
                                : TagTone.neutral,
                            leadingDot: memory.status == ProcessingStatus.ready,
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.s3),
                      Text(
                        memoryTitle(memory),
                        style: MemoraText.style(
                          20,
                          medium: true,
                          height: 1.3,
                          spacing: -0.4,
                          color: c.text,
                        ),
                      ),
                      if (memory.visualDescription case final String d) ...[
                        const SizedBox(height: Space.s3),
                        Text(
                          d,
                          style: MemoraText.style(
                            13,
                            height: 1.55,
                            color: c.muted,
                          ),
                        ),
                      ],
                      if (memory.status == ProcessingStatus.failed) ...[
                        const SizedBox(height: Space.s4),
                        _FailureCard(
                          reason: memory.failureReason,
                          onRetry: () => unawaited(_retry(details)),
                        ),
                      ],
                    ],
                  ),
                ),
                if (rows.isNotEmpty) ...[
                  const SizedBox(height: Space.s6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.s6),
                    child: _FactsTable(rows: rows),
                  ),
                ],
                if (memory.addedLater) ...[
                  const SizedBox(height: Space.s4),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.s6),
                    child: _FiledUnderNote(memory: memory),
                  ),
                ],
                if (details.keywords.isNotEmpty) ...[
                  const SizedBox(height: Space.s8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.s6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const CapsLabel('Keywords'),
                        const SizedBox(height: Space.s3),
                        Wrap(
                          spacing: Space.s2,
                          runSpacing: Space.s2,
                          children: [
                            for (final keyword in details.keywords)
                              KeywordChip(keyword),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                if (details.conversationCount > 0) ...[
                  const SizedBox(height: Space.s8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.s6),
                    child: TapArea(
                      onTap: () => context.go(Routes.ask),
                      semanticLabel: 'Conversations using this memory',
                      minSize: 0,
                      child: Container(
                        padding: const EdgeInsets.all(Space.s4),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(Radii.md),
                          border: Border.all(color: c.lineSoft),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              MemoraIcons.chatsCircle,
                              size: 17,
                              color: c.accent,
                            ),
                            const SizedBox(width: Space.s4),
                            Expanded(
                              child: Text(
                                'Used in ${conversationCount(details.conversationCount)}',
                                style: MemoraText.style(13, color: c.text),
                              ),
                            ),
                            Icon(
                              MemoraIcons.caretRight,
                              size: 13,
                              color: c.dim,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: Space.s8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.s6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in provenanceLines(details))
                        CapsLabel(
                          line,
                          size: 9.5,
                          spacing: 0.9,
                          height: 1.9,
                          maxLines: null,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.s8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.s6),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlineAction(
                          label: 'Ask about this',
                          icon: MemoraIcons.sparkle,
                          height: 42,
                          fontSize: 13.5,
                          iconSize: 15,
                          onPressed: () {
                            ref
                                .read(chatControllerProvider.notifier)
                                .startNew(focusMemoryId: memory.id);
                            context.go(Routes.ask);
                          },
                        ),
                      ),
                      if (memory.status == ProcessingStatus.ready) ...[
                        const SizedBox(width: Space.s3),
                        OutlineAction(
                          label: 'Reprocess',
                          tone: ActionTone.neutral,
                          height: 42,
                          fontSize: 13.5,
                          expand: false,
                          onPressed: () => unawaited(_reprocess(details)),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showMenu(MemoryDetails details) async {
    final box = context.findRenderObject()! as RenderBox;
    final size = box.size;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        size.width - 200,
        MediaQuery.paddingOf(context).top + 56,
        Space.s4,
        0,
      ),
      items: const [
        PopupMenuItem(value: 'delete', child: Text('Delete memory')),
      ],
    );
    if (action == 'delete') await _delete(details);
  }
}

/// `3 conversations`, `1 conversation`.
String conversationCount(int n) =>
    n == 1 ? '1 conversation' : '$n conversations';

class _FactsTable extends StatelessWidget {
  const _FactsTable({required this.rows});

  final List<FactRow> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: c.surface2,
            padding: const EdgeInsets.symmetric(
              horizontal: Space.s4,
              vertical: 7,
            ),
            child: const CapsLabel('Extracted', size: 8.5, spacing: 1.2),
          ),
          Container(height: 1, color: c.line),
          for (final (i, (label, value)) in rows.indexed)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i == rows.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: c.lineSoft)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(Space.s4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 104,
                      child: CapsLabel(
                        label,
                        size: 9.5,
                        spacing: 1,
                        height: 1.5,
                        maxLines: 2,
                      ),
                    ),
                    const SizedBox(width: Space.s4),
                    Expanded(
                      child: Text(
                        value,
                        style: MemoraText.style(
                          14,
                          medium: true,
                          tabular: true,
                          color: c.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FiledUnderNote extends StatelessWidget {
  const _FiledUnderNote({required this.memory});

  final Memory memory;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final note = filedUnderNote(memory);
    final date = DateFormat('d MMMM y').format(memory.takenAt);
    final parts = note.split(date);
    final body = MemoraText.style(12, height: 1.55, color: c.muted);
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.lineSoft),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              MemoraIcons.clockCounterClockwise,
              size: 16,
              color: c.muted,
            ),
          ),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: parts.first),
                  TextSpan(
                    text: date,
                    style: body.copyWith(
                      color: c.text,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  if (parts.length > 1) TextSpan(text: parts[1]),
                ],
              ),
              style: body,
            ),
          ),
        ],
      ),
    );
  }
}

class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.reason, required this.onRetry});

  final String? reason;
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
              'Could not process: ${reason ?? 'the provider refused it'}.',
              style: MemoraText.style(12.5, height: 1.5, color: c.text),
            ),
          ),
          const SizedBox(width: Space.s3),
          OutlineAction(
            label: 'Retry',
            height: 28,
            fontSize: 12,
            expand: false,
            horizontalPadding: Space.s3,
            onPressed: onRetry,
          ),
        ],
      ),
    );
  }
}

class _FullImage extends ConsumerWidget {
  const _FullImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: MemoryImageView(path: path, fit: BoxFit.contain),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(context).top + Space.s2,
            right: Space.s2,
            child: MemoraIconButton(
              icon: MemoraIcons.x,
              semanticLabel: 'Close image',
              color: Colors.white,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
