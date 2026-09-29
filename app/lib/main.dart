import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/demo/demo_app_services.dart';
import 'src/routing/memora_app.dart';
import 'src/services/app_services.dart';
import 'src/state/services.dart';

export 'src/routing/memora_app.dart' show MemoraApp;

/// Until the composition root lands, the app runs on in-memory demo data.
/// Build with `--dart-define=MEMORA_DEMO=false` once bootstrap is wired.
const useDemoServices = bool.fromEnvironment('MEMORA_DEMO', defaultValue: true);

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  LicenseRegistry.addLicense(_interLicense);
  runApp(
    ProviderScope(
      overrides: [appServicesProvider.overrideWithValue(_services())],
      child: const MemoraApp(),
    ),
  );
}

AppServices _services() {
  if (useDemoServices) return DemoAppServices();
  throw UnsupportedError(
    'Real services are built by the composition root in lib/src/bootstrap, '
    'which arrives with integration. Run with MEMORA_DEMO=true until then.',
  );
}

Stream<LicenseEntry> _interLicense() async* {
  final text = await rootBundle.loadString('assets/fonts/OFL.txt');
  yield LicenseEntryWithLineBreaks(['Inter'], text);
}
