import 'dart:async';

import 'package:flutter/material.dart';
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
import '../../widgets/bordered_list.dart';
import '../../widgets/chip_bar.dart';
import '../../widgets/memory_labels.dart';
import '../../widgets/outline_action.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/tags.dart';
import 'cloud_disclosure.dart';
import 'settings_rows.dart';

/// Chooses the provider and model for one capability.
class CapabilityScreen extends ConsumerStatefulWidget {
  const CapabilityScreen({super.key, required this.capability});

  final Capability capability;

  @override
  ConsumerState<CapabilityScreen> createState() => _CapabilityScreenState();
}

class _CapabilityScreenState extends ConsumerState<CapabilityScreen> {
  final _model = TextEditingController();
  final _baseUrl = TextEditingController();
  String? _providerId;
  List<String> _suggestions = const [];
  bool _loaded = false;

  @override
  void dispose() {
    _model.dispose();
    _baseUrl.dispose();
    super.dispose();
  }

  void _loadFrom(AiSettings settings) {
    if (_loaded) return;
    _loaded = true;
    final selection = settings.selections[widget.capability];
    if (selection == null) return;
    _providerId = selection.providerId;
    _model.text = selection.modelId;
    _baseUrl.text = settings.baseUrls[selection.providerId] ?? '';
    unawaited(_loadSuggestions(selection.providerId));
  }

  Future<void> _loadSuggestions(String providerId) async {
    final services = ref.read(appServicesProvider);
    final descriptor = services.providers.descriptor(providerId);
    var models = descriptor?.suggestedModels[widget.capability] ?? const [];
    try {
      final client = await services.router.clientFor(providerId);
      final listed = await client.listModels(widget.capability);
      if (listed.isNotEmpty) models = listed;
    } on Object {
      // Keep the suggested list when the provider can't be reached.
    }
    if (mounted) setState(() => _suggestions = models);
  }

  void _pick(ProviderDescriptor descriptor, AiSettings settings) {
    setState(() {
      _providerId = descriptor.id;
      _model.text = descriptor.defaultModel(widget.capability) ?? _model.text;
      _baseUrl.text =
          settings.baseUrls[descriptor.id] ?? descriptor.defaultBaseUrl ?? '';
      _suggestions = const [];
    });
    unawaited(_loadSuggestions(descriptor.id));
  }

  Future<void> _save(AiSettings settings) async {
    final providerId = _providerId;
    final model = _model.text.trim();
    if (providerId == null || model.isEmpty) return;
    final services = ref.read(appServicesProvider);
    final descriptor = services.providers.descriptor(providerId);
    if (descriptor == null) return;
    if (descriptor.location == ProviderLocation.cloud &&
        !settings.acknowledgedCloudProviders.contains(descriptor.id)) {
      final accepted = await showCloudDisclosure(context, descriptor);
      if (!accepted) return;
      await ref
          .read(aiSettingsProvider.notifier)
          .acknowledgeCloud(descriptor.id);
    }
    await ref
        .read(aiSettingsProvider.notifier)
        .select(
          widget.capability,
          CapabilitySelection(providerId, model),
          baseUrl: descriptor.baseUrlEditable ? _baseUrl.text.trim() : null,
        );
    if (mounted) popOrHome(context);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final services = ref.watch(appServicesProvider);
    final settings = ref.watch(aiSettingsProvider).value ?? const AiSettings();
    _loadFrom(settings);
    final providers = services.providers.supporting(widget.capability);
    final selected = _providerId == null
        ? null
        : services.providers.descriptor(_providerId!);
    final url = _baseUrl.text.trim();
    final blocked =
        settings.localOnly &&
        selected != null &&
        !const LocalOnlyPolicy().allows(
          selected,
          url.isEmpty ? selected.defaultBaseUrl : url,
        );

    return ColoredBox(
      color: c.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(
            title: sentenceCase(widget.capability.key),
            onLeading: () => popOrHome(context),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                Space.s6,
                Space.s2,
                Space.s6,
                Space.s8 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                SettingsSection(
                  label: 'Provider',
                  child: BorderedList(
                    children: [
                      for (final provider in providers)
                        SettingsRow(
                          title: provider.displayName,
                          subtitle: locationLabel(provider.location),
                          onTap: () => _pick(provider, settings),
                          trailing: provider.id == _providerId
                              ? const Tag('Selected', tone: TagTone.accent)
                              : null,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.s8),
                SettingsSection(
                  label: 'Model',
                  footnote:
                      'Any model id the provider accepts works here. The '
                      'suggestions come from the provider itself.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _model,
                        autocorrect: false,
                        style: MemoraText.style(13.5, color: c.text),
                        decoration: const InputDecoration(hintText: 'model id'),
                        onChanged: (_) => setState(() {}),
                      ),
                      if (_suggestions.isNotEmpty) ...[
                        const SizedBox(height: Space.s3),
                        Wrap(
                          spacing: Space.s2,
                          runSpacing: Space.s2,
                          children: [
                            for (final suggestion in _suggestions.take(8))
                              SelectChip(
                                label: suggestion,
                                selected: _model.text.trim() == suggestion,
                                onTap: () =>
                                    setState(() => _model.text = suggestion),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected?.baseUrlEditable ?? false) ...[
                  const SizedBox(height: Space.s8),
                  SettingsSection(
                    label: 'Base URL',
                    footnote:
                        'Local-only mode allows this provider when the '
                        'address points at this device or your own network.',
                    child: TextField(
                      controller: _baseUrl,
                      autocorrect: false,
                      keyboardType: TextInputType.url,
                      style: MemoraText.style(13.5, color: c.text),
                      decoration: InputDecoration(
                        hintText: selected?.defaultBaseUrl ?? 'http://…',
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
                if (selected != null && selected.requiresApiKey) ...[
                  const SizedBox(height: Space.s8),
                  BorderedList(
                    children: [
                      SettingsRow(
                        icon: MemoraIcons.key,
                        title: 'API key',
                        subtitle: '${selected.displayName} · Android Keystore',
                        chevron: true,
                        onTap: () =>
                            context.push(Routes.providerKey(selected.id)),
                      ),
                    ],
                  ),
                ],
                if (blocked) ...[
                  const SizedBox(height: Space.s6),
                  Container(
                    padding: const EdgeInsets.all(Space.s4),
                    decoration: BoxDecoration(
                      color: c.surface2,
                      borderRadius: BorderRadius.circular(Radii.md),
                      border: Border.all(color: c.accentLine),
                    ),
                    child: Text(
                      'Local-only mode is on, so this provider stays '
                      'unavailable until you turn it off.',
                      style: MemoraText.style(
                        12.5,
                        height: 1.55,
                        color: c.text,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: Space.s8),
                OutlineAction(
                  label: selected == null
                      ? 'Choose a provider'
                      : 'Use ${selected.displayName}',
                  icon: MemoraIcons.checkCircle,
                  onPressed: selected == null || _model.text.trim().isEmpty
                      ? null
                      : () => unawaited(_save(settings)),
                ),
                if (settings.selections[widget.capability] != null) ...[
                  const SizedBox(height: Space.s2),
                  OutlineAction(
                    label: 'Use nothing for this',
                    tone: ActionTone.ghost,
                    onPressed: () async {
                      await ref
                          .read(aiSettingsProvider.notifier)
                          .clear(widget.capability);
                      if (context.mounted) popOrHome(context);
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// How a provider runs, in plain words.
String locationLabel(ProviderLocation location) => switch (location) {
  ProviderLocation.onDevice => 'Runs on this phone',
  ProviderLocation.selfHosted => 'A server you run',
  ProviderLocation.cloud => 'Cloud service',
};
