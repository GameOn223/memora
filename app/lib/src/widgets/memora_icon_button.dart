import 'package:flutter/widgets.dart';

import '../theme/memora_colors.dart';
import 'tap_area.dart';

/// A bare icon in a small square, with a 48px touch target around it.
class MemoraIconButton extends StatelessWidget {
  const MemoraIconButton({
    super.key,
    required this.icon,
    required this.semanticLabel,
    required this.onPressed,
    this.box = 32,
    this.iconSize = 19,
    this.color,
    this.badge,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onPressed;

  /// Visual square the icon is centered in.
  final double box;
  final double iconSize;
  final Color? color;

  /// Optional overlay in the top right corner, such as a count.
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    return TapArea(
      onTap: onPressed,
      semanticLabel: semanticLabel,
      child: SizedBox(
        width: box,
        height: box,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Center(
              child: Icon(
                icon,
                size: iconSize,
                color: color ?? context.colors.muted,
              ),
            ),
            if (badge != null) Positioned(top: 3, right: 2, child: badge!),
          ],
        ),
      ),
    );
  }
}
