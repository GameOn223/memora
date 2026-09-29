import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../routing/router.dart';
import '../../theme/memora_colors.dart';
import '../../theme/memora_icons.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../../widgets/caps_label.dart';
import '../../widgets/fading_rule.dart';
import '../../widgets/outline_action.dart';
import 'home_header.dart';

/// First run: nothing has been added yet.
class EmptyState extends ConsumerWidget {
  const EmptyState({super.key});

  static const steps = [
    'Tap Add and select images from your gallery: one, or a few hundred.',
    'They are filed immediately under the date each image was taken.',
    'Memora understands them one at a time in the background, then you can '
        'ask questions.',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ColoredBox(
      color: c.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const HomeHeader(compact: true),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                Space.s6,
                44.8 - 28,
                Space.s6,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.accentTint,
                      borderRadius: BorderRadius.circular(Radii.md),
                      border: Border.all(color: c.accentLine),
                    ),
                    child: Icon(MemoraIcons.images, size: 22, color: c.accent),
                  ),
                  const SizedBox(height: Space.s6),
                  Text(
                    'No memories yet.',
                    style: MemoraText.style(
                      24,
                      medium: true,
                      spacing: -0.7,
                      height: 1.2,
                      color: c.text,
                    ),
                  ),
                  const SizedBox(height: Space.s4),
                  Text(
                    'Memora never watches your screen. A memory exists '
                    'because you chose it: picked from your gallery, shared '
                    'to Memora, or saved with the Memora tile.',
                    style: MemoraText.style(13.5, height: 1.6, color: c.muted),
                  ),
                  const SizedBox(height: Space.s8),
                  const FadingRule(),
                  const SizedBox(height: Space.s8),
                  const CapsLabel('How it works', spacing: 1.4),
                  const SizedBox(height: Space.s4),
                  for (final (i, step) in steps.indexed) ...[
                    if (i > 0) const SizedBox(height: Space.s4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: c.line),
                          ),
                          child: Text(
                            '${i + 1}',
                            style: MemoraText.style(
                              10,
                              medium: true,
                              color: c.muted,
                            ),
                          ),
                        ),
                        const SizedBox(width: Space.s4),
                        Expanded(
                          child: Text(
                            step,
                            style: MemoraText.style(
                              13,
                              height: 1.5,
                              color: c.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: Space.s8),
                  Container(
                    padding: const EdgeInsets.all(Space.s4),
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(Radii.md),
                      border: Border.all(color: c.line),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const CapsLabel('A backlog is fine'),
                        const SizedBox(height: Space.s3),
                        Text(
                          'Select two hundred images at once if you like. '
                          'Memora adds them all immediately and works '
                          'through the queue one at a time, overnight if you '
                          'ask it to.',
                          style: MemoraText.style(
                            12.5,
                            height: 1.55,
                            color: c.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Space.s6),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              Space.s6,
              0,
              Space.s6,
              Space.s6 + bottom,
            ),
            child: OutlineAction(
              label: 'Add images from gallery',
              icon: MemoraIcons.images,
              onPressed: () => context.go(Routes.add),
            ),
          ),
        ],
      ),
    );
  }
}
