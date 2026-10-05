import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/memora_colors.dart';
import '../theme/memora_icons.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';
import 'fading_rule.dart';
import 'tap_area.dart';

/// The four destinations: Memories, Ask, Add and Settings.
class BottomTabs extends StatelessWidget {
  const BottomTabs({
    super.key,
    required this.currentIndex,
    required this.onSelected,
  });

  /// Highlighted tab, or null for none.
  final int? currentIndex;
  final ValueChanged<int> onSelected;

  static const items = [
    ('Memories', MemoraIcons.squaresFour),
    ('Ask', MemoraIcons.sparkle),
    ('Add', MemoraIcons.images),
    ('Settings', MemoraIcons.slidersHorizontal),
  ];

  /// Space the bar covers at the bottom of the screen, excluding the system
  /// inset. Scrolling content pads by this so nothing hides behind it.
  static const double coveredHeight = 104;

  /// Bottom padding under the row, grown to clear the system gesture bar.
  static double bottomPadding(BuildContext context) =>
      math.max(Space.s6, MediaQuery.paddingOf(context).bottom + Space.s2);

  /// How tall the bar draws, for anything that floats above it.
  static double barHeight(BuildContext context) =>
      Space.s8 + 1 + Space.s3 + 48 + bottomPadding(context);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.only(top: Space.s8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [c.bg, c.bg, c.bg.withValues(alpha: 0)],
          stops: const [0, 0.62, 1],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const FadingRule(),
          Padding(
            padding: EdgeInsets.fromLTRB(
              Space.s3,
              Space.s3,
              Space.s3,
              bottomPadding(context),
            ),
            child: Row(
              children: [
                for (final (i, (label, icon)) in items.indexed)
                  Expanded(
                    child: TapArea(
                      onTap: () => onSelected(i),
                      semanticLabel: label,
                      selected: currentIndex == i,
                      child: ConstrainedBox(
                        // At least a 48px target, taller when the label is
                        // scaled up, so nothing overflows.
                        constraints: const BoxConstraints(
                          minHeight: kMinTapTarget,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              icon,
                              size: 20,
                              color: currentIndex == i ? c.accentInk : c.dim,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              label,
                              style: MemoraText.style(
                                9.5,
                                medium: true,
                                spacing: 0.5,
                                color: currentIndex == i ? c.accentInk : c.dim,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
