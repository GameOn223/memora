import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../routing/router.dart';
import '../../widgets/screen_body.dart';
import '../../widgets/screen_header.dart';

/// AI and privacy. Filled in by the settings task.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScreenBody(
      header: ScreenHeader(
        title: 'AI & privacy',
        onLeading: () => context.go(Routes.home),
      ),
      child: const SizedBox.shrink(),
    );
  }
}
