import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:memora_core/memora_core.dart';

import '../features/add/add_screen.dart';
import '../features/browser/browser_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/detail/detail_screen.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/queue/queue_screen.dart';
import '../features/settings/capability_screen.dart';
import '../features/settings/provider_key_screen.dart';
import '../features/settings/settings_screen.dart';
import '../theme/memora_colors.dart';
import 'app_shell.dart';

/// Paths used across the app.
abstract final class Routes {
  static const onboarding = '/onboarding';
  static const home = '/';
  static const ask = '/ask';
  static const add = '/add';
  static const settings = '/settings';
  static const browser = '/browser';
  static const queue = '/queue';

  static String memory(String id) => '/memory/$id';

  static String capability(Capability capability) =>
      '/settings/capability/${capability.key}';

  static String providerKey(String providerId) =>
      '/settings/provider/$providerId';

  /// Tab order in the bottom bar.
  static const tabRoots = [home, ask, add, settings];
}

/// Goes back where the user came from, or home when this screen was the
/// entry point (a deep link, or a test opening it directly).
void popOrHome(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(Routes.home);
  }
}

final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
final _homeKey = GlobalKey<NavigatorState>(debugLabel: 'memories');
final _askKey = GlobalKey<NavigatorState>(debugLabel: 'ask');
final _addKey = GlobalKey<NavigatorState>(debugLabel: 'add');
final _settingsKey = GlobalKey<NavigatorState>(debugLabel: 'settings');

/// Screens pushed over the shell get their own Material surface, since
/// they are outside the shell's Scaffold.
Widget _surface(Widget child) => Builder(
  builder: (context) =>
      Scaffold(backgroundColor: context.colors.bg, body: child),
);

Page<void> _page(GoRouterState state, Widget child) =>
    MaterialPage(key: state.pageKey, name: state.name, child: _surface(child));

Page<void> _flat(GoRouterState state, Widget child) =>
    NoTransitionPage(key: state.pageKey, name: state.name, child: child);

GoRouter buildRouter({String initialLocation = Routes.home}) {
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    routes: [
      GoRoute(
        path: Routes.onboarding,
        name: 'onboarding',
        pageBuilder: (context, state) => _flat(state, const OnboardingScreen()),
      ),
      GoRoute(
        path: '/memory/:id',
        name: 'memory',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) =>
            _page(state, DetailScreen(memoryId: state.pathParameters['id']!)),
      ),
      GoRoute(
        path: Routes.queue,
        name: 'queue',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (context, state) => _page(state, const QueueScreen()),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) =>
            AppShell(shell: shell, location: state.uri.path),
        branches: [
          StatefulShellBranch(
            navigatorKey: _homeKey,
            routes: [
              GoRoute(
                path: Routes.home,
                name: 'home',
                pageBuilder: (context, state) =>
                    _flat(state, const HomeScreen()),
                routes: [
                  GoRoute(
                    path: 'browser',
                    name: 'browser',
                    pageBuilder: (context, state) =>
                        _page(state, const BrowserScreen()),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _askKey,
            routes: [
              GoRoute(
                path: Routes.ask,
                name: 'ask',
                pageBuilder: (context, state) =>
                    _flat(state, const ChatScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _addKey,
            routes: [
              GoRoute(
                path: Routes.add,
                name: 'add',
                pageBuilder: (context, state) =>
                    _flat(state, const AddScreen()),
              ),
            ],
          ),
          StatefulShellBranch(
            navigatorKey: _settingsKey,
            routes: [
              GoRoute(
                path: Routes.settings,
                name: 'settings',
                pageBuilder: (context, state) =>
                    _flat(state, const SettingsScreen()),
                routes: [
                  GoRoute(
                    path: 'capability/:capability',
                    name: 'capability',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) => _page(
                      state,
                      CapabilityScreen(
                        capability: Capability.fromKey(
                          state.pathParameters['capability']!,
                        ),
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'provider/:id',
                    name: 'provider',
                    parentNavigatorKey: rootNavigatorKey,
                    pageBuilder: (context, state) => _page(
                      state,
                      ProviderKeyScreen(
                        providerId: state.pathParameters['id']!,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
