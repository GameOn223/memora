import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/app_services.dart';
import 'messages.g.dart';

/// Builds the services a background worker needs. The composition root
/// provides one that opens the database and wires real providers.
typedef BackgroundServicesFactory = Future<AppServices> Function();

/// Starts serving [BackgroundFlutterApi] calls on the headless engine.
///
/// Android workers start an engine on `backgroundMain`, wait for
/// [BackgroundHostApi.backgroundReady], then call one method and destroy the
/// engine when it returns. Services are built before readiness is signalled,
/// so a call never arrives before there is something to handle it.
///
/// [onFinished] runs once that call is done, before the worker is answered.
/// Destroying an engine does not close a database connection or an HTTP
/// client the isolate opened, so whoever built them closes them here.
Future<void> runBackground(
  BackgroundServicesFactory create, {
  BackgroundHostApi? host,
  BinaryMessenger? binaryMessenger,
  Future<void> Function()? onFinished,
}) async {
  final services = await create();
  BackgroundFlutterApi.setUp(
    BackgroundCallHandler(services, onFinished: onFinished),
    binaryMessenger: binaryMessenger,
  );
  await (host ?? BackgroundHostApi(binaryMessenger: binaryMessenger))
      .backgroundReady();
}

/// Maps worker calls onto app services.
class BackgroundCallHandler implements BackgroundFlutterApi {
  BackgroundCallHandler(this._services, {this.onFinished});

  final AppServices _services;

  /// Runs after the worker's call, to close what the isolate opened.
  final Future<void> Function()? onFinished;

  @override
  Future<int> ingestInbox() => _finish(_services.capture.ingestInbox());

  @override
  Future<RunResult> runQueue(int budgetMillis, bool processNow) {
    return _finish(() async {
      final report = await _services.pipeline.runQueue(
        budget: Duration(milliseconds: budgetMillis),
        processNow: processNow,
      );
      return RunResult(
        processed: report.processed,
        remaining: report.remaining,
      );
    }());
  }

  @override
  Future<int> reindexEmbeddings(int budgetMillis) => _finish(
    _services.pipeline.reindexEmbeddings(
      budget: Duration(milliseconds: budgetMillis),
    ),
  );

  /// Runs the worker's call, then closes whatever the isolate opened. The
  /// worker still gets its result if the cleanup fails, since the engine is
  /// about to be destroyed either way.
  Future<T> _finish<T>(Future<T> work) async {
    try {
      return await work;
    } finally {
      try {
        await onFinished?.call();
      } catch (error) {
        debugPrint('Memora could not close its background services: $error');
      }
    }
  }
}
