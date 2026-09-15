import 'package:flutter/widgets.dart';
import 'package:memora_core/memora_core.dart';

import '../theme/memora_colors.dart';

/// A small round mark. Processing state is shown by tone, not hue.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 4});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

/// How a processing status looks: its label, dot tone and tile edge.
class StatusStyle {
  const StatusStyle({
    required this.label,
    required this.dot,
    required this.border,
  });

  factory StatusStyle.of(ProcessingStatus status, MemoraColors c) {
    return switch (status) {
      ProcessingStatus.ready => StatusStyle(
        label: 'AI ready',
        dot: c.accent,
        border: c.lineSoft,
      ),
      ProcessingStatus.processing => StatusStyle(
        label: 'Understanding',
        dot: c.muted,
        border: c.line,
      ),
      ProcessingStatus.captured ||
      ProcessingStatus.reprocessing ||
      ProcessingStatus.deleted => StatusStyle(
        label: 'In queue',
        dot: c.dim,
        border: c.lineSoft,
      ),
      ProcessingStatus.failed => StatusStyle(
        label: 'Could not process',
        dot: c.dim,
        border: c.accentLine,
      ),
    };
  }

  final String label;
  final Color dot;
  final Color border;
}
