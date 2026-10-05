import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:memora_core/memora_core.dart';

import '../services/app_services.dart';
import 'data_version.dart';
import 'services.dart';

/// Whether onboarding has been seen. Read once at startup.
final onboardingCompleteProvider = FutureProvider<bool>((ref) async {
  return ref.watch(appServicesProvider).preferences.onboardingComplete();
});

final themePreferenceProvider =
    AsyncNotifierProvider<ThemeController, ThemePreference>(
      ThemeController.new,
    );

class ThemeController extends AsyncNotifier<ThemePreference> {
  @override
  Future<ThemePreference> build() =>
      ref.watch(appServicesProvider).preferences.theme();

  Future<void> set(ThemePreference preference) async {
    state = AsyncData(preference);
    await ref.read(appServicesProvider).preferences.setTheme(preference);
  }

  /// System, then dark, then light, as the home header's toggle cycles.
  Future<void> cycle() async {
    final next = switch (state.value ?? ThemePreference.system) {
      ThemePreference.system => ThemePreference.dark,
      ThemePreference.dark => ThemePreference.light,
      ThemePreference.light => ThemePreference.system,
    };
    await set(next);
  }
}

final gridColumnsProvider = AsyncNotifierProvider<GridColumnsController, int>(
  GridColumnsController.new,
);

class GridColumnsController extends AsyncNotifier<int> {
  @override
  Future<int> build() =>
      ref.watch(appServicesProvider).preferences.gridColumns();

  Future<void> set(int columns) async {
    state = AsyncData(columns);
    await ref.read(appServicesProvider).preferences.setGridColumns(columns);
  }
}

final aiSettingsProvider =
    AsyncNotifierProvider<AiSettingsController, AiSettings>(
      AiSettingsController.new,
    );

class AiSettingsController extends AsyncNotifier<AiSettings> {
  @override
  Future<AiSettings> build() =>
      ref.watch(appServicesProvider).aiSettings.load();

  Future<void> save(AiSettings settings) async {
    state = AsyncData(settings);
    final services = ref.read(appServicesProvider);
    await services.aiSettings.save(settings);
    // Which providers are selected decides whether background work needs
    // Wi-Fi, so the native schedule is rebuilt whenever they change.
    await services.scheduler.refresh();
  }

  Future<void> setLocalOnly({required bool localOnly}) async {
    final current = state.value ?? const AiSettings();
    await save(current.copyWith(localOnly: localOnly));
  }

  Future<void> setVerifyAnswers({required bool verify}) async {
    final current = state.value ?? const AiSettings();
    await save(current.copyWith(verifyAnswers: verify));
  }

  Future<void> select(
    Capability capability,
    CapabilitySelection selection, {
    String? baseUrl,
  }) async {
    final current = state.value ?? const AiSettings();
    await save(
      current.copyWith(
        selections: {...current.selections, capability: selection},
        baseUrls: baseUrl == null
            ? current.baseUrls
            : {...current.baseUrls, selection.providerId: baseUrl},
      ),
    );
  }

  Future<void> clear(Capability capability) async {
    final current = state.value ?? const AiSettings();
    await save(current.withoutSelection(capability));
  }

  Future<void> acknowledgeCloud(String providerId) async {
    final current = state.value ?? const AiSettings();
    await save(
      current.copyWith(
        acknowledgedCloudProviders: {
          ...current.acknowledgedCloudProviders,
          providerId,
        },
      ),
    );
  }

  Future<void> setBaseUrl(String providerId, String? baseUrl) async {
    final current = state.value ?? const AiSettings();
    final urls = {...current.baseUrls};
    if (baseUrl == null || baseUrl.trim().isEmpty) {
      urls.remove(providerId);
    } else {
      urls[providerId] = baseUrl.trim();
    }
    await save(current.copyWith(baseUrls: urls));
  }
}

/// Availability of each capability, recomputed when settings or keys change.
final capabilityStatusesProvider =
    FutureProvider<Map<Capability, CapabilityStatus>>((ref) async {
      await ref.watch(aiSettingsProvider.future);
      ref.watch(secretsVersionProvider);
      return ref.watch(appServicesProvider).router.statuses();
    });

/// Selected providers that send data off the phone.
final offDeviceProvidersProvider = FutureProvider<List<ProviderDescriptor>>((
  ref,
) async {
  final settings = await ref.watch(aiSettingsProvider.future);
  final providers = await ref
      .watch(appServicesProvider)
      .router
      .offDeviceProviders();
  if (!settings.localOnly) return providers;
  // In local-only mode only a provider on the local network can still run.
  return [
    for (final p in providers)
      if (p.location == ProviderLocation.selfHosted) p,
  ];
});

/// An API key row in settings.
@immutable
class ApiKeyRow {
  const ApiKeyRow({required this.provider, this.masked});

  final ProviderDescriptor provider;

  /// `nvapi-••••7Q2f`, or null when no key is stored.
  final String? masked;
}

final apiKeysProvider = FutureProvider<List<ApiKeyRow>>((ref) async {
  ref.watch(secretsVersionProvider);
  final services = ref.watch(appServicesProvider);
  final rows = <ApiKeyRow>[];
  for (final provider in services.providers.descriptors) {
    if (!provider.requiresApiKey) continue;
    final key = await services.secrets.read(
      CapabilityRouter.apiKeyName(provider.id),
    );
    rows.add(ApiKeyRow(provider: provider, masked: maskApiKey(key)));
  }
  return rows;
});

/// Shows enough of a key to recognize it: the first six characters, four
/// bullets, and the last four.
String? maskApiKey(String? key) {
  if (key == null || key.isEmpty) return null;
  if (key.length <= 10) {
    return '••••${key.length > 4 ? key.substring(key.length - 2) : ''}';
  }
  return '${key.substring(0, 6)}••••${key.substring(key.length - 4)}';
}

final captureSetupProvider = FutureProvider<CaptureSetup>((ref) async {
  ref.watch(captureVersionProvider);
  return ref.watch(appServicesProvider).capture.setup();
});

/// Bumped after a capture setting is changed so the rows re-read.
final captureVersionProvider = NotifierProvider<CaptureVersion, int>(
  CaptureVersion.new,
);

class CaptureVersion extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}

final localModelsProvider = StreamProvider<List<LocalModelInfo>>((ref) {
  return ref.watch(appServicesProvider).localModels.watch();
});

final chatAvailabilityProvider = FutureProvider<ChatAvailability>((ref) async {
  await ref.watch(aiSettingsProvider.future);
  ref.watch(secretsVersionProvider);
  return ref.watch(appServicesProvider).chat.availability();
});
