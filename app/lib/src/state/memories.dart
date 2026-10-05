import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:memora_core/memora_core.dart';

import '../widgets/memory_labels.dart';
import 'data_version.dart';
import 'services.dart';

/// Filters for a memory list, with value equality so it can key a family.
@immutable
class MemoryFilter {
  const MemoryFilter({
    this.sort = MemorySort.newest,
    this.categories = const {},
    this.statuses = const {},
    this.takenBetween,
    this.limit = 500,
  });

  final MemorySort sort;
  final Set<String> categories;
  final Set<ProcessingStatus> statuses;
  final DateRange? takenBetween;
  final int limit;

  MemoryListQuery toQuery() => MemoryListQuery(
    sort: sort,
    categories: categories,
    statuses: statuses,
    takenBetween: takenBetween,
    limit: limit,
  );

  MemoryFilter copyWith({
    MemorySort? sort,
    Set<String>? categories,
    Set<ProcessingStatus>? statuses,
    DateRange? takenBetween,
    bool clearTakenBetween = false,
  }) => MemoryFilter(
    sort: sort ?? this.sort,
    categories: categories ?? this.categories,
    statuses: statuses ?? this.statuses,
    takenBetween: clearTakenBetween ? null : takenBetween ?? this.takenBetween,
    limit: limit,
  );

  @override
  bool operator ==(Object other) =>
      other is MemoryFilter &&
      other.sort == sort &&
      setEquals(other.categories, categories) &&
      setEquals(other.statuses, statuses) &&
      other.takenBetween == takenBetween &&
      other.limit == limit;

  @override
  int get hashCode => Object.hash(
    sort,
    Object.hashAllUnordered(categories),
    Object.hashAllUnordered(statuses),
    takenBetween,
    limit,
  );
}

final memoriesProvider = FutureProvider.family<List<Memory>, MemoryFilter>((
  ref,
  filter,
) async {
  ref.watch(dataVersionProvider);
  final services = ref.watch(appServicesProvider);
  return services.memories.listMemories(filter.toQuery());
});

/// Everything, newest taken first.
final allMemoriesProvider = FutureProvider<List<Memory>>((ref) async {
  return ref.watch(memoriesProvider(const MemoryFilter()).future);
});

final storageStatsProvider = FutureProvider<StorageStats>((ref) async {
  ref.watch(dataVersionProvider);
  return ref.watch(appServicesProvider).memories.storageStats();
});

/// True once there is at least one memory, for the empty state.
final hasMemoriesProvider = Provider<bool>((ref) {
  final stats = ref.watch(storageStatsProvider);
  return (stats.value?.memoryCount ?? 0) > 0;
});

final memoryDetailsProvider = FutureProvider.family<MemoryDetails?, String>((
  ref,
  id,
) async {
  ref.watch(dataVersionProvider);
  return ref.watch(appServicesProvider).memories.getDetails(id);
});

/// The facts line under a tile, such as `₹1,842 · due 30 Sep`.
final memoryFactProvider = FutureProvider.family<String?, String>((
  ref,
  id,
) async {
  final details = await ref.watch(memoryDetailsProvider(id).future);
  return details == null ? null : keyFact(details);
});

/// A filter chip on the home screen.
@immutable
class CategoryOption {
  const CategoryOption({
    required this.label,
    required this.categories,
    required this.count,
  });

  final String label;

  /// Raw categories the label stands for. Empty means everything.
  final Set<String> categories;
  final int count;
}

/// Raw categories grouped under the labels the design uses.
const categoryGroups = <String, Set<String>>{
  'Bills': {'utility_bill', 'receipt', 'invoice'},
  'Places': {'place', 'map'},
  'Work': {'reference', 'document', 'code'},
  'Shopping': {'comparison', 'product'},
  'Travel': {'booking', 'ticket'},
};

final categoryOptionsProvider = FutureProvider<List<CategoryOption>>((
  ref,
) async {
  ref.watch(dataVersionProvider);
  final counts = await ref.watch(appServicesProvider).memories.categoryCounts();
  return buildCategoryOptions(counts);
});

/// `All` first, then the design's labels that have memories, then any
/// category that doesn't fit a label, most common first.
List<CategoryOption> buildCategoryOptions(List<FacetCount> counts) {
  final byCategory = {for (final c in counts) c.value: c.count};
  final total = counts.fold(0, (sum, c) => sum + c.count);
  final options = <CategoryOption>[
    CategoryOption(label: 'All', categories: const {}, count: total),
  ];
  final used = <String>{};
  for (final group in categoryGroups.entries) {
    final present = group.value.where(byCategory.containsKey).toSet();
    if (present.isEmpty) continue;
    used.addAll(present);
    options.add(
      CategoryOption(
        label: group.key,
        categories: present,
        count: present.fold(0, (sum, c) => sum + byCategory[c]!),
      ),
    );
  }
  final extras = [
    for (final c in counts)
      if (!used.contains(c.value)) c,
  ]..sort((a, b) => b.count.compareTo(a.count));
  for (final extra in extras.take(4)) {
    options.add(
      CategoryOption(
        label: sentenceCase(extra.value),
        categories: {extra.value},
        count: extra.count,
      ),
    );
  }
  return options;
}

/// Memories grouped under `Today`, `Yesterday` or `12 September 2026`.
@immutable
class DateGroup {
  const DateGroup(this.label, this.items);

  final String label;
  final List<Memory> items;
}

List<DateGroup> groupByTakenDate(List<Memory> memories, DateTime now) {
  final groups = <String, List<Memory>>{};
  for (final memory in memories) {
    (groups[dayLabel(memory.takenAt, now)] ??= []).add(memory);
  }
  return [for (final e in groups.entries) DateGroup(e.key, e.value)];
}
