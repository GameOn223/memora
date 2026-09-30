import 'package:flutter/widgets.dart';

import '../theme/memora_colors.dart';

/// A 1px horizontal rule that fades in over [fade] pixels at both ends.
class FadingRule extends StatelessWidget {
  const FadingRule({super.key, this.color, this.fade = 48});

  final Color? color;
  final double fade;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      width: double.infinity,
      child: CustomPaint(
        painter: FadingRulePainter(
          color: color ?? context.colors.line,
          fade: fade,
        ),
      ),
    );
  }
}

class FadingRulePainter extends CustomPainter {
  const FadingRulePainter({required this.color, required this.fade});

  final Color color;
  final double fade;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    final edge = size.width <= fade * 2 ? 0.5 : fade / size.width;
    final transparent = color.withValues(alpha: 0);
    final paint = Paint()
      ..shader = LinearGradient(
        colors: [transparent, color, color, transparent],
        stops: [0, edge, 1 - edge, 1],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
  }

  @override
  bool shouldRepaint(FadingRulePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.fade != fade;
}
