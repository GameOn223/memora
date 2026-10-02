import 'package:meta/meta.dart';

import '../model/processing.dart';
import '../ports/stores.dart';

/// Which provider and model serve one capability.
@immutable
class CapabilitySelection {
  const CapabilitySelection(this.providerId, this.modelId);

  final String providerId;
  final String modelId;

  @override
  bool operator ==(Object other) =>
      other is CapabilitySelection &&
      other.providerId == providerId &&
      other.modelId == modelId;

  @override
  int get hashCode => Object.hash(providerId, modelId);
}

/// AI-related settings. Stored as JSON under [AiSettingsRepository.key].
@immutable
class AiSettings {
  const AiSettings({
    this.selections = const {},
    this.baseUrls = const {},
    this.localOnly = false,
    this.verifyAnswers = true,
    this.acknowledgedCloudProviders = const {},
  });

  factory AiSettings.fromJson(Map<String, Object?> json) {
    final selections = <Capability, CapabilitySelection>{};
    final rawSelections = json['selections'];
    if (rawSelections is Map) {
      for (final entry in rawSelections.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        final provider = value['provider'];
        final model = value['model'];
        if (provider is! String || model is! String) continue;
        try {
          selections[Capability.fromKey(entry.key as String)] =
              CapabilitySelection(provider, model);
        } on ArgumentError {
          // Unknown capability from a newer version; ignore it.
        }
      }
    }
    final rawUrls = json['base_urls'];
    final rawAck = json['acknowledged_cloud_providers'];
    return AiSettings(
      selections: selections,
      baseUrls: rawUrls is Map ? rawUrls.cast<String, String>() : const {},
      localOnly: json['local_only'] as bool? ?? false,
      verifyAnswers: json['verify_answers'] as bool? ?? true,
      acknowledgedCloudProviders: rawAck is List
          ? rawAck.whereType<String>().toSet()
          : const {},
    );
  }

  final Map<Capability, CapabilitySelection> selections;

  /// Base URL overrides by provider id.
  final Map<String, String> baseUrls;
  final bool localOnly;

  /// Check single-value answers against the original image.
  final bool verifyAnswers;

  /// Cloud providers the user has seen the disclosure for.
  final Set<String> acknowledgedCloudProviders;

  AiSettings copyWith({
    Map<Capability, CapabilitySelection>? selections,
    Map<String, String>? baseUrls,
    bool? localOnly,
    bool? verifyAnswers,
    Set<String>? acknowledgedCloudProviders,
  }) {
    return AiSettings(
      selections: selections ?? this.selections,
      baseUrls: baseUrls ?? this.baseUrls,
      localOnly: localOnly ?? this.localOnly,
      verifyAnswers: verifyAnswers ?? this.verifyAnswers,
      acknowledgedCloudProviders:
          acknowledgedCloudProviders ?? this.acknowledgedCloudProviders,
    );
  }

  /// Returns a copy with [capability] cleared.
  AiSettings withoutSelection(Capability capability) =>
      copyWith(selections: {...selections}..remove(capability));

  Map<String, Object?> toJson() => {
    'selections': {
      for (final e in selections.entries)
        e.key.key: {'provider': e.value.providerId, 'model': e.value.modelId},
    },
    'base_urls': baseUrls,
    'local_only': localOnly,
    'verify_answers': verifyAnswers,
    'acknowledged_cloud_providers': acknowledgedCloudProviders.toList()..sort(),
  };
}

/// Loads and saves [AiSettings] through the generic settings store.
class AiSettingsRepository {
  const AiSettingsRepository(this._store);

  static const key = 'ai';

  final SettingsStore _store;

  Future<AiSettings> load() async {
    final raw = await _store.read(key);
    return raw is Map
        ? AiSettings.fromJson(raw.cast<String, Object?>())
        : const AiSettings();
  }

  Future<void> save(AiSettings settings) =>
      _store.write(key, settings.toJson());
}
