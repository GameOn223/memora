import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../routing/router.dart';
import '../../state/memories.dart';
import '../../state/services.dart';
import '../../theme/memora_colors.dart';
import '../../theme/memora_icons.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../../widgets/bottom_tabs.dart';
import '../../widgets/fading_rule.dart';
import '../../widgets/memory_tile.dart';
import '../../widgets/section_header.dart';
import '../../widgets/tap_area.dart';
import 'home_header.dart';

/// The memories grid: date groups of tiles, with the ask bar on top.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memories = ref.watch(memoriesProvider(const MemoryFilter())).value;
    final now = ref.watch(clockProvider).now();
    final groups = groupByTakenDate(memories ?? const [], now);
    return SafeArea(
      bottom: false,
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HomeHeader(),
          const AskBar(),
          const FadingRule(),
          Expanded(child: MemoryGrid(groups: groups, columns: 2)),
        ],
      ),
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
                        count: '${group.items.length}',
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
                          return MemoryTile(
                            memory: memory,
                            columns: columns,
                            onTap: () => context.push(Routes.memory(memory.id)),
                          );
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
