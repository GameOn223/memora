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
import '../../widgets/caps_label.dart';
import '../../widgets/memory_labels.dart';
import '../../widgets/outline_action.dart';
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
                  hasToken: view.hasToken,
                  onDownload: () =>
                      unawaited(controller.download(model.spec.id)),
                  onImport: () => unawaited(controller.import(model.spec.id)),
                  onRemove: () => unawaited(controller.remove(model.spec.id)),
                ),
              if (view.models.any((model) => model.canImport))
                _TokenRow(
                  hasToken: view.hasToken,
                  enabled: !view.busy,
                  onSave: controller.saveToken,
                ),
            ],
          ),
        ),
      ],
    );
  }

  static String _footnote(LocalLlmView view) {
    final source = view.models.first.spec;
    if (!view.hasToken) {
      return '$tradeoff The weights sit behind the ${source.licence}, which '
          'you accept once on ${source.sourceName}. Paste a read token below '
          'and Memora fetches the file itself.';
    }
    return '$tradeoff Memora downloads the file from ${source.sourceName} '
        'with your token. Already have the file on the phone? Import it '
        'instead.';
  }
}

class _LlmRow extends StatelessWidget {
  const _LlmRow({
    required this.model,
    required this.busy,
    required this.progress,
    required this.enabled,
    required this.hasToken,
    required this.onDownload,
    required this.onImport,
    required this.onRemove,
  });

  final LocalLlmStatus model;
  final bool busy;
  final double? progress;
  final bool enabled;

  /// Whether an access token is saved, which is what makes Download real.
  final bool hasToken;
  final VoidCallback onDownload;
  final VoidCallback onImport;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final spec = model.spec;
    final size = byteSize(model.installed?.sizeBytes ?? spec.approximateBytes);
    final (String state, Widget trailing, VoidCallback? onTap) = busy
        ? ('Fetching', const Tag('Working', tone: TagTone.dim), null)
        : model.isInstalled
        ? ('installed', const Tag('Remove'), enabled ? onRemove : null)
        : model.canImport
        ? hasToken
              ? (
                  fitLabel(model.fit),
                  const Tag('Download', tone: TagTone.accent),
                  enabled ? onDownload : null,
                )
              : (
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
        // With a token the row downloads, so importing moves out of the way
        // without going away. Someone who already pulled the file over adb
        // should not have to fetch three gigabytes again.
        if (hasToken && model.canImport && !busy)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s3),
            child: GestureDetector(
              onTap: enabled ? onImport : null,
              child: Text(
                'Already downloaded it? Import the file instead.',
                style: MemoraText.style(
                  11.5,
                  height: 1.5,
                  color: c.accent,
                ).copyWith(decoration: TextDecoration.underline),
                semanticsLabel:
                    'Import a model file for ${spec.displayName} instead',
              ),
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

/// Where the Hugging Face read token is pasted.
///
/// The token is the whole reason a download is possible: these repositories
/// refuse an unauthenticated request for the weights. It is kept with the
/// provider API keys, under the same Keystore key, and never reaches the
/// database or an export.
class _TokenRow extends StatefulWidget {
  const _TokenRow({
    required this.hasToken,
    required this.enabled,
    required this.onSave,
  });

  final bool hasToken;
  final bool enabled;

  /// Saves the token, or clears the saved one when given an empty string.
  final Future<void> Function(String token) onSave;

  @override
  State<_TokenRow> createState() => _TokenRowState();
}

class _TokenRowState extends State<_TokenRow> {
  final _token = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _save(String token) async {
    setState(() => _saving = true);
    await widget.onSave(token);
    if (!mounted) return;
    _token.clear();
    setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (widget.hasToken) {
      return SettingsRow(
        icon: MemoraIcons.key,
        title: 'Hugging Face token',
        subtitle: 'saved',
        trailing: const Tag('Remove', tone: TagTone.dim),
        onTap: widget.enabled && !_saving ? () => unawaited(_save('')) : null,
        semanticLabel: 'Hugging Face token, saved',
      );
    }
    return Padding(
      padding: const EdgeInsets.all(Space.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CapsLabel('HUGGING FACE TOKEN', color: c.dim),
          const SizedBox(height: Space.s3),
          TextField(
            controller: _token,
            autocorrect: false,
            obscureText: true,
            style: MemoraText.style(13.5, color: c.text),
            decoration: const InputDecoration(hintText: 'hf_…'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.s3),
          Text(
            'A read token from huggingface.co/settings/tokens, needed once. '
            'Accept the model licence on its own page with the same account, '
            'or the download comes back refused.',
            style: MemoraText.style(11.5, height: 1.5, color: c.dim),
          ),
          const SizedBox(height: Space.s3),
          OutlineAction(
            label: _saving ? 'Saving…' : 'Save token',
            icon: MemoraIcons.checkCircle,
            onPressed: _token.text.trim().isEmpty || _saving || !widget.enabled
                ? null
                : () => unawaited(_save(_token.text)),
          ),
        ],
      ),
    );
  }
}
