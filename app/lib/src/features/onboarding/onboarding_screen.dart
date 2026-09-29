import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/memora_colors.dart';

/// Privacy disclosure shown on first launch. Filled in by the onboarding
/// task.
class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      ColoredBox(color: context.colors.bg);
}
