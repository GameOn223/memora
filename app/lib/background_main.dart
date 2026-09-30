import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'src/platform/background_entry.dart';
import 'src/platform/messages.g.dart';
import 'src/services/app_services.dart';

/// Headless entrypoint started by WorkManager workers. See
/// docs/architecture.md, section 10.
///
/// Two things have to be true for Android to find this function: it keeps the
/// `vm:entry-point` pragma, and `main.dart` references this library. Release
/// builds drop libraries `main.dart` can't reach.
@pragma('vm:entry-point')
Future<void> backgroundMain() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await runBackground(createBackgroundServices);
  } catch (error, stack) {
    // Fail the worker now instead of letting it wait out the readiness
    // timeout, and leave something in the log to act on.
    debugPrint('Memora background entrypoint failed: $error');
    debugPrintStack(stackTrace: stack);
    await BackgroundHostApi().backgroundFailed('$error');
  }
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
