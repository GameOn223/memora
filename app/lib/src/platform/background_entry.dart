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
Future<void> runBackground(
  BackgroundServicesFactory create, {
  BackgroundHostApi? host,
  BinaryMessenger? binaryMessenger,
}) async {
  final services = await create();
  BackgroundFlutterApi.setUp(
    BackgroundCallHandler(services),
    binaryMessenger: binaryMessenger,
  );
  await (host ?? BackgroundHostApi(binaryMessenger: binaryMessenger))
      .backgroundReady();
}

/// Maps worker calls onto app services.
class BackgroundCallHandler implements BackgroundFlutterApi {
  BackgroundCallHandler(this._services);

  final AppServices _services;

  @override
  Future<int> ingestInbox() => _services.capture.ingestInbox();

  @override
  Future<RunResult> runQueue(int budgetMillis, bool processNow) async {
    final report = await _services.pipeline.runQueue(
      budget: Duration(milliseconds: budgetMillis),
      processNow: processNow,
    );
    return RunResult(processed: report.processed, remaining: report.remaining);
  }

  @override
  Future<int> reindexEmbeddings(int budgetMillis) => _services.pipeline
      .reindexEmbeddings(budget: Duration(milliseconds: budgetMillis));
}
