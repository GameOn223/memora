import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../routing/router.dart';
import '../../widgets/screen_body.dart';
import '../../widgets/screen_header.dart';

/// Gallery picker. Filled in by the add task.
class AddScreen extends ConsumerWidget {
  const AddScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScreenBody(
      header: ScreenHeader(
        title: 'Add from gallery',
        leading: HeaderLeading.close,
        onLeading: () => context.go(Routes.home),
      ),
      child: const SizedBox.shrink(),
    );
  }
}
