import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:memora_core/memora_core.dart';

import '../services/app_services.dart';

/// Every service the UI talks to. Overridden at startup in `main.dart` and in
/// tests.
final appServicesProvider = Provider<AppServices>(
  (ref) => throw UnimplementedError('appServicesProvider must be overridden'),
);

/// Wall clock for date grouping and queue timestamps. Tests pin it.
final clockProvider = Provider<Clock>((ref) => const SystemClock());
