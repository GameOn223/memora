import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/bootstrap/app_preferences_impl.dart';
import 'package:memora/src/services/app_services.dart';

import '../platform/fakes.dart';

void main() {
  late MemorySettings settings;
  late StoredAppPreferences preferences;

  setUp(() {
    settings = MemorySettings();
    preferences = StoredAppPreferences(settings);
  });

  test('a fresh install shows onboarding, the system theme and 2', () async {
    expect(await preferences.onboardingComplete(), isFalse);
    expect(await preferences.theme(), ThemePreference.system);
    expect(await preferences.gridColumns(), StoredAppPreferences.defaultColumns);
  });

  test('every preference is read back as it was written', () async {
    await preferences.setOnboardingComplete();
    await preferences.setTheme(ThemePreference.light);
    await preferences.setGridColumns(8);

    expect(await preferences.onboardingComplete(), isTrue);
    expect(await preferences.theme(), ThemePreference.light);
    expect(await preferences.gridColumns(), 8);

    // A second reader over the same store sees the same values, which is how
    // a restart reads them.
    final reopened = StoredAppPreferences(settings);
    expect(await reopened.onboardingComplete(), isTrue);
    expect(await reopened.theme(), ThemePreference.light);
    expect(await reopened.gridColumns(), 8);
  });

  test('each theme is stored under its own name', () async {
    for (final preference in ThemePreference.values) {
      await preferences.setTheme(preference);
      expect(await settings.read(StoredAppPreferences.themeKey), preference.name);
      expect(await preferences.theme(), preference);
    }
  });

  test('the grid takes only the widths the toggle offers', () async {
    for (final columns in StoredAppPreferences.allowedColumns) {
      await preferences.setGridColumns(columns);
      expect(await preferences.gridColumns(), columns);
    }
    expect(() => preferences.setGridColumns(3), throwsArgumentError);
    expect(await preferences.gridColumns(), 8);
  });

  test('a value a newer build wrote falls back to the default', () async {
    await settings.write(StoredAppPreferences.themeKey, 'sepia');
    await settings.write(StoredAppPreferences.gridColumnsKey, 'lots');
    await settings.write(StoredAppPreferences.onboardingKey, 'yes');

    expect(await preferences.theme(), ThemePreference.system);
    expect(await preferences.gridColumns(), StoredAppPreferences.defaultColumns);
    expect(await preferences.onboardingComplete(), isFalse);
  });
}
