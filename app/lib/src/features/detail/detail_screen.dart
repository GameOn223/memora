import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../widgets/screen_body.dart';
import '../../widgets/screen_header.dart';

/// One memory in full. Filled in by the detail task.
class DetailScreen extends ConsumerWidget {
  const DetailScreen({super.key, required this.memoryId});

  final String memoryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScreenBody(
      header: ScreenHeader(title: 'Memory', onLeading: () => context.pop()),
      child: const SizedBox.shrink(),
    );
  }
}
