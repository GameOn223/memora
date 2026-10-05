import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/app_services.dart';
import '../state/settings.dart';
import '../theme/memora_colors.dart';
import '../theme/memora_theme.dart';
import 'router.dart';

/// The app itself. It waits for the stored preferences before building the
/// router, so first launch opens onboarding without a flash of the grid.
class MemoraApp extends ConsumerStatefulWidget {
  const MemoraApp({super.key, this.initialLocation});

  /// Overrides where the app opens. Used by tests and screenshots.
  final String? initialLocation;

  @override
  ConsumerState<MemoraApp> createState() => _MemoraAppState();
}

class _MemoraAppState extends ConsumerState<MemoraApp> {
  GoRouter? _router;

  @override
  void dispose() {
    _router?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onboarded = ref.watch(onboardingCompleteProvider).value;
    final preference =
        ref.watch(themePreferenceProvider).value ?? ThemePreference.system;
    final themeMode = switch (preference) {
      ThemePreference.system => ThemeMode.system,
      ThemePreference.dark => ThemeMode.dark,
      ThemePreference.light => ThemeMode.light,
    };
    if (onboarded == null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: MemoraTheme.light(),
        darkTheme: MemoraTheme.dark(),
        themeMode: themeMode,
        home: const ColoredBox(color: Color(0x00000000)),
      );
    }
    final router = _router ??= buildRouter(
      initialLocation:
          widget.initialLocation ??
          (onboarded ? Routes.home : Routes.onboarding),
    );
    return MaterialApp.router(
      title: 'Memora',
      debugShowCheckedModeBanner: false,
      theme: MemoraTheme.light(),
      darkTheme: MemoraTheme.dark(),
      themeMode: themeMode,
      routerConfig: router,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: MemoraTheme.overlayStyle(Theme.of(context).brightness),
        child: ColoredBox(
          color: context.colors.bg,
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
