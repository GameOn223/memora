import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:memora_core/memora_core.dart';

import '../../routing/router.dart';
import '../../state/memories.dart';
import '../../state/queue.dart';
import '../../state/services.dart';
import '../../theme/memora_colors.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../../widgets/bottom_tabs.dart';
import '../../widgets/caps_label.dart';
import '../../widgets/chip_bar.dart';
import '../../widgets/fading_rule.dart';
import '../../widgets/memory_image.dart';
import '../../widgets/memory_labels.dart';
import '../../widgets/screen_body.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/segmented.dart';
import '../../widgets/tap_area.dart';

/// Browse everything: sort, facets with counts, and a dense results grid.
class BrowserScreen extends ConsumerStatefulWidget {
  const BrowserScreen({super.key});

  @override
  ConsumerState<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends ConsumerState<BrowserScreen> {
  MemorySort _sort = MemorySort.newest;
  String? _category;
  String? _taken;
  String? _status;

  static const _sorts = [
    ('Newest', MemorySort.newest),
    ('Oldest', MemorySort.oldest),
    ('Category', MemorySort.category),
  ];

  static const _statusFilters = {
    'Ready': {ProcessingStatus.ready},
    'In queue': {
      ProcessingStatus.captured,
      ProcessingStatus.processing,
      ProcessingStatus.reprocessing,
    },
    'Failed': {ProcessingStatus.failed},
  };

  DateRange? _takenRange(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (_taken) {
      'Today' => DateRange(start: today),
      'This week' => DateRange(
        start: today.subtract(Duration(days: now.weekday - 1)),
      ),
      'This month' => DateRange(start: DateTime(now.year, now.month)),
      final String label when label == '${now.year}' => DateRange(
        start: DateTime(now.year),
      ),
      _ => null,
    };
  }

  void _toggle(String group, String label) {
    setState(() {
      switch (group) {
        case 'Category':
          _category = _category == label ? null : label;
        case 'Image taken':
          _taken = _taken == label ? null : label;
        case 'Processing':
          _status = _status == label ? null : label;
      }
    });
  }

  String? _selected(String group) => switch (group) {
    'Category' => _category,
    'Image taken' => _taken,
    _ => _status,
  };

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final now = ref.watch(clockProvider).now();
    final options = ref.watch(categoryOptionsProvider).value ?? const [];
    final everything = ref.watch(allMemoriesProvider).value ?? const [];
    final summary = ref.watch(queueSummaryProvider).value;
    final categories = options
        .where((o) => o.label == _category)
        .map((o) => o.categories)
        .firstOrNull;
    final filter = MemoryFilter(
      sort: _sort,
      categories: categories ?? const {},
      statuses: _statusFilters[_status] ?? const {},
      takenBetween: _takenRange(now),
    );
    final results = ref.watch(memoriesProvider(filter)).value ?? const [];
    final total = everything.length;

    int takenCount(String label) {
      final range = switch (label) {
        'Today' => DateRange(start: DateTime(now.year, now.month, now.day)),
        'This week' => DateRange(
          start: DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(Duration(days: now.weekday - 1)),
        ),
        'This month' => DateRange(start: DateTime(now.year, now.month)),
        _ => DateRange(start: DateTime(now.year)),
      };
      return everything.where((m) => range.contains(m.takenAt)).length;
    }

    final facets = <String, List<(String, int)>>{
      'Category': [
        for (final option in options.where((o) => o.label != 'All'))
          (option.label, option.count),
      ],
      'Image taken': [
        for (final label in ['Today', 'This week', 'This month', '${now.year}'])
          (label, takenCount(label)),
      ],
      'Processing': [
        ('Ready', summary?.ready ?? 0),
        ('In queue', (summary?.waiting ?? 0) + (summary?.processing ?? 0)),
        ('Failed', summary?.failed ?? 0),
      ],
    };

    return ScreenBody(
      header: ScreenHeader(
        title: 'All memories',
        onLeading: () => context.pop(),
        trailing: [
          Text(
            '$total',
            style: MemoraText.caps(
              9.5,
              spacing: 1,
              tabular: true,
              color: c.dim,
            ),
          ),
        ],
      ),
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              Space.s6,
              0,
              Space.s6,
              BottomTabs.coveredHeight + MediaQuery.paddingOf(context).bottom,
            ),
            sliver: SliverMainAxisGroup(
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const CapsLabel('Sort', size: 9.5),
                      const SizedBox(height: Space.s3),
                      MemoraSegmented(
                        labels: [for (final (label, _) in _sorts) label],
                        selected: _sorts.firstWhere((s) => s.$2 == _sort).$1,
                        onSelected: (label) => setState(() {
                          _sort = _sorts.firstWhere((s) => s.$1 == label).$2;
                        }),
                      ),
                      for (final facet in facets.entries) ...[
                        const SizedBox(height: Space.s8),
                        CapsLabel(facet.key, size: 9.5),
                        const SizedBox(height: Space.s3),
                        Wrap(
                          spacing: Space.s2,
                          runSpacing: Space.s2,
                          children: [
                            for (final (label, count) in facet.value)
                              SelectChip(
                                label: label,
                                count: '$count',
                                selected: _selected(facet.key) == label,
                                horizontalPadding: 10,
                                onTap: () => _toggle(facet.key, label),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: Space.s8),
                      const FadingRule(),
                      const SizedBox(height: Space.s8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const CapsLabel('Results', size: 9.5),
                          const Spacer(),
                          Text(
                            '${results.length} of $total',
                            style: MemoraText.caps(
                              9.5,
                              spacing: 0.8,
                              tabular: true,
                              color: c.dim,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: Space.s4),
                    ],
                  ),
                ),
                SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: Space.s2,
                    crossAxisSpacing: Space.s2,
                    childAspectRatio: 3 / 4,
                  ),
                  delegate: SliverChildBuilderDelegate((context, i) {
                    final memory = results[i];
                    return TapArea(
                      onTap: () => context.push(Routes.memory(memory.id)),
                      semanticLabel: memoryTitle(memory),
                      minSize: 0,
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(Radii.sm),
                        ),
                        foregroundDecoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(Radii.sm),
                          border: Border.all(color: c.lineSoft),
                        ),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            MemoryImageView(
                              path: memory.thumbnailPath,
                              cacheWidth: 360,
                            ),
                            if (memory.category != null)
                              Positioned(
                                left: 5,
                                right: 5,
                                bottom: 5,
                                child: CapsLabel(
                                  humanizeKey(memory.category!),
                                  size: 7.5,
                                  spacing: 0.8,
                                  color: c.muted,
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  }, childCount: results.length),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
