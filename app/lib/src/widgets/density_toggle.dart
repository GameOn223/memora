import 'package:flutter/widgets.dart';

import '../theme/memora_colors.dart';
import '../theme/memora_icons.dart';
import '../theme/tokens.dart';
import 'tap_area.dart';

/// Switches the memories grid between 2, 4 and 8 columns.
class DensityToggle extends StatelessWidget {
  const DensityToggle({
    super.key,
    required this.columns,
    required this.onChanged,
    this.hitHeight = 28,
  });

  final int columns;
  final ValueChanged<int> onChanged;

  /// Height of the tappable cells. The visual group stays 28px tall.
  final double hitHeight;

  static const _options = [
    (2, MemoraIcons.square, 13.0, 'Large tiles'),
    (4, MemoraIcons.gridFour, 13.0, 'Small tiles'),
    (8, MemoraIcons.dotsNine, 14.0, 'Dense grid'),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: hitHeight,
      child: Center(
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (i, (n, icon, size, label)) in _options.indexed)
                _cell(c, n, icon, size, label, first: i == 0),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cell(
    MemoraColors c,
    int n,
    IconData icon,
    double size,
    String label, {
    required bool first,
  }) {
    final selected = columns == n;
    return TapArea(
      onTap: () => onChanged(n),
      semanticLabel: '$label, $n columns',
      selected: selected,
      minSize: 0,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? c.accentTint : c.accentTint.withValues(alpha: 0),
          border: first ? null : Border(left: BorderSide(color: c.line)),
        ),
        child: Icon(icon, size: size, color: selected ? c.accentInk : c.dim),
      ),
    );
  }
}
