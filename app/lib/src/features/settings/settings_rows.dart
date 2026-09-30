import 'package:flutter/widgets.dart';

import '../../theme/memora_colors.dart';
import '../../theme/memora_icons.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../../widgets/caps_label.dart';
import '../../widgets/tap_area.dart';

/// A row inside a bordered settings group.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
    this.chevron = false,
    this.semanticLabel,
  });

  final String title;

  /// Small uppercase line under the title, such as a model id.
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final row = Padding(
      padding: const EdgeInsets.all(Space.s4),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 17, color: c.muted),
            const SizedBox(width: Space.s4),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: MemoraText.style(14, medium: true, color: c.text),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: Space.s1),
                  CapsLabel(
                    subtitle!,
                    size: 10,
                    spacing: 0.7,
                    height: 1.4,
                    maxLines: 2,
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: Space.s3),
            Flexible(child: trailing!),
          ],
          if (chevron) ...[
            const SizedBox(width: Space.s3),
            Icon(MemoraIcons.caretRight, size: 12, color: c.dim),
          ],
        ],
      ),
    );
    if (onTap == null) return row;
    return TapArea(
      onTap: onTap,
      semanticLabel:
          semanticLabel ?? '$title${subtitle == null ? '' : ', $subtitle'}',
      minSize: 0,
      child: row,
    );
  }
}

/// Caption above a settings group.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.label,
    required this.child,
    this.footnote,
  });

  final String label;
  final Widget child;
  final String? footnote;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CapsLabel(label),
        const SizedBox(height: Space.s3),
        child,
        if (footnote != null) ...[
          const SizedBox(height: Space.s3),
          Text(
            footnote!,
            style: MemoraText.style(12, height: 1.55, color: c.dim),
          ),
        ],
      ],
    );
  }
}
