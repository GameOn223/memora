import 'package:flutter/widgets.dart';

import '../features/queue/block_notice.dart';
import '../services/app_services.dart';
import '../theme/memora_colors.dart';
import '../theme/memora_icons.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';
import 'caps_label.dart';
import 'motion.dart';
import 'tap_area.dart';

/// Confirmation after images are added: they're filed, queued, and will be
/// understood later. When [notice] is set, nothing can be understood yet and
/// the toast says why instead.
class AddedToast extends StatefulWidget {
  const AddedToast({
    super.key,
    required this.result,
    required this.overnight,
    required this.windowStart,
    required this.onQueue,
    this.notice,
  });

  final AddImagesResult result;
  final bool overnight;

  /// Start of the overnight window, such as `01:00`.
  final String windowStart;

  /// Opens the queue, or the notice's settings screen when there is one.
  final VoidCallback onQueue;

  /// Why nothing will be understood yet, when something is in the way.
  final BlockNotice? notice;

  static String titleFor(AddImagesResult result) =>
      result.added == 1 ? '1 image added' : '${result.added} images added';

  static String copyFor(
    AddImagesResult result, {
    required bool overnight,
    required String windowStart,
    BlockNotice? notice,
  }) {
    final base =
        notice?.sentence ??
        (overnight
            ? 'Filed by the date each image was taken. Processing starts at '
                  '$windowStart while charging.'
            : 'Filed by the date each image was taken. Processing one at a '
                  'time now.');
    final notes = [
      if (result.duplicates > 0)
        '${result.duplicates} ${result.duplicates == 1 ? 'was' : 'were'} '
            'already in Memora.',
      if (result.failed > 0) '${result.failed} could not be copied.',
    ];
    return [base, ...notes].join(' ');
  }

  @override
  State<AddedToast> createState() => _AddedToastState();
}

class _AddedToastState extends State<AddedToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _rise = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );

  @override
  void initState() {
    super.initState();
    _rise.forward();
  }

  @override
  void dispose() {
    _rise.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final curved = CurvedAnimation(parent: _rise, curve: Curves.easeOut);
    final notice = widget.notice;
    const steps = ['Added', '·', 'Queued', '·', 'Understood'];
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) => Opacity(
        opacity: curved.value,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - curved.value)),
          child: child,
        ),
      ),
      child: TapArea(
        onTap: widget.onQueue,
        button: false,
        minSize: 0,
        child: Semantics(
          liveRegion: true,
          container: true,
          child: Container(
            padding: const EdgeInsets.all(Space.s4),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: c.accentLine),
              boxShadow: Shadows.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Icon(
                      notice == null
                          ? MemoraIcons.checkCircle
                          : MemoraIcons.warningCircle,
                      size: 19,
                      color: c.accent,
                    ),
                    const SizedBox(width: Space.s4),
                    Expanded(
                      child: Text(
                        AddedToast.titleFor(widget.result),
                        style: MemoraText.style(
                          14,
                          medium: true,
                          color: c.text,
                        ),
                      ),
                    ),
                    Text(
                      notice?.action ?? 'Queue',
                      style: MemoraText.style(
                        12.5,
                        medium: true,
                        color: c.accentInk,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: Space.s4),
                Row(
                  children: [
                    for (final (i, label) in steps.indexed) ...[
                      if (i > 0) const SizedBox(width: 7),
                      CapsLabel(
                        label,
                        spacing: 1.2,
                        color: label == '·'
                            ? c.line
                            // Understanding is not coming while the queue
                            // is blocked, so only the done steps are inked.
                            : (i <= 2 ? c.accentInk : c.dim),
                      ),
                    ],
                  ],
                ),
                if (notice == null) ...[
                  const SizedBox(height: Space.s3),
                  const SweepBar(segment: 0.28),
                ],
                const SizedBox(height: Space.s3),
                Text(
                  AddedToast.copyFor(
                    widget.result,
                    overnight: widget.overnight,
                    windowStart: widget.windowStart,
                    notice: notice,
                  ),
                  style: MemoraText.style(12.5, height: 1.45, color: c.muted),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
