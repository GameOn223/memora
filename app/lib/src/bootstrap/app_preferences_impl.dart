import 'package:memora_core/memora_core.dart';

import '../services/app_services.dart';

/// [AppPreferences] on top of the settings table.
///
/// These sit next to the AI and queue settings rather than in their own
/// store, so one export carries everything the user chose. Nothing here is a
/// secret. A value written by a newer build, or edited by hand, falls back to
/// the default instead of throwing.
class StoredAppPreferences implements AppPreferences {
  const StoredAppPreferences(this._settings);

  static const onboardingKey = 'onboarding_complete';
  static const themeKey = 'theme';
  static const gridColumnsKey = 'grid_columns';

  /// What the density toggle on the memories grid offers.
  static const allowedColumns = [2, 4, 8];

  static const defaultColumns = 2;

  final SettingsStore _settings;

  @override
  Future<bool> onboardingComplete() async =>
      await _settings.read(onboardingKey) == true;

  @override
  Future<void> setOnboardingComplete() => _settings.write(onboardingKey, true);

  @override
  Future<ThemePreference> theme() async {
    final stored = await _settings.read(themeKey);
    for (final preference in ThemePreference.values) {
      if (preference.name == stored) return preference;
    }
    return ThemePreference.system;
  }

  @override
  Future<void> setTheme(ThemePreference theme) =>
      _settings.write(themeKey, theme.name);

  @override
  Future<int> gridColumns() async {
    final stored = await _settings.read(gridColumnsKey);
    return stored is int && allowedColumns.contains(stored)
        ? stored
        : defaultColumns;
  }

  @override
  Future<void> setGridColumns(int columns) {
    if (!allowedColumns.contains(columns)) {
      throw ArgumentError.value(
        columns,
        'columns',
        'The grid offers $allowedColumns columns',
      );
    }
    return _settings.write(gridColumnsKey, columns);
  }
}
