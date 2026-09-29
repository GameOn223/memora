import 'package:flutter/widgets.dart';

import 'src/platform/background_entry.dart';
import 'src/services/app_services.dart';

/// Headless entrypoint started by WorkManager workers. See
/// docs/architecture.md, section 10.
///
/// Two things have to be true for Android to find this function:
/// it keeps the `vm:entry-point` pragma, and `main.dart` imports this file
/// (the compiler only includes libraries reachable from `main.dart`).
@pragma('vm:entry-point')
Future<void> backgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  await runBackground(createBackgroundServices);
}

/// Hook for the composition root. Integration replaces the body with a call
/// that opens the database and builds real services, for example
/// `createAppServices(background: true)`.
Future<AppServices> createBackgroundServices() {
  throw UnimplementedError(
    'Background services are not wired yet. '
    'Point createBackgroundServices at the composition root.',
  );
}
