import 'package:flutter/widgets.dart';

import '../theme/memora_colors.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';
import 'tap_area.dart';

/// A row of options in one outlined group, one of them selected. Used for
/// sort on the browser and for appearance in settings.
class MemoraSegmented extends StatelessWidget {
  const MemoraSegmented({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.height = 34,
  });

  final List<String> labels;
  final String selected;
  final ValueChanged<String> onSelected;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          for (final (i, label) in labels.indexed)
            Expanded(
              child: TapArea(
                onTap: () => onSelected(label),
                semanticLabel: label,
                selected: label == selected,
                minSize: 0,
                child: Container(
                  height: height,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: label == selected
                        ? c.accentTint
                        : c.accentTint.withValues(alpha: 0),
                    border: i == 0
                        ? null
                        : Border(left: BorderSide(color: c.line)),
                  ),
                  child: Text(
                    label,
                    style: MemoraText.style(
                      12,
                      medium: true,
                      color: label == selected ? c.accentInk : c.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
