import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:memora_core/memora_core.dart';

import '../../routing/router.dart';
import '../../state/data_version.dart';
import '../../state/queue.dart';
import '../../state/services.dart';
import '../../theme/memora_colors.dart';
import '../../theme/memora_icons.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../../widgets/bordered_list.dart';
import '../../widgets/caps_label.dart';
import '../../widgets/memory_image.dart';
import '../../widgets/memory_labels.dart';
import '../../widgets/motion.dart';
import '../../widgets/outline_action.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/tap_area.dart';
import '../../widgets/toggle_card.dart';

/// What Memora is understanding, what is waiting, and what went wrong.
class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  /// True after "Process now", until the queue is paused again.
  bool _runningNow = false;

  Future<void> _refresh() => ref.read(dataVersionProvider.notifier).check();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final view = ref.watch(queueViewProvider).value;
    final services = ref.read(appServicesProvider);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final summary = view?.summary ?? QueueSummary.empty;
    final policy = view?.policy ?? const QueuePolicy();
    final overnight = policy.mode == QueueMode.overnight;
    final now = ref.watch(clockProvider).now();
    final running =
        !policy.paused &&
        (_runningNow || !overnight || policy.isInsideWindow(now));
    final progress = summary.total == 0 ? 0.0 : summary.ready / summary.total;

    return ColoredBox(
      color: c.bg,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScreenHeader(
                title: 'Processing queue',
                onLeading: () => popOrHome(context),
              ),
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    Space.s6,
                    0,
                    Space.s6,
                    100 + bottomInset,
                  ),
                  children: [
                    _SummaryCard(
                      summary: summary,
                      progress: progress,
                      copy: statusCopy(
                        summary: summary,
                        policy: policy,
                        running: running,
                      ),
                    ),
                    if (view?.block != null) ...[
                      const SizedBox(height: Space.s6),
                      _BlockBanner(block: view!.block!),
                    ],
                    const SizedBox(height: Space.s6),
                    ToggleCard(
                      value: overnight,
                      icon: MemoraIcons.moonStars,
                      title: 'Process overnight',
                      body: overnightDetail(overnight: overnight),
                      onChanged: (value) async {
                        await ref
                            .read(queuePolicyProvider.notifier)
                            .setMode(
                              value ? QueueMode.overnight : QueueMode.immediate,
                            );
                        if (value) setState(() => _runningNow = false);
                        await _refresh();
                      },
                    ),
                    const SizedBox(height: Space.s2),
                    _InfoCard(
                      icon: MemoraIcons.arrowLineDown,
                      title: 'One image at a time',
                      body:
                          'Serial processing keeps the phone responsive and '
                          'stays inside provider rate limits. Order is '
                          'oldest first.',
                    ),
                    const SizedBox(height: Space.s6),
                    const CapsLabel('In the queue'),
                    const SizedBox(height: Space.s3),
                    BorderedList(
                      children: [
                        for (final item in view?.items ?? const <QueueItem>[])
                          _QueueRow(
                            item: item,
                            hasActive: summary.processing > 0,
                            onRetry: () async {
                              await services.queue.retry(
                                item.memory.id,
                                ref.read(clockProvider).now(),
                              );
                              await services.scheduler.refresh();
                              await _refresh();
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: Space.s3),
                    Text(
                      'Images are browsable the moment they are added. '
                      'Everything below the current item is waiting on '
                      'vision, not on you.',
                      style: MemoraText.style(12, height: 1.55, color: c.dim),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [c.bg, c.bg, c.bg.withValues(alpha: 0)],
                  stops: const [0, 0.68, 1],
                ),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  Space.s4,
                  Space.s4,
                  Space.s4,
                  Space.s6 + bottomInset,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlineAction(
                        label: policy.paused
                            ? 'Resume queue'
                            : running
                            ? 'Pause queue'
                            : 'Process now',
                        icon: policy.paused
                            ? MemoraIcons.play
                            : running
                            ? MemoraIcons.pause
                            : MemoraIcons.lightning,
                        height: 44,
                        fontSize: 13.5,
                        iconSize: 15,
                        onPressed: () async {
                          final controller = ref.read(
                            queuePolicyProvider.notifier,
                          );
                          if (policy.paused) {
                            await controller.setPaused(paused: false);
                          } else if (running) {
                            setState(() => _runningNow = false);
                            await controller.setPaused(paused: true);
                          } else {
                            setState(() => _runningNow = true);
                            await services.scheduler.processNow();
                          }
                          await _refresh();
                        },
                      ),
                    ),
                    const SizedBox(width: Space.s2),
                    OutlineAction(
                      label: 'Add more',
                      tone: ActionTone.neutral,
                      height: 44,
                      fontSize: 13.5,
                      expand: false,
                      onPressed: () => context.go(Routes.add),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The line under the progress bar on the queue screen.
String statusCopy({
  required QueueSummary summary,
  required QueuePolicy policy,
  required bool running,
}) {
  final waiting = summary.waiting + summary.processing;
  if (policy.paused) {
    return 'Queue paused. Added images stay browsable; nothing is sent '
        'until you resume.';
  }
  if (waiting == 0) {
    return 'Everything added so far is understood.';
  }
  final images = waiting == 1 ? '1 image' : '$waiting images';
  if (running) {
    return 'Processing now, one image at a time. $images waiting.';
  }
  return 'Paused until ${clockTime(policy.windowStartMinutes)} tonight. '
      '$images waiting, one at a time, oldest first.';
}

/// The detail line under "Process overnight".
String overnightDetail({required bool overnight}) => overnight
    ? 'Runs between 01:00 and 07:00 while charging and on Wi-Fi. Vision '
          'calls are the expensive part, so a large backlog clears while '
          'you sleep.'
    : 'Runs as soon as each image is added. Faster, but heavier on battery '
          'and provider quota.';

/// State line for one queue row, such as `Queued · 3rd`.
String queueRowState(QueueItem item, {required bool hasActive}) {
  final memory = item.memory;
  return switch (memory.status) {
    ProcessingStatus.processing => 'Processing · vision',
    ProcessingStatus.failed =>
      'Failed · ${memory.failureReason ?? 'could not process'}',
    ProcessingStatus.ready => 'Understood',
    _ => switch (item.position) {
      null => 'Queued',
      1 => 'Queued · next',
      final int p => 'Queued · ${ordinal(p + (hasActive ? 1 : 0))}',
    },
  };
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.summary,
    required this.progress,
    required this.copy,
  });

  final QueueSummary summary;
  final double progress;
  final String copy;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: c.accentTint,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.accentLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${summary.ready}',
                style: MemoraText.style(
                  26,
                  medium: true,
                  spacing: -0.8,
                  tabular: true,
                  color: c.text,
                ),
              ),
              const SizedBox(width: Space.s3),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: CapsLabel(
                  'of ${summary.total} understood',
                  size: 12,
                  spacing: 1.1,
                  color: c.muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.s3),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: SizedBox(
              height: 3,
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: c.lineSoft,
                valueColor: AlwaysStoppedAnimation(c.accent),
              ),
            ),
          ),
          const SizedBox(height: Space.s3),
          Text(copy, style: MemoraText.style(12.5, height: 1.5, color: c.text)),
        ],
      ),
    );
  }
}

class _BlockBanner extends StatelessWidget {
  const _BlockBanner({required this.block});

  final QueueBlock block;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final message = switch (block) {
      NoVisionProvider() =>
        'AI processing is not configured, so nothing is being understood.',
      BlockedByLocalOnly(:final providerName) =>
        'Local-only mode blocks $providerName, so nothing is being '
            'understood.',
      ProviderConfigurationProblem(:final message) => message,
    };
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.accentLine),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(MemoraIcons.warningCircle, size: 17, color: c.accent),
          const SizedBox(width: Space.s4),
          Expanded(
            child: Text(
              message,
              style: MemoraText.style(12.5, height: 1.55, color: c.text),
            ),
          ),
          const SizedBox(width: Space.s3),
          TapArea(
            onTap: () => context.go(Routes.settings),
            semanticLabel: 'Open settings',
            minSize: 0,
            child: Text(
              'Settings',
              style: MemoraText.style(12.5, medium: true, color: c.accentInk),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.lineSoft),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: c.muted),
          const SizedBox(width: Space.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: MemoraText.style(14, medium: true, color: c.text),
                ),
                const SizedBox(height: Space.s1),
                Text(
                  body,
                  style: MemoraText.style(12, height: 1.5, color: c.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.item,
    required this.hasActive,
    required this.onRetry,
  });

  final QueueItem item;
  final bool hasActive;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final memory = item.memory;
    final active = memory.status == ProcessingStatus.processing;
    final failed = memory.status == ProcessingStatus.failed;
    final done = memory.status == ProcessingStatus.ready;
    final state = queueRowState(item, hasActive: hasActive);
    return TapArea(
      onTap: () => context.push(Routes.memory(memory.id)),
      semanticLabel: '${memoryTitle(memory)}, $state',
      minSize: 0,
      child: Container(
        color: active ? c.accentTint : null,
        padding: const EdgeInsets.symmetric(
          vertical: Space.s3,
          horizontal: Space.s4,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 30,
              height: 38,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.sm),
                child: MemoryImageView(
                  path: memory.thumbnailPath,
                  cacheWidth: 120,
                ),
              ),
            ),
            const SizedBox(width: Space.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    memoryTitle(memory),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: MemoraText.style(12.5, medium: true, color: c.text),
                  ),
                  const SizedBox(height: Space.s1),
                  CapsLabel(
                    state,
                    size: 9.5,
                    spacing: 0.9,
                    color: done
                        ? c.dim
                        : active
                        ? c.accentInk
                        : failed
                        ? c.muted
                        : c.dim,
                  ),
                  if (active) ...[
                    const SizedBox(height: Space.s2),
                    const SweepBar(),
                  ],
                ],
              ),
            ),
            if (failed) ...[
              const SizedBox(width: Space.s3),
              TapArea(
                onTap: () => unawaited(onRetry()),
                semanticLabel: 'Retry ${memoryTitle(memory)}',
                minSize: 0,
                child: Container(
                  height: 24,
                  padding: const EdgeInsets.symmetric(horizontal: Space.s3),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.sm),
                    border: Border.all(color: c.accent),
                  ),
                  child: Text(
                    'Retry',
                    style: MemoraText.style(
                      11,
                      medium: true,
                      color: c.accentInk,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(width: Space.s3),
            Text(
              DateFormat('d MMM').format(memory.takenAt),
              style: MemoraText.caps(
                9.5,
                spacing: 0.8,
                tabular: true,
                color: c.dim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
