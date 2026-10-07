import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:memora_core/memora_core.dart';

import '../../routing/router.dart';
import '../../state/memories.dart';
import '../../state/queue.dart';
import '../../state/services.dart';
import '../../state/settings.dart';
import '../../state/ui_state.dart';
import '../../theme/memora_colors.dart';
import '../../theme/memora_icons.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../../widgets/added_toast.dart';
import '../../widgets/bottom_tabs.dart';
import '../../widgets/density_toggle.dart';
import '../../widgets/fading_rule.dart';
import '../../widgets/memory_labels.dart';
import '../../widgets/memory_tile.dart';
import '../../widgets/section_header.dart';
import '../../widgets/tap_area.dart';
import '../queue/block_notice.dart';
import 'category_filter.dart';
import 'empty_state.dart';
import 'home_header.dart';

/// The memories grid: date groups of tiles, with the ask bar, category
/// chips and the density toggle above them.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  /// Height of the chip row, which also makes the chips easy to hit.
  static const double controlsHeight = 52.4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(storageStatsProvider);
    if (stats.hasValue && !ref.watch(hasMemoriesProvider)) {
      return const EmptyState();
    }
    final options = ref.watch(categoryOptionsProvider).value ?? const [];
    final chosen = ref.watch(homeFilterProvider);
    // Several labels are a union, so the raw categories behind each chosen
    // one are gathered up. Nothing chosen is no filter at all.
    final categories = <String>{
      for (final option in options)
        if (chosen.contains(option.label)) ...option.categories,
    };
    final columns = ref.watch(gridColumnsProvider).value ?? 2;
    final memories = ref
        .watch(memoriesProvider(MemoryFilter(categories: categories)))
        .value;
    final now = ref.watch(clockProvider).now();
    final groups = groupByTakenDate(memories ?? const [], now);

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const HomeHeader(),
            const AskBar(),
            const FadingRule(),
            SizedBox(
              height: controlsHeight,
              child: Row(
                children: [
                  const SizedBox(width: Space.s6),
                  const Expanded(child: CategoryFilter(height: controlsHeight)),
                  const SizedBox(width: Space.s4),
                  DensityToggle(
                    columns: columns,
                    hitHeight: controlsHeight,
                    onChanged: (value) =>
                        ref.read(gridColumnsProvider.notifier).set(value),
                  ),
                  const SizedBox(width: Space.s6),
                ],
              ),
            ),
            Expanded(
              child: MemoryGrid(groups: groups, columns: columns),
            ),
          ],
        ),
        const _ToastHost(),
      ],
    );
  }
}

/// Opens Ask from the top of the memories screen.
class AskBar extends StatelessWidget {
  const AskBar({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.s6, 0, Space.s6, Space.s4),
      child: TapArea(
        onTap: () => context.go(Routes.ask),
        semanticLabel: 'Ask your memories',
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(color: c.line),
          ),
          child: Row(
            children: [
              Icon(MemoraIcons.sparkle, size: 17, color: c.accent),
              const SizedBox(width: Space.s4),
              Expanded(
                child: Text(
                  'Ask your memories…',
                  style: MemoraText.style(14, color: c.muted),
                ),
              ),
              Icon(MemoraIcons.arrowUpRight, size: 15, color: c.dim),
            ],
          ),
        ),
      ),
    );
  }
}

/// Date-grouped grid of memory tiles with sticky group headers.
class MemoryGrid extends ConsumerWidget {
  const MemoryGrid({
    super.key,
    required this.groups,
    required this.columns,
    this.bottomPadding = BottomTabs.coveredHeight,
  });

  final List<DateGroup> groups;
  final int columns;
  final double bottomPadding;

  static double gapFor(int columns) => switch (columns) {
    2 => Space.s3,
    4 => Space.s2,
    _ => Space.s1,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final gap = gapFor(columns);
    final bottom = bottomPadding + MediaQuery.paddingOf(context).bottom;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(Space.s6, 0, Space.s6, bottom),
          sliver: SliverMainAxisGroup(
            slivers: [
              for (final group in groups)
                SliverMainAxisGroup(
                  slivers: [
                    PinnedHeaderSliver(
                      child: SectionHeader(
                        label: group.label,
                        count: imageCount(group.items.length),
                        background: c.bg,
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.only(
                        top: Space.s3,
                        bottom: Space.s6,
                      ),
                      sliver: SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          mainAxisSpacing: gap,
                          crossAxisSpacing: gap,
                          childAspectRatio: 3 / 4,
                        ),
                        delegate: SliverChildBuilderDelegate((context, i) {
                          final memory = group.items[i];
                          return _Tile(memory: memory, columns: columns);
                        }, childCount: group.items.length),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Tile extends ConsumerWidget {
  const _Tile({required this.memory, required this.columns});

  final Memory memory;
  final int columns;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Facts are only shown on the large tiles, so only load them there.
    final fact = columns == 2 && memory.status == ProcessingStatus.ready
        ? ref.watch(memoryFactProvider(memory.id)).value
        : null;
    return MemoryTile(
      memory: memory,
      columns: columns,
      fact: fact,
      onTap: () => context.push(Routes.memory(memory.id)),
    );
  }
}

/// Shows the toast after images are added, then clears it.
class _ToastHost extends ConsumerStatefulWidget {
  const _ToastHost();

  @override
  ConsumerState<_ToastHost> createState() => _ToastHostState();
}

class _ToastHostState extends ConsumerState<_ToastHost> {
  static const _visibleFor = Duration(milliseconds: 5200);
  static const _visibleForBlocked = Duration(milliseconds: 9000);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // The timer lives outside build: a rebuild from the data version poll
    // would otherwise keep pushing the dismissal back.
    _schedule(ref.read(addedToastProvider));
    ref.listenManual(addedToastProvider, (previous, next) => _schedule(next));
  }

  void _schedule(AddedOutcome? outcome) {
    _timer?.cancel();
    if (outcome == null) return;
    // A toast that asks for a decision stays up long enough to read it.
    _timer = Timer(
      outcome.block == null ? _visibleFor : _visibleForBlocked,
      () {
        if (mounted) ref.read(addedToastProvider.notifier).clear();
      },
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final outcome = ref.watch(addedToastProvider);
    if (outcome == null) return const SizedBox.shrink();
    final policy = ref.watch(queuePolicyProvider).value ?? const QueuePolicy();
    final block = outcome.block;
    final notice = block == null
        ? null
        : blockNotice(
            block,
            providers: ref.read(appServicesProvider).providers,
          );
    return Positioned(
      left: 14,
      right: 14,
      bottom: BottomTabs.barHeight(context) + Space.s3,
      child: AddedToast(
        result: outcome.result,
        overnight: policy.mode == QueueMode.overnight,
        windowStart: clockTime(policy.windowStartMinutes),
        notice: notice,
        onQueue: () {
          ref.read(addedToastProvider.notifier).clear();
          if (notice == null) {
            context.push(Routes.queue);
          } else {
            context.go(notice.route);
          }
        },
      ),
    );
  }
}
