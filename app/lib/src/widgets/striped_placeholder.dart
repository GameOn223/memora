import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/memora_colors.dart';

/// Diagonal stripes shown where an image hasn't loaded, matching
/// `repeating-linear-gradient(126deg, a 0 6px, b 6px 12px)`.
class StripedPlaceholder extends StatelessWidget {
  const StripedPlaceholder({super.key, this.stripe = 6, this.child});

  /// Width of one band. The pattern repeats every two bands.
  final double stripe;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CustomPaint(
      painter: StripePainter(a: c.stripeA, b: c.stripeB, stripe: stripe),
      child: child ?? const SizedBox.expand(),
    );
  }
}

class StripePainter extends CustomPainter {
  const StripePainter({required this.a, required this.b, required this.stripe});

  final Color a;
  final Color b;
  final double stripe;

  // CSS gradient angle: 0deg points up, 90deg points right.
  static const _cssAngle = 126 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = Offset.zero & size;
    canvas
      ..save()
      ..clipRect(rect)
      ..drawRect(rect, Paint()..color = b);

    final dx = math.sin(_cssAngle);
    final dy = -math.cos(_cssAngle);
    // Length of the gradient line through the center, as CSS defines it.
    final length = size.width * dx.abs() + size.height * dy.abs();
    final diagonal = math.sqrt(
      size.width * size.width + size.height * size.height,
    );

    canvas
      ..translate(size.width / 2, size.height / 2)
      ..rotate(math.atan2(dy, dx));
    final paint = Paint()..color = a;
    final period = stripe * 2;
    for (var x = -length / 2; x < length / 2; x += period) {
      canvas.drawRect(Rect.fromLTWH(x, -diagonal / 2, stripe, diagonal), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(StripePainter oldDelegate) =>
      oldDelegate.a != a || oldDelegate.b != b || oldDelegate.stripe != stripe;
}
