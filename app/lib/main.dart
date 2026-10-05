import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/bootstrap/bootstrap.dart';
import 'src/bootstrap/inbox_drain.dart';
import 'src/demo/demo_app_services.dart';
import 'src/routing/memora_app.dart';
import 'src/services/app_services.dart';
import 'src/state/services.dart';
import 'src/theme/memora_theme.dart';

// Keeps the headless entrypoint in the build. A release build drops any
// library main.dart can't reach, and WorkManager could then not start
// backgroundMain. Do not remove this line.
export 'background_main.dart' show backgroundMain;
export 'src/routing/memora_app.dart' show MemoraApp;

/// Runs the UI on in-memory demo data instead of the device, so the screens
/// can be worked on without a phone. Build with
/// `--dart-define=MEMORA_DEMO=true`.
const useDemoServices = bool.fromEnvironment('MEMORA_DEMO');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  LicenseRegistry.addLicense(_interLicense);

  final AppServices services;
  try {
    services = await _services();
  } catch (error, stack) {
    debugPrint('Memora could not start: $error');
    debugPrintStack(stackTrace: stack);
    runApp(const _StartupFailure());
    return;
  }

  // Files anything the tile or the share sheet left behind, and lines the
  // native schedule up with the queue. Both happen again on every resume.
  // The listener registers with the binding, which keeps it alive.
  ForegroundInboxDrain(
    capture: services.capture,
    scheduler: services.scheduler,
  ).start();

  runApp(
    ProviderScope(
      overrides: [appServicesProvider.overrideWithValue(services)],
      child: const MemoraApp(),
    ),
  );
}

Future<AppServices> _services() async =>
    useDemoServices ? DemoAppServices() : await memoraServices();

/// Shown when the database can't be opened. The memories are still on the
/// device, so the only thing to do is try again.
class _StartupFailure extends StatelessWidget {
  const _StartupFailure();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Memora',
      debugShowCheckedModeBanner: false,
      theme: MemoraTheme.light(),
      darkTheme: MemoraTheme.dark(),
      home: const Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Text(
              'Memora could not open its library.\n'
              'Your memories are still on this device. '
              'Close the app and open it again.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

Stream<LicenseEntry> _interLicense() async* {
  final text = await rootBundle.loadString('assets/fonts/OFL.txt');
  yield LicenseEntryWithLineBreaks(['Inter'], text);
}
