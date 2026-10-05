/// The composition root.
///
/// Both entrypoints come through here: `main.dart` for the UI and
/// `background_main.dart` for the engine a WorkManager worker starts. Each
/// runs in its own isolate with its own copy of this library, so each builds
/// one set of services and one database connection, and callers inside an
/// isolate share it.
library;

import '../services/app_services.dart';
import 'app_services_impl.dart';

Future<MemoraAppServices>? _services;

/// The services for this isolate, built on first use.
///
/// A build that fails is not cached, so a later call can try again rather
/// than handing out the same error forever.
Future<AppServices> memoraServices() =>
    _services ??= MemoraAppServices.open().onError<Object>((error, stack) {
      _services = null;
      Error.throwWithStackTrace(error, stack);
    });

/// Closes the services this isolate built. Does nothing when there are none.
Future<void> disposeMemoraServices() async {
  final pending = _services;
  _services = null;
  if (pending == null) return;
  final MemoraAppServices services;
  try {
    services = await pending;
  } on Object {
    // The build failed, so nothing was opened and nothing needs closing.
    return;
  }
  await services.dispose();
}
