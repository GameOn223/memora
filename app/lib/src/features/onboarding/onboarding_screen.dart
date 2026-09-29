import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:memora_core/memora_core.dart';

import '../../routing/router.dart';
import '../../state/services.dart';
import '../../state/settings.dart';
import '../../theme/memora_colors.dart';
import '../../theme/memora_icons.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../../widgets/caps_label.dart';
import '../../widgets/fading_rule.dart';
import '../../widgets/outline_action.dart';
import '../../widgets/tap_area.dart';

/// What Memora does with your data, shown before the first image is added.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  static const rows = [
    (
      MemoraIcons.images,
      'You choose what is remembered',
      'Pick images from your gallery, share them to Memora, or tap the '
          'Memora tile. Memora never watches your screen and never imports '
          'your library on its own.',
    ),
    (
      MemoraIcons.stack,
      'A queue, not a wait',
      'Added images are browsable at once. Understanding happens one image '
          'at a time in the background, overnight if you prefer.',
    ),
    (
      MemoraIcons.key,
      'Your keys, your provider',
      'Bring your own API key, or run local models. You can change provider '
          'later without losing memories.',
    ),
  ];

  Future<void> _complete(WidgetRef ref) async {
    await ref.read(appServicesProvider).preferences.setOnboardingComplete();
    ref.invalidate(onboardingCompleteProvider);
  }

  Future<void> _startLocalOnly(BuildContext context, WidgetRef ref) async {
    await ref
        .read(aiSettingsProvider.notifier)
        .save(
          const AiSettings(
            localOnly: true,
            selections: {
              Capability.vision: CapabilitySelection('local', 'ocr-rules'),
              Capability.embeddings: CapabilitySelection(
                'local',
                'bge-small-en-v1.5',
              ),
              Capability.reranking: CapabilitySelection(
                'local',
                'score-fusion',
              ),
            },
          ),
        );
    await _complete(ref);
    if (context.mounted) context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final padding = MediaQuery.paddingOf(context);
    return ColoredBox(
      color: c.bg,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Space.s6,
          Space.s8 + padding.top,
          Space.s6,
          Space.s6 + padding.bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                for (var i = 0; i < 3; i++) ...[
                  if (i > 0) const SizedBox(width: Space.s3),
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == 0 ? c.accent : null,
                      border: i == 0 ? null : Border.all(color: c.line),
                    ),
                  ),
                ],
                const Spacer(),
                TapArea(
                  onTap: () async {
                    await _complete(ref);
                    if (context.mounted) context.go(Routes.home);
                  },
                  semanticLabel: 'Skip',
                  minSize: 0,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Space.s2,
                      vertical: Space.s3,
                    ),
                    child: Text(
                      'Skip',
                      style: MemoraText.style(12, medium: true, color: c.muted),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(top: 33.6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CapsLabel(
                      'Before you start',
                      spacing: 1.4,
                      color: c.accentInk,
                    ),
                    const SizedBox(height: Space.s4),
                    Text(
                      'Your memories stay on your device.',
                      style: MemoraText.style(
                        29,
                        medium: true,
                        spacing: -0.9,
                        height: 1.16,
                        color: c.text,
                      ),
                    ),
                    const SizedBox(height: Space.s4),
                    Text(
                      'Images, the database, embeddings and every '
                      'conversation are written to local storage. Memora has '
                      'no account and no server of its own.',
                      style: MemoraText.style(
                        13.5,
                        height: 1.6,
                        color: c.muted,
                      ),
                    ),
                    const SizedBox(height: Space.s8),
                    const FadingRule(),
                    const SizedBox(height: Space.s8),
                    for (final (icon, title, body) in rows) ...[
                      _Row(icon: icon, title: title, body: body),
                      if (title != rows.last.$2)
                        const SizedBox(height: Space.s4),
                    ],
                    const SizedBox(height: Space.s8),
                    const _CloudNote(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Space.s6),
            OutlineAction(
              label: 'Start in local-only mode',
              icon: MemoraIcons.shieldCheck,
              onPressed: () => _startLocalOnly(context, ref),
            ),
            const SizedBox(height: Space.s2),
            OutlineAction(
              label: 'Choose AI providers instead',
              tone: ActionTone.ghost,
              onPressed: () async {
                await _complete(ref);
                if (context.mounted) context.go(Routes.settings);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 18, color: c.accent),
        ),
        const SizedBox(width: Space.s4),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: MemoraText.style(13.5, medium: true, color: c.text),
              ),
              const SizedBox(height: Space.s1),
              Text(
                body,
                style: MemoraText.style(12.5, height: 1.55, color: c.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CloudNote extends StatelessWidget {
  const _CloudNote();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    const flow = [
      'Image',
      '→',
      'Prompt',
      '→',
      'Provider',
      '→',
      'Back to device',
    ];
    return Container(
      padding: const EdgeInsets.all(Space.s4),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: c.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CapsLabel('If you turn on a cloud provider'),
          const SizedBox(height: Space.s3),
          Wrap(
            spacing: 7,
            runSpacing: Space.s2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final label in flow)
                CapsLabel(
                  label,
                  size: 10,
                  spacing: 1,
                  color: switch (label) {
                    '→' => c.line,
                    'Provider' => c.accentInk,
                    _ => c.text,
                  },
                ),
            ],
          ),
          const SizedBox(height: Space.s3),
          Text(
            'Each queued image and its extracted context leave the device for '
            'that one request. Nothing is stored by Memora off-device.',
            style: MemoraText.style(12, height: 1.55, color: c.muted),
          ),
        ],
      ),
    );
  }
}
