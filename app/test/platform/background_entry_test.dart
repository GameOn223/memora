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
