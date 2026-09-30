import 'package:flutter/widgets.dart';

import '../theme/memora_colors.dart';
import '../theme/text_styles.dart';

/// Uppercase tracked metadata text, the design's small caps labels.
class CapsLabel extends StatelessWidget {
  const CapsLabel(
    this.text, {
    super.key,
    this.size = 9,
    this.spacing = 1.3,
    this.color,
    this.height,
    this.tabular = false,
    this.maxLines = 1,
    this.textAlign,
  });

  final String text;
  final double size;
  final double spacing;
  final Color? color;
  final double? height;
  final bool tabular;
  final int? maxLines;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
      textAlign: textAlign,
      style: MemoraText.caps(
        size,
        spacing: spacing,
        height: height,
        tabular: tabular,
        color: color ?? context.colors.dim,
      ),
    );
  }
}
