import 'package:flutter/widgets.dart';

import '../theme/memora_colors.dart';
import '../theme/tokens.dart';

/// A rounded, outlined group of rows separated by soft hairlines.
class BorderedList extends StatelessWidget {
  const BorderedList({super.key, required this.children, this.header});

  final List<Widget> children;

  /// Optional header row on surface-2 above the first row.
  final Widget? header;

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
        mainAxisSize: MainAxisSize.min,
        children: [
          if (header != null)
            DecoratedBox(
              decoration: BoxDecoration(
                color: c.surface2,
                border: Border(bottom: BorderSide(color: c.line)),
              ),
              child: header,
            ),
          for (final (i, child) in children.indexed)
            DecoratedBox(
              decoration: BoxDecoration(
                border: i == children.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: c.lineSoft)),
              ),
              child: child,
            ),
        ],
      ),
    );
  }
}
