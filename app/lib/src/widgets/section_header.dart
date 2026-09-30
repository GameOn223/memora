import 'package:flutter/widgets.dart';

import '../theme/memora_colors.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';

/// Date group header: a caps label, a hairline, and a count.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.label,
    required this.count,
    this.background,
    this.verticalPadding = Space.s2,
  });

  final String label;
  final String count;

  /// Fill behind the header so it can stick over scrolling content.
  final Color? background;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      color: background,
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: Row(
        // The design aligns on the text baseline, so the hairline sits there.
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: MemoraText.caps(11, spacing: 1.2, color: c.text),
            ),
          ),
          const SizedBox(width: Space.s3),
          Expanded(
            child: Container(
              height: 1,
              margin: const EdgeInsets.only(bottom: 3),
              color: c.lineSoft,
            ),
          ),
          const SizedBox(width: Space.s3),
          Text(
            count,
            style: MemoraText.caps(
              9.5,
              spacing: 0.8,
              tabular: true,
              color: c.dim,
            ),
          ),
        ],
      ),
    );
  }
}
