import 'package:flutter/widgets.dart';
import 'package:memora_core/memora_core.dart';

import '../theme/memora_colors.dart';
import '../theme/memora_icons.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';
import 'caps_label.dart';
import 'memory_image.dart';
import 'memory_labels.dart';
import 'status_dot.dart';
import 'tap_area.dart';

/// One memory in the grid. What it shows depends on density: title and
/// facts at 2 columns, a status dot at 4, the image alone at 8.
class MemoryTile extends StatelessWidget {
  const MemoryTile({
    super.key,
    required this.memory,
    required this.columns,
    required this.onTap,
    this.fact,
  });

  final Memory memory;
  final int columns;
  final VoidCallback? onTap;

  /// Key facts line for ready memories, such as `₹1,842 · due 30 Sep`.
  final String? fact;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final status = StatusStyle.of(memory.status, c);
    final title = memoryTitle(memory);
    final meta = memory.status == ProcessingStatus.ready && fact != null
        ? fact!
        : status.label;
    final radius = switch (columns) {
      2 => Radii.md,
      4 => Radii.sm,
      _ => 2.0,
    };
    final hasImage = memory.thumbnailPath != null;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (MediaQuery.sizeOf(context).width / columns * dpr)
        .round();

    return TapArea(
      onTap: onTap,
      semanticLabel: '$title, $meta',
      minSize: 0,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(radius)),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: status.border),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MemoryImageView(path: memory.thumbnailPath, cacheWidth: cacheWidth),
            if (columns == 2) ...[
              if (!hasImage && memory.category != null)
                Positioned(
                  top: 8,
                  left: 8,
                  right: 8,
                  child: CapsLabel(
                    humanizeKey(memory.category!),
                    size: 7.5,
                    spacing: 1.1,
                    color: c.dim,
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(9, Space.s8, 9, 9),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [c.scrim, c.scrim, c.scrim.withValues(alpha: 0)],
                      stops: const [0, 0.42, 1],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: MemoraText.style(
                          11.5,
                          medium: true,
                          height: 1.3,
                          color: c.text,
                        ),
                      ),
                      const SizedBox(height: Space.s2),
                      Row(
                        children: [
                          StatusDot(color: status.dot),
                          const SizedBox(width: Space.s2),
                          Expanded(
                            child: CapsLabel(
                              meta,
                              size: 8,
                              spacing: 0.9,
                              color: c.muted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (columns == 4)
              Positioned(
                bottom: 4,
                left: 4,
                child: StatusDot(key: tileDotKey, color: status.dot, size: 5),
              ),
            if (memory.addedLater)
              Positioned(
                top: 4,
                right: 4,
                child: Icon(
                  MemoraIcons.clockCounterClockwise,
                  key: addedLaterKey,
                  size: columns == 2 ? 11 : 9,
                  color: c.muted,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Found by tests: the status dot shown at 4 columns.
  static const tileDotKey = ValueKey('memory-tile-dot');

  /// Found by tests: the "added later" history glyph.
  static const addedLaterKey = ValueKey('memory-tile-added-later');
}
