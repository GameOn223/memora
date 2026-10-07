import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:memora_providers/memora_providers.dart';

import '../state/local_llm.dart';
import '../theme/memora_colors.dart';
import '../theme/text_styles.dart';
import '../theme/tokens.dart';
import 'caps_label.dart';

/// Shown while a model on this phone is being read into memory.
///
/// Half a gigabyte of weights takes seconds to load and the first question of
/// a session pays for it. Without this the app just sits there, which is what
/// a broken model looks like too.
///
/// The bar has no end on purpose. MediaPipe loads a model in one call and
/// says nothing while it works, so a percentage here would be made up. What
/// is honest is that it is working and on which model.
class LlmLoadingBar extends ConsumerWidget {
  const LlmLoadingBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loading = ref.watch(llmLoadingProvider).value;
    if (loading == null) return const SizedBox.shrink();
    final c = context.colors;
    final spec = localLlmSpecForPath(loading.relativePath);
    final name = spec?.displayName ?? 'the model';

    return Semantics(
      liveRegion: true,
      label: 'Loading $name onto this phone',
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s6,
          vertical: Space.s3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CapsLabel('LOADING $name'.toUpperCase(), color: c.muted),
            const SizedBox(height: Space.s2),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 2,
                child: LinearProgressIndicator(
                  backgroundColor: c.lineSoft,
                  valueColor: AlwaysStoppedAnimation(c.accent),
                ),
              ),
            ),
            const SizedBox(height: Space.s2),
            Text(
              'Reading the weights into memory. The first question of a '
              'session waits for this.',
              style: MemoraText.style(11.5, height: 1.5, color: c.dim),
            ),
          ],
        ),
      ),
    );
  }
}
