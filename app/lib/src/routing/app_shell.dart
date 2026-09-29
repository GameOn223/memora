import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/memories.dart';
import '../theme/memora_colors.dart';
import '../widgets/bottom_tabs.dart';
import 'router.dart';

/// Holds the four tabs and paints the bottom bar over the screens that show
/// it. Ask, Add and the drill-in screens run full height, as in the design.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.shell, required this.location});

  final StatefulNavigationShell shell;
  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasMemories = ref.watch(hasMemoriesProvider);
    final showTabs = switch (location) {
      Routes.home => hasMemories,
      Routes.browser || Routes.settings => true,
      _ => false,
    };
    return PopScope(
      // Back from another tab returns to Memories instead of leaving.
      canPop: shell.currentIndex == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) shell.goBranch(0);
      },
      child: Scaffold(
        backgroundColor: context.colors.bg,
        body: Stack(
          children: [
            Positioned.fill(child: shell),
            if (showTabs)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: BottomTabs(
                  currentIndex: shell.currentIndex,
                  onSelected: (index) => shell.goBranch(
                    index,
                    initialLocation: index == shell.currentIndex,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
