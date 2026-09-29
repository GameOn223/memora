import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/screen_body.dart';
import '../../widgets/screen_header.dart';

/// Sort, facets and results. Filled in by the browser task.
class BrowserScreen extends ConsumerWidget {
  const BrowserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScreenBody(
      header: ScreenHeader(
        title: 'All memories',
        onLeading: () => context.pop(),
      ),
      child: const SizedBox.shrink(),
    );
  }
}
