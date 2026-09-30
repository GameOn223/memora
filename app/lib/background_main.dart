import 'package:flutter/widgets.dart';

import 'src/bootstrap/bootstrap.dart';
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
    await runBackground(
      createBackgroundServices,
      // The engine is destroyed once the worker's call returns, and that
      // leaves the database connection and the HTTP client open. Close them
      // while there is still an isolate to close them from.
      onFinished: disposeMemoraServices,
    );
  } catch (error, stack) {
    // Fail the worker now instead of letting it wait out the readiness
    // timeout, and leave something in the log to act on.
    debugPrint('Memora background entrypoint failed: $error');
    debugPrintStack(stackTrace: stack);
    await BackgroundHostApi().backgroundFailed('$error');
  }
}

/// The services a worker runs on. A headless engine is its own isolate, so
/// this opens a second connection to the same database file rather than
/// sharing the one the UI holds. WAL lets both write.
Future<AppServices> createBackgroundServices() => memoraServices();
