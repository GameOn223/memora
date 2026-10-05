import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../routing/router.dart';
import '../../services/app_services.dart';
import '../../state/queue.dart';
import '../../state/settings.dart';
import '../../theme/memora_colors.dart';
import '../../theme/memora_icons.dart';
import '../../theme/text_styles.dart';
import '../../widgets/memora_icon_button.dart';
import '../../widgets/screen_header.dart';

/// Brand row on the home and empty screens: theme, queue, browser and
/// settings.
class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key, this.compact = false});

  /// The empty screen shows only the settings button.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final waiting = ref.watch(queueWaitingCountProvider);
    final preference =
        ref.watch(themePreferenceProvider).value ?? ThemePreference.system;
    return ScreenHeader(
      title: 'Memora',
      brand: true,
      leading: HeaderLeading.none,
      trailing: [
        if (!compact) ...[
          MemoraIconButton(
            icon: MemoraIcons.circleHalf,
            semanticLabel: 'Theme: ${preference.name}. Change theme',
            onPressed: () => ref.read(themePreferenceProvider.notifier).cycle(),
          ),
          MemoraIconButton(
            icon: MemoraIcons.stack,
            semanticLabel: waiting == 0
                ? 'Processing queue'
                : 'Processing queue, $waiting waiting',
            onPressed: () => context.push(Routes.queue),
            badge: waiting == 0 ? null : _Badge(count: waiting),
          ),
          MemoraIconButton(
            icon: MemoraIcons.funnel,
            semanticLabel: 'Browse all memories',
            onPressed: () => context.go(Routes.browser),
          ),
        ],
        MemoraIconButton(
          icon: MemoraIcons.slidersHorizontal,
          semanticLabel: 'AI and privacy settings',
          onPressed: () => context.go(Routes.settings),
          color: c.muted,
        ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Container(
      constraints: const BoxConstraints(minWidth: 14),
      height: 14,
      padding: const EdgeInsets.symmetric(horizontal: 3),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: c.accentTint,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: c.accentLine),
      ),
      child: Text(
        '$count',
        style: MemoraText.style(
          8,
          medium: true,
          tabular: true,
          color: c.accentInk,
        ),
      ),
    );
  }
}
