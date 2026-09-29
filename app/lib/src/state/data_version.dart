import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'services.dart';

/// How often the UI polls `PRAGMA data_version`. Null turns polling off.
final dataPollIntervalProvider = Provider<Duration?>(
  (ref) => const Duration(milliseconds: 1500),
);

/// Counts changes to the database, including writes made by a background
/// worker. Data providers watch it so they reload when anything changes.
final dataVersionProvider = NotifierProvider<DataVersionTicker, int>(
  DataVersionTicker.new,
);

class DataVersionTicker extends Notifier<int> {
  int? _last;
  Timer? _timer;

  @override
  int build() {
    final interval = ref.watch(dataPollIntervalProvider);
    if (interval != null) {
      _timer = Timer.periodic(interval, (_) => unawaited(check()));
      ref.onDispose(() {
        _timer?.cancel();
        _timer = null;
      });
    }
    return 0;
  }

  /// Reads the version now. Call it after a write so the screen refreshes
  /// without waiting for the next poll.
  Future<void> check() async {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) return;
    final version = await ref.read(appServicesProvider).memories.dataVersion();
    if (!ref.mounted) return;
    if (_last == null) {
      _last = version;
      return;
    }
    if (version != _last) {
      _last = version;
      state = state + 1;
    }
  }
}

/// Bumped when an API key is written or removed, since secrets live outside
/// the database.
final secretsVersionProvider = NotifierProvider<SecretsVersion, int>(
  SecretsVersion.new,
);

class SecretsVersion extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state = state + 1;
}
