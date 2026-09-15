import 'package:flutter/widgets.dart';

import '../theme/memora_colors.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';
import 'tap_area.dart';

/// A selectable pill: tinted with an accent hairline when selected.
class SelectChip extends StatelessWidget {
  const SelectChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.horizontalPadding = Space.s4,
    this.hitHeight,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  /// Optional count shown dim after the label.
  final String? count;
  final double horizontalPadding;

  /// Taller invisible hit area, for chips that sit in a padded row.
  final double? hitHeight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final pill = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      height: 28,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.sm),
        color: selected ? c.accentTint : c.accentTint.withValues(alpha: 0),
        border: Border.all(color: selected ? c.accentLine : c.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            style: MemoraText.style(
              12,
              medium: true,
              color: selected ? c.accentInk : c.muted,
            ),
          ),
          if (count != null) ...[
            const SizedBox(width: 7),
            Text(
              count!,
              style: MemoraText.style(
                9.5,
                medium: true,
                tabular: true,
                color: c.dim,
              ),
            ),
          ],
        ],
      ),
    );
    return TapArea(
      onTap: onTap,
      semanticLabel: count == null ? label : '$label, $count',
      selected: selected,
      minSize: 0,
      child: hitHeight == null
          ? pill
          : SizedBox(
              height: hitHeight,
              child: Center(child: pill),
            ),
    );
  }
}

/// A horizontally scrolling row of [SelectChip]s.
class ChipBar extends StatelessWidget {
  const ChipBar({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.height = 28,
  });

  final List<String> labels;
  final String selected;
  final ValueChanged<String> onSelected;

  /// Height of the scrolling row. Chips stay 28px and center in it.
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.s2),
        itemBuilder: (context, i) => SelectChip(
          label: labels[i],
          selected: labels[i] == selected,
          onTap: () => onSelected(labels[i]),
          hitHeight: height,
        ),
      ),
    );
  }
}
