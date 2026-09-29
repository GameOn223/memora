import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/screen_body.dart';
import '../../widgets/screen_header.dart';

/// Processing queue. Filled in by the queue task.
class QueueScreen extends ConsumerWidget {
  const QueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScreenBody(
      header: ScreenHeader(
        title: 'Processing queue',
        onLeading: () => context.pop(),
      ),
      child: const SizedBox.shrink(),
    );
  }
}
