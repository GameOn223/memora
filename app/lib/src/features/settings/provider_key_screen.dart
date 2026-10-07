import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:memora_core/memora_core.dart';

import '../../routing/router.dart';
import '../../state/data_version.dart';
import '../../state/services.dart';
import '../../state/settings.dart';
import '../../theme/memora_colors.dart';
import '../../theme/memora_icons.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../../widgets/external_link.dart';
import '../../widgets/outline_action.dart';
import '../../widgets/screen_header.dart';
import 'settings_rows.dart';

/// The API key and base URL for one provider. Keys are written straight to
/// the platform secret store, never into the database.
class ProviderKeyScreen extends ConsumerStatefulWidget {
  const ProviderKeyScreen({super.key, required this.providerId});

  final String providerId;

  @override
  ConsumerState<ProviderKeyScreen> createState() => _ProviderKeyScreenState();
}

class _ProviderKeyScreenState extends ConsumerState<ProviderKeyScreen> {
  final _key = TextEditingController();
  String? _result;
  bool _resultOk = true;
  bool _testing = false;
  bool _saving = false;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  void _say(String message, {bool ok = true}) {
    if (!mounted) return;
    setState(() {
      _result = message;
      _resultOk = ok;
    });
  }

  Future<void> _save(ProviderDescriptor descriptor) async {
    final value = _key.text.trim();
    if (value.isEmpty || _saving) return;
    setState(() => _saving = true);
    try {
      final services = ref.read(appServicesProvider);
      await services.secrets.write(
        CapabilityRouter.apiKeyName(descriptor.id),
        value,
      );
      _key.clear();
      ref.read(secretsVersionProvider.notifier).bump();
      await ref.read(dataVersionProvider.notifier).check();
      _say('Key saved.');
    } on Object {
      _say('The key could not be saved. Nothing was stored.', ok: false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _remove(ProviderDescriptor descriptor) async {
    try {
      final services = ref.read(appServicesProvider);
      await services.secrets.delete(CapabilityRouter.apiKeyName(descriptor.id));
      ref.read(secretsVersionProvider.notifier).bump();
      _say('Key removed.');
    } on Object {
      _say('The key could not be removed.', ok: false);
    }
  }

  Future<void> _test(ProviderDescriptor descriptor) async {
    setState(() {
      _testing = true;
      _result = null;
    });
    try {
      final services = ref.read(appServicesProvider);
      final client = await services.router.clientFor(descriptor.id);
      final check = await client.testConnection();
      // Only the provider's own message is shown, never a raw exception,
      // which could carry the key itself.
      _say(
        check.ok
            ? 'Connected. ${check.detail ?? ''}'.trim()
            : 'Could not connect. ${check.detail ?? ''}'.trim(),
        ok: check.ok,
      );
    } on AiException catch (error) {
      _say('Could not connect. ${error.message}', ok: false);
    } on Object {
      _say('Could not connect. Check the key and the network.', ok: false);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final services = ref.watch(appServicesProvider);
    final descriptor = services.providers.descriptor(widget.providerId);
    final rows = ref.watch(apiKeysProvider).value ?? const [];
    final stored = rows
        .where((row) => row.provider.id == widget.providerId)
        .map((row) => row.masked)
        .firstOrNull;
    if (descriptor == null) {
      return ColoredBox(
        color: c.bg,
        child: Column(
          children: [
            ScreenHeader(
              title: 'Provider',
              onLeading: () => popOrHome(context),
            ),
            const Spacer(),
          ],
        ),
      );
    }

    return ColoredBox(
      color: c.bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ScreenHeader(
            title: descriptor.displayName,
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
                  label: 'API key · Android Keystore',
                  footnote:
                      'The key is encrypted with a key that never leaves '
                      'this phone. It is not written to the database, the '
                      'logs or an export.',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (stored != null) ...[
                        Row(
                          children: [
                            Icon(MemoraIcons.key, size: 16, color: c.accent),
                            const SizedBox(width: Space.s3),
                            Text(
                              'Saved: $stored',
                              style: MemoraText.style(12.5, color: c.muted),
                            ),
                          ],
                        ),
                        const SizedBox(height: Space.s3),
                      ],
                      TextField(
                        controller: _key,
                        autocorrect: false,
                        obscureText: true,
                        style: MemoraText.style(13.5, color: c.text),
                        decoration: InputDecoration(
                          hintText: descriptor.apiKeyHint ?? 'Paste your key',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.s6),
                OutlineAction(
                  label: _saving ? 'Saving…' : 'Save key',
                  icon: MemoraIcons.checkCircle,
                  onPressed: _key.text.trim().isEmpty || _saving
                      ? null
                      : () => unawaited(_save(descriptor)),
                ),
                const SizedBox(height: Space.s2),
                OutlineAction(
                  label: _testing ? 'Testing…' : 'Test connection',
                  tone: ActionTone.neutral,
                  onPressed: _testing
                      ? null
                      : () => unawaited(_test(descriptor)),
                ),
                if (stored != null) ...[
                  const SizedBox(height: Space.s2),
                  OutlineAction(
                    label: 'Remove key',
                    tone: ActionTone.ghost,
                    onPressed: () => unawaited(_remove(descriptor)),
                  ),
                ],
                if (_result != null) ...[
                  const SizedBox(height: Space.s4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        _resultOk
                            ? MemoraIcons.checkCircle
                            : MemoraIcons.warningCircle,
                        size: 15,
                        color: _resultOk ? c.accent : c.muted,
                      ),
                      const SizedBox(width: Space.s3),
                      Expanded(
                        child: Text(
                          _result!,
                          style: MemoraText.style(
                            12.5,
                            height: 1.5,
                            color: _resultOk ? c.accentInk : c.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                // The exact page the key is made on, not the home page
                // someone then has to find their way around.
                if (descriptor.apiKeyUrl case final url?) ...[
                  const SizedBox(height: Space.s8),
                  ExternalLink(
                    label: 'Get a ${descriptor.displayName} key',
                    url: url,
                    size: 12,
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
