import 'dart:async';

import 'package:flutter/widgets.dart';

import '../services/app_services.dart';

/// Files tile captures and shared images that arrived while Memora was in the
/// background, then lines the native schedule up with what is now queued.
///
/// Kotlin writes those images into `files/inbox/` because it can't safely
/// write to the database, and a worker drains the inbox when the app is
/// closed. This is the other half, for when the app is open. See
/// docs/architecture.md, section 4.2.
class ForegroundInboxDrain {
  ForegroundInboxDrain({required this.capture, required this.scheduler});

  final CaptureService capture;
  final QueueScheduler scheduler;

  AppLifecycleListener? _listener;
  Future<void>? _running;

  /// Drains once now and again every time the app returns to the foreground.
  void start() {
    _listener ??= AppLifecycleListener(onResume: () => unawaited(drain()));
    unawaited(drain());
  }

  /// One pass. A call made while a pass is running joins that pass instead of
  /// starting a second one, since resume events arrive in bursts.
  Future<void> drain() =>
      _running ??= _drain().whenComplete(() => _running = null);

  Future<void> _drain() async {
    try {
      await capture.ingestInbox();
    } catch (error, stack) {
      // A capture that can't be filed now is offered again by the next
      // drain, so the app carries on and the schedule is still refreshed.
      debugPrint('Memora could not drain the inbox: $error');
      debugPrintStack(stackTrace: stack);
    }
    try {
      await scheduler.refresh();
    } catch (error, stack) {
      debugPrint('Memora could not refresh the queue schedule: $error');
      debugPrintStack(stackTrace: stack);
    }
  }

  /// Stops listening for foreground events.
  void dispose() {
    _listener?.dispose();
    _listener = null;
  }
}
