import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/services.dart';
import '../../widgets/screen_body.dart';
import '../../widgets/screen_header.dart';

/// API key and base URL for one provider. Filled in by the settings task.
class ProviderKeyScreen extends ConsumerWidget {
  const ProviderKeyScreen({super.key, required this.providerId});

  final String providerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final descriptor = ref
        .watch(appServicesProvider)
        .providers
        .descriptor(providerId);
    return ScreenBody(
      header: ScreenHeader(
        title: descriptor?.displayName ?? 'Provider',
        onLeading: () => context.pop(),
      ),
      child: const SizedBox.shrink(),
    );
  }
}
