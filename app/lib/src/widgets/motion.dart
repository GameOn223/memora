import 'package:flutter/widgets.dart';

import '../theme/memora_colors.dart';

/// A thin track with an accent segment sweeping across, for work in
/// progress with no known end. Holds still when animations are disabled.
class SweepBar extends StatefulWidget {
  const SweepBar({super.key, this.segment = 0.3, this.height = 2});

  /// Segment width as a fraction of the track.
  final double segment;
  final double height;

  @override
  State<SweepBar> createState() => _SweepBarState();
}

class _SweepBarState extends State<SweepBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = 0.35;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: Container(
        height: widget.height,
        color: c.lineSoft,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth * widget.segment;
            return AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final t = Curves.easeInOut.transform(_controller.value);
                // translateX from -100% to 420% of the segment width.
                final dx = width * (-1 + 5.2 * t);
                return Transform.translate(offset: Offset(dx, 0), child: child);
              },
              child: Align(
                alignment: Alignment.centerLeft,
                child: Container(width: width, color: c.accent),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A small accent dot that breathes while Memora is thinking.
class PulseDot extends StatefulWidget {
  const PulseDot({super.key, this.size = 5});

  final double size;

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller
        ..stop()
        ..value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        // 0.3 -> 1 -> 0.3 over one cycle.
        final t = Curves.easeInOut.transform(
          1 - (2 * _controller.value - 1).abs(),
        );
        return Opacity(
          opacity: 0.3 + 0.7 * t,
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
          ),
        );
      },
    );
  }
}
