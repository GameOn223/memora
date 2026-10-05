import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memora/src/platform/background_entry.dart';
import 'package:memora/src/platform/messages.g.dart';
import 'package:memora/src/services/app_services.dart';
import 'package:memora_core/memora_core.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('builds services before signalling readiness', () async {
    final events = <String>[];
    final host = _FakeBackgroundHost(events);

    await runBackground(() async {
      events.add('create');
      return _FakeServices();
    }, host: host);

    expect(events, ['create', 'ready']);
    BackgroundFlutterApi.setUp(null);
  });

  test('maps worker calls onto services', () async {
    final services = _FakeServices();
    final handler = BackgroundCallHandler(services);

    expect(await handler.ingestInbox(), 3);

    final run = await handler.runQueue(540000, true);
    expect(run.processed, 7);
    expect(run.remaining, isTrue);
    expect(services.pipeline.budgets, [const Duration(minutes: 9)]);
    expect(services.pipeline.processNowFlags, [true]);

    expect(await handler.reindexEmbeddings(60000), 12);
    expect(services.pipeline.budgets.last, const Duration(minutes: 1));
  });

  test('closes what the isolate opened once the call is done', () async {
    var closed = 0;
    final handler = BackgroundCallHandler(
      _FakeServices(),
      onFinished: () async => closed++,
    );

    expect(await handler.ingestInbox(), 3);
    expect(closed, 1);
    await handler.runQueue(540000, false);
    expect(closed, 2);
    await handler.reindexEmbeddings(60000);
    expect(closed, 3);
  });

  test('the worker still gets its result if the cleanup fails', () async {
    final handler = BackgroundCallHandler(
      _FakeServices(),
      onFinished: () async => throw StateError('the database was busy'),
    );

    expect(await handler.ingestInbox(), 3);
  });

  group('the headless entrypoint stays in the build', () {
    test('background_main.dart keeps the entry-point pragma', () {
      final source = File('lib/background_main.dart').readAsStringSync();

      expect(source, contains("@pragma('vm:entry-point')"));
      expect(source, contains('Future<void> backgroundMain()'));
    });

    test('main.dart references the library so AOT compiles it', () {
      final source = File('lib/main.dart').readAsStringSync();

      // Without this, release builds drop the library and WorkManager can't
      // start the entrypoint. See docs/architecture.md, section 10.
      expect(
        source,
        anyOf(
          contains("export 'background_main.dart'"),
          contains("import 'background_main.dart'"),
        ),
        reason: 'main.dart must reference lib/background_main.dart',
      );
      expect(source, contains('backgroundMain'));
    });

    test('the Kotlin runner points at the same library and function', () {
      final runner = File(
        'android/app/src/main/kotlin/io/github/gameon223/memora/'
        'background/HeadlessEngineRunner.kt',
      ).readAsStringSync();

      expect(runner, contains('package:memora/background_main.dart'));
      expect(runner, contains('"backgroundMain"'));
    });
  });
}

class _FakeBackgroundHost extends BackgroundHostApi {
  _FakeBackgroundHost(this.events);

  final List<String> events;

  @override
  Future<void> backgroundReady() async => events.add('ready');
}

class _FakeServices implements AppServices {
  @override
  final _FakeCapture capture = _FakeCapture();

  @override
  final _FakePipeline pipeline = _FakePipeline();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeCapture implements CaptureService {
  @override
  Future<int> ingestInbox() async => 3;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePipeline implements ProcessingPipeline {
  final budgets = <Duration>[];
  final processNowFlags = <bool>[];

  @override
  Future<QueueRunReport> runQueue({
    required Duration budget,
    bool processNow = false,
  }) async {
    budgets.add(budget);
    processNowFlags.add(processNow);
    return const QueueRunReport(processed: 7, remaining: true);
  }

  @override
  Future<int> reindexEmbeddings({required Duration budget}) async {
    budgets.add(budget);
    return 12;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
