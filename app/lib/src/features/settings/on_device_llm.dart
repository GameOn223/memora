import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:memora_providers/memora_providers.dart';

import '../../state/local_llm.dart';
import '../../state/services.dart';
import '../../theme/memora_colors.dart';
import '../../theme/memora_icons.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../../widgets/bordered_list.dart';
import '../../widgets/memory_labels.dart';
import '../../widgets/tags.dart';
import 'settings_rows.dart';

/// Generative models the user can bring to this phone.
///
/// The section is only here when the build has a runtime to load a model
/// into. Each row is honest about the phone it is running on: a model that
/// needs more memory than the device has says so instead of offering a
/// download of several gigabytes that would fail at the end.
class OnDeviceLlmSection extends ConsumerWidget {
  const OnDeviceLlmSection({super.key});

  /// What choosing an on-device model means, in plain words.
  static const tradeoff =
      'A model here keeps every question on the phone. It answers more '
      'slowly than a cloud model and it uses battery while it works.';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(appServicesProvider).localLlm.supported) {
      return const SizedBox.shrink();
    }
    final view = ref.watch(localLlmProvider).value;
    if (view == null || view.models.isEmpty) return const SizedBox.shrink();
    final controller = ref.read(localLlmProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Space.s8),
        SettingsSection(
          label: 'Chat and vision on this device',
          footnote: view.problem ?? _footnote(view),
          footnoteIsError: view.problem != null,
          child: BorderedList(
            children: [
              for (final model in view.models)
                _LlmRow(
                  model: model,
                  busy: view.importing == model.spec.id,
                  progress: view.importing == model.spec.id
                      ? view.progress
                      : null,
                  enabled: !view.busy,
                  onImport: () => unawaited(controller.import(model.spec.id)),
                  onRemove: () => unawaited(controller.remove(model.spec.id)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _footnote(LocalLlmView view) {
    final source = view.models.first.spec;
    return '$tradeoff Download the ${source.fileExtensions.first} file from '
        '${source.sourceName} after accepting the ${source.licence}, then '
        'import it here. Memora cannot fetch these files for you.';
  }
}

class _LlmRow extends StatelessWidget {
  const _LlmRow({
    required this.model,
    required this.busy,
    required this.progress,
    required this.enabled,
    required this.onImport,
    required this.onRemove,
  });

  final LocalLlmStatus model;
  final bool busy;
  final double? progress;
  final bool enabled;
  final VoidCallback onImport;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final spec = model.spec;
    final size = byteSize(model.installed?.sizeBytes ?? spec.approximateBytes);
    final (String state, Widget trailing, VoidCallback? onTap) = busy
        ? ('Importing', const Tag('Working', tone: TagTone.dim), null)
        : model.isInstalled
        ? ('installed', const Tag('Remove'), enabled ? onRemove : null)
        : model.canImport
        ? (
            fitLabel(model.fit),
            const Tag('Import a model file', tone: TagTone.accent),
            enabled ? onImport : null,
          )
        : (
            fitLabel(model.fit),
            const Tag('Will not run here', tone: TagTone.dim),
            null,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsRow(
          icon: spec.vision ? MemoraIcons.eye : MemoraIcons.chatTeardropText,
          title: spec.displayName,
          subtitle: '$size · $state',
          trailing: trailing,
          onTap: onTap,
          semanticLabel: '${spec.displayName}, $size, $state',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s3),
          child: Text(
            model.fit == LocalLlmFit.tooSmall
                ? '${spec.adds} It needs about '
                      '${byteSize(spec.requiredMemoryBytes)} of memory, and '
                      'this phone does not have it.'
                : spec.adds,
            style: MemoraText.style(11.5, height: 1.5, color: c.dim),
          ),
        ),
        if (busy)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s3),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 2,
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: c.lineSoft,
                  valueColor: AlwaysStoppedAnimation(c.accent),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// What the device can do with this model, for the row's small line.
  static String fitLabel(LocalLlmFit fit) => switch (fit) {
    LocalLlmFit.fits => 'this phone can run it',
    LocalLlmFit.tight => 'little memory free right now',
    LocalLlmFit.tooSmall => 'not enough memory on this phone',
    LocalLlmFit.unknown => 'not checked yet',
  };
}
