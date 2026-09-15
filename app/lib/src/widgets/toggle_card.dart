import 'package:flutter/widgets.dart';

import '../theme/memora_colors.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';
import 'memora_toggle.dart';
import 'tap_area.dart';

/// A tappable card or row holding a setting and its switch. The whole area
/// toggles, and screen readers hear one switch with the title as its label.
class ToggleCard extends StatelessWidget {
  const ToggleCard({
    super.key,
    required this.value,
    required this.onChanged,
    required this.body,
    this.title,
    this.icon,
    this.iconSize = 18,
    this.iconColor,
    this.titleSize = 14,
    this.bodySize = 12,
    this.bodyHeight = 1.5,
    this.bodyColor,
    this.bodyGap = Space.s1,
    this.padding = const EdgeInsets.all(Space.s4),
    this.gap = Space.s4,
    this.toggleSize = ToggleSize.regular,
    this.offColor,
    this.card = true,
    this.alignTop = false,
  });

  /// Compact card above the add button on the Add screen.
  const ToggleCard.compact({
    super.key,
    required this.value,
    required this.onChanged,
    required this.body,
    this.icon,
  }) : title = null,
       iconSize = 16,
       iconColor = null,
       titleSize = 14,
       bodySize = 12,
       bodyHeight = 1.45,
       bodyColor = null,
       bodyGap = 0,
       padding = const EdgeInsets.symmetric(
         vertical: Space.s3,
         horizontal: Space.s4,
       ),
       gap = Space.s3,
       toggleSize = ToggleSize.small,
       offColor = null,
       card = true,
       alignTop = false;

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String body;
  final String? title;
  final IconData? icon;
  final double iconSize;

  /// Defaults to accent.
  final Color? iconColor;
  final double titleSize;
  final double bodySize;
  final double bodyHeight;

  /// Defaults to muted.
  final Color? bodyColor;
  final double bodyGap;
  final EdgeInsets padding;
  final double gap;
  final ToggleSize toggleSize;

  /// Card color when off. Defaults to surface-2.
  final Color? offColor;

  /// Draw the tinted card. False for rows inside a bordered list.
  final bool card;
  final bool alignTop;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = title ?? body;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (title != null)
          Text(
            title!,
            style: MemoraText.style(titleSize, medium: true, color: c.text),
          ),
        Padding(
          padding: EdgeInsets.only(top: title == null ? 0 : bodyGap),
          child: Text(
            body,
            style: MemoraText.style(
              bodySize,
              height: bodyHeight,
              color: bodyColor ?? c.muted,
            ),
          ),
        ),
      ],
    );
    final row = Row(
      crossAxisAlignment: alignTop
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Icon(icon, size: iconSize, color: iconColor ?? c.accent),
          SizedBox(width: gap),
        ],
        Expanded(child: text),
        SizedBox(width: gap),
        MemoraToggle(
          value: value,
          onChanged: onChanged,
          semanticLabel: label,
          size: toggleSize,
          interactive: false,
        ),
      ],
    );
    return TapArea(
      onTap: onChanged == null ? null : () => onChanged!(!value),
      semanticLabel: label,
      button: false,
      toggled: value,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: padding,
        decoration: card
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.md),
                color: value ? c.accentTint : (offColor ?? c.surface2),
                border: Border.all(color: value ? c.accentLine : c.line),
              )
            : null,
        child: row,
      ),
    );
  }
}
