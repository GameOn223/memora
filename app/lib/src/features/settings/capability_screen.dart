import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:memora_core/memora_core.dart';

import '../../routing/router.dart';
import '../../widgets/memory_labels.dart';
import '../../widgets/screen_body.dart';
import '../../widgets/screen_header.dart';

/// Picks the provider and model for one capability. Filled in by the
/// settings task.
class CapabilityScreen extends ConsumerWidget {
  const CapabilityScreen({super.key, required this.capability});

  final Capability capability;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ScreenBody(
      header: ScreenHeader(
        title: sentenceCase(capability.key),
        onLeading: () => popOrHome(context),
      ),
      child: const SizedBox.shrink(),
    );
  }
}
