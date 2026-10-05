import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:memora_core/memora_core.dart';

import '../../routing/router.dart';
import '../../services/app_services.dart';
import '../../state/data_version.dart';
import '../../state/memories.dart';
import '../../state/queue.dart';
import '../../state/services.dart';
import '../../state/settings.dart';
import '../../theme/memora_colors.dart';
import '../../theme/memora_icons.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../../widgets/bordered_list.dart';
import '../../widgets/bottom_tabs.dart';
import '../../widgets/caps_label.dart';
import '../../widgets/memory_labels.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/segmented.dart';
import '../../widgets/tags.dart';
import '../../widgets/tap_area.dart';
import '../../widgets/toggle_card.dart';
import 'settings_rows.dart';

/// AI and privacy: what runs where, which keys are stored, and what the
/// data on this phone adds up to.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  String? _busy;
  String? _flash;
  String? _modelError;
  Timer? _flashTimer;

  static const capabilityIcons = {
    Capability.vision: MemoraIcons.eye,
    Capability.chat: MemoraIcons.chatTeardropText,
    Capability.embeddings: MemoraIcons.graph,
    Capability.reranking: MemoraIcons.sortAscending,
  };

  void _setFlash(String message) {
    setState(() => _flash = message);
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _flash = null);
    });
  }

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }

  Future<void> _toggleLocalOnly({
    required bool value,
    required AiSettings settings,
    required Map<Capability, CapabilityStatus> statuses,
  }) async {
    final services = ref.read(appServicesProvider);
    if (value) {
      final affected = <String>[];
      for (final entry in settings.selections.entries) {
        final descriptor = services.providers.descriptor(
          entry.value.providerId,
        );
        if (descriptor == null ||
            descriptor.location == ProviderLocation.onDevice) {
          continue;
        }
        affected.add(
          '${sentenceCase(entry.key.key)} (${descriptor.displayName})',
        );
      }
      if (affected.isNotEmpty) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Turn on local-only mode?'),
            content: Text(
              '${joinNames(affected)} stop working until you pick a provider '
              'that runs on this device or on your own network. Nothing is '
              'deleted, and your selections are kept.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Turn on'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }
    }
    await ref.read(aiSettingsProvider.notifier).setLocalOnly(localOnly: value);
  }

  /// Runs one data action, clearing the busy flag even when the service
  /// throws, and saying what happened instead of going quiet.
  Future<void> _run(
    String name,
    Future<String> Function() action, {
    required String onFailure,
  }) async {
    if (_busy != null) return;
    setState(() => _busy = name);
    var message = onFailure;
    try {
      message = await action();
    } on Object {
      message = onFailure;
    } finally {
      if (mounted) setState(() => _busy = null);
    }
    if (mounted) _setFlash(message);
  }

  Future<void> _export() => _run('export', () async {
    final done = await ref
        .read(appServicesProvider)
        .export
        .exportAll(
          onProgress: (progress) {
            if (mounted && _busy != null) {
              setState(
                () => _busy = 'export ${progress.done}/${progress.total}',
              );
            }
          },
        );
    return done ? 'Export saved.' : 'Export cancelled.';
  }, onFailure: 'Export failed. Nothing was written.');

  Future<void> _reindex() => _run('reindex', () async {
    final count = await ref
        .read(appServicesProvider)
        .pipeline
        .reindexEmbeddings(budget: const Duration(minutes: 1));
    return 'Reindexed ${memoryCount(count)}.';
  }, onFailure: 'Reindexing failed. Nothing changed.');

  Future<void> _deleteAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => const _DeleteAllDialog(),
    );
    if (confirmed != true || !mounted) return;
    await _run('delete', () async {
      final services = ref.read(appServicesProvider);
      final files = await services.memories.deleteAll();
      await services.images.delete([for (final f in files) ...f.all]);
      await ref.read(dataVersionProvider.notifier).check();
      return 'Every memory was deleted.';
    }, onFailure: 'Some memories could not be deleted.');
  }

  Future<void> _capture(Future<Object?> Function() action) async {
    try {
      await action();
    } on Object {
      if (mounted) _setFlash('Android would not open that setting.');
    }
    if (mounted) ref.read(captureVersionProvider.notifier).bump();
  }

  Future<void> _model(String name, Future<void> Function() action) async {
    setState(() => _modelError = null);
    try {
      await action();
    } on Object {
      // Shown beside the model rather than in the flash at the bottom of
      // the screen, where it would be out of sight.
      if (mounted) {
        setState(() => _modelError = 'The $name download failed. Try again.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final services = ref.watch(appServicesProvider);
    final settings = ref.watch(aiSettingsProvider).value ?? const AiSettings();
    final statuses =
        ref.watch(capabilityStatusesProvider).value ??
        const <Capability, CapabilityStatus>{};
    final policy = ref.watch(queuePolicyProvider).value ?? const QueuePolicy();
    final waiting = ref.watch(queueWaitingCountProvider);
    final offDevice = ref.watch(offDeviceProvidersProvider).value ?? const [];
    final keys = ref.watch(apiKeysProvider).value ?? const [];
    final models = ref.watch(localModelsProvider).value ?? const [];
    final capture = ref.watch(captureSetupProvider).value;
    final stats = ref.watch(storageStatsProvider).value;
    final theme =
        ref.watch(themePreferenceProvider).value ?? ThemePreference.system;

    return ColoredBox(
      color: c.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(
            title: 'AI & privacy',
            onLeading: () => context.go(Routes.home),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                Space.s6,
                Space.s2,
                Space.s6,
                BottomTabs.coveredHeight + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                ToggleCard(
                  value: settings.localOnly,
                  title: 'Local-only mode',
                  titleSize: 15,
                  bodySize: 12.5,
                  bodyGap: 4,
                  alignTop: true,
                  offColor: c.surface,
                  body: settings.localOnly
                      ? 'On. Vision runs on this device. Chat needs a model '
                            'you run yourself, and anything the device '
                            'cannot do is shown as unavailable rather than '
                            'sent away.'
                      : 'Off. Cloud providers handle vision and chat. Turn '
                            'on to keep every image on device.',
                  onChanged: (value) => unawaited(
                    _toggleLocalOnly(
                      value: value,
                      settings: settings,
                      statuses: statuses,
                    ),
                  ),
                ),
                const SizedBox(height: Space.s8),
                SettingsSection(
                  label: 'Capabilities',
                  footnote:
                      'Each capability is selected independently. Switching '
                      'a provider never touches stored memories.',
                  child: BorderedList(
                    children: [
                      for (final capability in Capability.values)
                        _CapabilityRow(
                          capability: capability,
                          status: statuses[capability],
                          selection: settings.selections[capability],
                          icon: capabilityIcons[capability]!,
                          onTap: () =>
                              context.push(Routes.capability(capability)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.s8),
                SettingsSection(
                  label: 'Processing',
                  child: BorderedList(
                    children: [
                      ToggleCard(
                        value: policy.mode == QueueMode.overnight,
                        card: false,
                        icon: MemoraIcons.moonStars,
                        iconColor: c.muted,
                        iconSize: 17,
                        title: 'Process overnight',
                        body: policy.mode == QueueMode.overnight
                            ? 'Runs between 01:00 and 07:00 while charging '
                                  'and on Wi-Fi.'
                            : 'Runs as soon as each image is added.',
                        bodySize: 11.5,
                        bodyColor: c.dim,
                        onChanged: (value) => unawaited(
                          ref
                              .read(queuePolicyProvider.notifier)
                              .setMode(
                                value
                                    ? QueueMode.overnight
                                    : QueueMode.immediate,
                              ),
                        ),
                      ),
                      SettingsRow(
                        icon: MemoraIcons.stack,
                        title: 'Queue',
                        chevron: true,
                        trailing: CapsLabel(
                          '$waiting waiting',
                          size: 11,
                          spacing: 0.8,
                          color: c.accentInk,
                        ),
                        onTap: () => context.push(Routes.queue),
                      ),
                    ],
                  ),
                ),
                if (offDevice.isNotEmpty) ...[
                  const SizedBox(height: Space.s8),
                  Container(
                    padding: const EdgeInsets.all(Space.s4),
                    decoration: BoxDecoration(
                      color: c.accentTint,
                      borderRadius: BorderRadius.circular(Radii.md),
                      border: Border.all(color: c.accentLine),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          MemoraIcons.cloudArrowUp,
                          size: 17,
                          color: c.accent,
                        ),
                        const SizedBox(width: Space.s4),
                        Expanded(
                          child: Text(
                            'Images you add, their extracted context and '
                            'conversation history may be sent to '
                            '${joinNames([for (final p in offDevice) p.displayName])} '
                            'for processing.',
                            style: MemoraText.style(
                              12.5,
                              height: 1.55,
                              color: c.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: Space.s8),
                SettingsSection(
                  label: 'API keys · Android Keystore',
                  child: BorderedList(
                    children: [
                      for (final row in keys)
                        SettingsRow(
                          title: row.provider.displayName,
                          onTap: () =>
                              context.push(Routes.providerKey(row.provider.id)),
                          trailing: Text(
                            row.masked ?? 'Not configured',
                            textAlign: TextAlign.right,
                            style: MemoraText.style(
                              11,
                              spacing: 0.5,
                              color: c.dim,
                            ),
                          ),
                          icon: null,
                          semanticLabel:
                              '${row.provider.displayName} API key, '
                              '${row.masked == null ? 'not configured' : 'configured'}',
                        ),
                    ],
                  ),
                ),
                if (models.isNotEmpty) ...[
                  const SizedBox(height: Space.s8),
                  SettingsSection(
                    label: 'On-device models',
                    footnote: _modelError,
                    footnoteIsError: true,
                    child: BorderedList(
                      children: [
                        for (final model in models)
                          _ModelRow(
                            model: model,
                            onDownload: () => unawaited(
                              _model(
                                model.displayName,
                                () => services.localModels.download(model.id),
                              ),
                            ),
                            onRemove: () => unawaited(
                              _model(
                                model.displayName,
                                () => services.localModels.remove(model.id),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: Space.s8),
                SettingsSection(
                  label: 'Answers',
                  child: BorderedList(
                    children: [
                      ToggleCard(
                        value: settings.verifyAnswers,
                        card: false,
                        icon: MemoraIcons.shieldCheck,
                        iconColor: c.muted,
                        iconSize: 17,
                        title: 'Check answers against the image',
                        body:
                            'A single figure is confirmed with one extra '
                            'vision call before it is shown.',
                        bodySize: 11.5,
                        bodyColor: c.dim,
                        onChanged: (value) => unawaited(
                          ref
                              .read(aiSettingsProvider.notifier)
                              .setVerifyAnswers(verify: value),
                        ),
                      ),
                    ],
                  ),
                ),
                if (capture != null) ...[
                  const SizedBox(height: Space.s8),
                  SettingsSection(
                    label: 'Saving from other apps',
                    footnote:
                        'The tile saves what is on screen when you tap it. '
                        'Memora never watches your screen on its own.',
                    child: BorderedList(
                      children: [
                        SettingsRow(
                          icon: MemoraIcons.deviceMobile,
                          title: 'Quick Settings tile',
                          subtitle: 'Save without opening Memora',
                          trailing: capture.canRequestTile
                              ? const Tag('Add tile', tone: TagTone.accent)
                              : const Tag('Added'),
                          onTap: capture.canRequestTile
                              ? () => unawaited(
                                  _capture(services.capture.requestAddTile),
                                )
                              : null,
                        ),
                        SettingsRow(
                          icon: MemoraIcons.handTap,
                          title: 'Accessibility capture',
                          subtitle: capture.accessibilitySupported
                              ? 'No consent dialog for each capture'
                              : 'Needs Android 11 or newer',
                          trailing: Tag(
                            capture.accessibilityEnabled ? 'On' : 'Off',
                            tone: capture.accessibilityEnabled
                                ? TagTone.accent
                                : TagTone.dim,
                          ),
                          onTap: capture.accessibilitySupported
                              ? () => unawaited(
                                  _capture(
                                    services.capture.openAccessibilitySettings,
                                  ),
                                )
                              : null,
                        ),
                        SettingsRow(
                          icon: MemoraIcons.bell,
                          title: 'Notifications',
                          subtitle: 'Confirms each capture',
                          trailing: Tag(
                            capture.notificationsAllowed ? 'Allowed' : 'Allow',
                            tone: capture.notificationsAllowed
                                ? TagTone.accent
                                : TagTone.dim,
                          ),
                          onTap: capture.notificationsAllowed
                              ? null
                              : () => unawaited(
                                  _capture(
                                    services
                                        .capture
                                        .requestNotificationPermission,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: Space.s8),
                SettingsSection(
                  label: 'Appearance',
                  child: MemoraSegmented(
                    labels: const ['System', 'Dark', 'Light'],
                    selected: switch (theme) {
                      ThemePreference.system => 'System',
                      ThemePreference.dark => 'Dark',
                      ThemePreference.light => 'Light',
                    },
                    onSelected: (label) => unawaited(
                      ref.read(themePreferenceProvider.notifier).set(
                        switch (label) {
                          'Dark' => ThemePreference.dark,
                          'Light' => ThemePreference.light,
                          _ => ThemePreference.system,
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Space.s8),
                SettingsSection(
                  label: 'Your data',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DataAction(
                        icon: MemoraIcons.export,
                        label: _busy != null && _busy!.startsWith('export')
                            ? 'Exporting ${_busy!.replaceFirst('export ', '')}'
                            : 'Export all memories',
                        onTap: _busy == null
                            ? () => unawaited(_export())
                            : null,
                      ),
                      const SizedBox(height: Space.s2),
                      _DataAction(
                        icon: MemoraIcons.arrowsClockwise,
                        label: _busy == 'reindex'
                            ? 'Reindexing…'
                            : 'Reindex embeddings',
                        onTap: _busy == null
                            ? () => unawaited(_reindex())
                            : null,
                      ),
                      const SizedBox(height: Space.s2),
                      _DataAction(
                        icon: MemoraIcons.trash,
                        label: _busy == 'delete'
                            ? 'Deleting…'
                            : 'Delete all memories',
                        onTap: _busy == null
                            ? () => unawaited(_deleteAll())
                            : null,
                      ),
                      if (_flash != null) ...[
                        const SizedBox(height: Space.s3),
                        Text(
                          _flash!,
                          style: MemoraText.style(12.5, color: c.accentInk),
                        ),
                      ],
                      const SizedBox(height: Space.s3),
                      CapsLabel(
                        '${memoryCount(stats?.memoryCount ?? 0)} · '
                        '${byteSize(stats?.imageBytes ?? 0)}',
                        size: 9.5,
                        spacing: 0.9,
                        height: 1.9,
                      ),
                      const CapsLabel(
                        'sqlite + fts5 + vector index · on device',
                        size: 9.5,
                        spacing: 0.9,
                        height: 1.9,
                      ),
                      const CapsLabel(
                        'no memora account',
                        size: 9.5,
                        spacing: 0.9,
                        height: 1.9,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CapabilityRow extends StatelessWidget {
  const _CapabilityRow({
    required this.capability,
    required this.status,
    required this.selection,
    required this.icon,
    required this.onTap,
  });

  final Capability capability;
  final CapabilityStatus? status;
  final CapabilitySelection? selection;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final provider = status?.provider;
    final onDevice = provider?.location == ProviderLocation.onDevice;
    final blocked = status?.reason == UnavailableReason.blockedByLocalOnly;
    final subtitle = switch (status?.reason) {
      null =>
        selection == null
            ? 'Not configured'
            : '${selection!.modelId}${onDevice ? ' · on device' : ''}',
      UnavailableReason.notConfigured => 'Not configured',
      UnavailableReason.missingApiKey => '${selection?.modelId} · needs a key',
      UnavailableReason.modelNotDownloaded =>
        '${selection?.modelId} · not downloaded',
      UnavailableReason.unsupportedByProvider =>
        '${provider?.displayName ?? 'This provider'} cannot do this',
      UnavailableReason.blockedByLocalOnly =>
        '${selection?.modelId}${onDevice ? ' · on device' : ''}',
    };
    return SettingsRow(
      icon: icon,
      title: sentenceCase(capability.key),
      subtitle: subtitle,
      chevron: true,
      onTap: onTap,
      trailing: blocked
          ? const Tag('Unavailable in local-only mode', tone: TagTone.dim)
          : provider == null
          ? const Tag('None', tone: TagTone.dim)
          : Tag(
              onDevice ? 'Local' : provider.displayName,
              tone: onDevice ? TagTone.neutral : TagTone.accent,
            ),
    );
  }
}

class _ModelRow extends StatelessWidget {
  const _ModelRow({
    required this.model,
    required this.onDownload,
    required this.onRemove,
  });

  final LocalModelInfo model;
  final VoidCallback onDownload;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final size = byteSize(model.sizeBytes);
    final (
      String subtitle,
      Widget trailing,
      VoidCallback? onTap,
    ) = switch (model.state) {
      LocalModelState.notDownloaded => (
        '$size · not downloaded',
        const Tag('Download', tone: TagTone.accent),
        onDownload,
      ),
      LocalModelState.downloading => (
        'Downloading ${((model.progress ?? 0) * 100).round()}%',
        const Tag('Working', tone: TagTone.dim),
        null,
      ),
      LocalModelState.ready => ('$size · ready', const Tag('Remove'), onRemove),
      LocalModelState.failed => (
        'Download failed',
        const Tag('Retry', tone: TagTone.accent),
        onDownload,
      ),
    };
    return Column(
      children: [
        SettingsRow(
          icon: MemoraIcons.downloadSimple,
          title: model.displayName,
          subtitle: subtitle,
          trailing: trailing,
          onTap: onTap,
        ),
        if (model.state == LocalModelState.downloading)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.s4, 0, Space.s4, Space.s3),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 2,
                child: LinearProgressIndicator(
                  value: model.progress,
                  backgroundColor: c.lineSoft,
                  valueColor: AlwaysStoppedAnimation(c.accent),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DataAction extends StatelessWidget {
  const _DataAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TapArea(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: Space.s4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: c.line),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: onTap == null ? c.dim : c.muted),
            const SizedBox(width: Space.s4),
            Expanded(
              child: Text(
                label,
                style: MemoraText.style(
                  13.5,
                  color: onTap == null ? c.dim : c.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeleteAllDialog extends StatefulWidget {
  const _DeleteAllDialog();

  @override
  State<_DeleteAllDialog> createState() => _DeleteAllDialogState();
}

class _DeleteAllDialogState extends State<_DeleteAllDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final armed = _controller.text.trim() == 'DELETE';
    return AlertDialog(
      title: const Text('Delete all memories?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Every image, extracted fact and embedding on this phone is '
            'removed. This cannot be undone. Type DELETE to confirm.',
          ),
          const SizedBox(height: Space.s4),
          TextField(
            controller: _controller,
            autocorrect: false,
            decoration: const InputDecoration(hintText: 'DELETE'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: armed ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
