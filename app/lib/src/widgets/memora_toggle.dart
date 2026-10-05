import 'package:flutter/widgets.dart';

import '../theme/memora_colors.dart';
import 'tap_area.dart';

enum ToggleSize {
  /// 42 by 24 with an 18px knob.
  regular,

  /// 34 by 20 with a 14px knob.
  small,
}

/// The design's switch: an outlined track that fills with accent when on.
class MemoraToggle extends StatelessWidget {
  const MemoraToggle({
    super.key,
    required this.value,
    required this.onChanged,
    required this.semanticLabel,
    this.size = ToggleSize.regular,
    this.interactive = true,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String semanticLabel;
  final ToggleSize size;

  /// False when a surrounding card handles taps and semantics.
  final bool interactive;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (double width, double height, double knob) = switch (size) {
      ToggleSize.regular => (42, 24, 18),
      ToggleSize.small => (34, 20, 14),
    };
    final track = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      width: width,
      height: height,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(height / 2),
        color: value ? c.accent : c.accent.withValues(alpha: 0),
        border: Border.all(color: value ? c.accent : c.line),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: knob,
          height: knob,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: value ? c.bg : c.dim,
          ),
        ),
      ),
    );
    if (!interactive) return ExcludeSemantics(child: track);
    return TapArea(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      semanticLabel: semanticLabel,
      button: false,
      toggled: value,
      child: track,
    );
  }
}
