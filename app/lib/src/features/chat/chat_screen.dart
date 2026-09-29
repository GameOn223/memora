import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../routing/router.dart';
import '../../widgets/screen_body.dart';
import '../../widgets/screen_header.dart';

/// Ask Memora. Filled in by the ask task.
class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScreenBody(
      header: ScreenHeader(
        title: 'Ask Memora',
        onLeading: () => context.go(Routes.home),
      ),
      child: const SizedBox.shrink(),
    );
  }
}
