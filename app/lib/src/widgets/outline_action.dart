import 'package:flutter/widgets.dart';

import '../theme/memora_colors.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';
import 'tap_area.dart';

enum ActionTone {
  /// Accent outline with accent ink. Primary actions.
  accent,

  /// Neutral outline with muted text. Secondary actions.
  neutral,

  /// No outline, muted text.
  ghost,

  /// Neutral outline, dimmed, for an action that isn't possible yet.
  disabled,
}

/// Memora's button: an outline, never a filled flood of accent.
class OutlineAction extends StatelessWidget {
  const OutlineAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.tone = ActionTone.accent,
    this.height = 44,
    this.fontSize = 14,
    this.iconSize = 16,
    this.iconGap = 7,
    this.horizontalPadding = Space.s6,
    this.expand = true,
    this.semanticLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final ActionTone tone;
  final double height;
  final double fontSize;
  final double iconSize;
  final double iconGap;
  final double horizontalPadding;

  /// Fill the available width and center the content.
  final bool expand;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final effective = onPressed == null ? ActionTone.disabled : tone;
    final (Color? border, Color fg) = switch (effective) {
      ActionTone.accent => (c.accent, c.accentInk),
      ActionTone.neutral => (c.line, c.muted),
      ActionTone.ghost => (null, c.muted),
      ActionTone.disabled => (c.line, c.dim),
    };
    final content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: iconSize, color: fg),
          SizedBox(width: iconGap),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: MemoraText.style(fontSize, medium: true, color: fg),
          ),
        ),
      ],
    );
    return TapArea(
      onTap: onPressed,
      semanticLabel: semanticLabel ?? label,
      child: Container(
        height: height,
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.md),
          border: border == null ? null : Border.all(color: border),
        ),
        child: content,
      ),
    );
  }
}
