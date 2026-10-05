import 'package:flutter/widgets.dart';

import '../theme/memora_colors.dart';
import '../theme/memora_icons.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';

enum TagTone {
  /// Chip background, hairline, muted text. On-device things and categories.
  neutral,

  /// Accent tint, accent hairline, accent ink. Ready state and cloud providers.
  accent,

  /// No fill, dim text. Unavailable things.
  dim,
}

/// A 22px uppercase tag, such as a category, a status or a provider.
class Tag extends StatelessWidget {
  const Tag(
    this.label, {
    super.key,
    this.tone = TagTone.neutral,
    this.leadingDot = false,
  });

  final String label;
  final TagTone tone;

  /// A small filled circle before the label, as on "AI ready".
  final bool leadingDot;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final (Color bg, Color border, Color fg) = switch (tone) {
      TagTone.neutral => (c.chip, c.line, c.muted),
      TagTone.accent => (c.accentTint, c.accentLine, c.accentInk),
      TagTone.dim => (c.chip.withValues(alpha: 0), c.lineSoft, c.dim),
    };
    return Container(
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (leadingDot) ...[
            Icon(MemoraIconsFill.circle, size: 6, color: fg),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MemoraText.caps(9, spacing: 1.1, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// A 26px outlined keyword chip on the detail screen.
class KeywordChip extends StatelessWidget {
  const KeywordChip(this.keyword, {super.key});

  final String keyword;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: c.line),
      ),
      // widthFactor keeps the chip around its word. Centering without it
      // takes the whole line a Wrap offers, which puts one chip per row.
      child: Center(
        widthFactor: 1,
        child: Text(keyword, style: MemoraText.style(12, color: c.muted)),
      ),
    );
  }
}
