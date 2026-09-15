import 'package:memora_core/memora_core.dart';

import 'fake_conversation_store.dart';
import 'fake_memora_state.dart';
import 'fake_memory_store.dart';
import 'fake_queue_store.dart';
import 'fake_search_store.dart';
import 'fake_vector_store.dart';

export 'fake_memora_state.dart' show MemoryRow, vectorKey;

/// One in-memory database implementing every storage port except settings
/// and secrets. Pass the same instance wherever a store is needed.
class FakeMemora extends FakeMemoraState
    with
        FakeMemoryStore,
        FakeQueueStore,
        FakeSearchStore,
        FakeVectorStore,
        FakeConversationStore {}

StoredEntity entity(String value, {String type = 'company'}) => StoredEntity(
  type: type,
  value: value,
  normalizedValue: foldForMatch(value),
);

StoredAttribute amount(
  double value, {
  String currency = 'INR',
  String label = 'total',
}) => StoredAttribute(
  type: 'amount',
  value: formatMoney(value, currency),
  valueNum: value,
  currency: currency,
  label: label,
);

StoredAttribute dateAttribute(String type, String iso) => StoredAttribute(
  type: type,
  value: displayDate(parseIsoDate(iso)!),
  valueDate: iso,
);

StoredAttribute textAttribute(String type, String value) =>
    StoredAttribute(type: type, value: value);
