import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/bootstrap/inbox_drain.dart';
import 'package:memora/src/services/app_services.dart';

import '../platform/fakes.dart';

/// A capture service that counts drains and can be held open or made to fail.
class FakeCapture implements CaptureService {
  FakeCapture({this.added = 0, this.fail = false});

  int added;
  bool fail;
  int drains = 0;
  Completer<void>? gate;

  @override
  Future<int> ingestInbox() async {
    drains++;
    if (gate != null) await gate!.future;
    if (fail) throw StateError('the inbox could not be read');
    return added;
  }

  @override
  Future<CaptureSetup> setup() => throw UnimplementedError();

  @override
  Future<void> openAccessibilitySettings() => throw UnimplementedError();

  @override
  Future<bool> requestAddTile() => throw UnimplementedError();

  @override
  Future<bool> requestNotificationPermission() => throw UnimplementedError();
}

void main() {
  late FakeCapture capture;
  late FakeScheduler scheduler;
  late ForegroundInboxDrain drain;

  setUp(() {
    capture = FakeCapture(added: 2);
    scheduler = FakeScheduler();
    drain = ForegroundInboxDrain(capture: capture, scheduler: scheduler);
  });

  test('files the inbox and then refreshes the schedule', () async {
    await drain.drain();

    expect(capture.drains, 1);
    expect(scheduler.refreshes, 1);
  });

  test('an empty inbox still lines the schedule up with the queue', () async {
    capture.added = 0;
    await drain.drain();

    expect(capture.drains, 1);
    expect(scheduler.refreshes, 1);
  });

  test('a burst of resumes joins the pass already running', () async {
    capture.gate = Completer<void>();
    final passes = [drain.drain(), drain.drain(), drain.drain()];
    capture.gate!.complete();
    await Future.wait(passes);

    expect(capture.drains, 1);
    expect(scheduler.refreshes, 1);

    // The next resume starts a fresh pass.
    capture.gate = null;
    await drain.drain();
    expect(capture.drains, 2);
  });

  test('an inbox that cannot be read leaves the app running', () async {
    capture.fail = true;

    await expectLater(drain.drain(), completes);
    expect(scheduler.refreshes, 1, reason: 'the queue may still have work');

    // And the failure does not wedge the guard against the next pass.
    capture.fail = false;
    await drain.drain();
    expect(capture.drains, 2);
    expect(scheduler.refreshes, 2);
  });
}
