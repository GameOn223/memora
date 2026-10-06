import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:memora_core/memora_core.dart';

import '../services/app_services.dart';

/// Label of the everything option, which cannot be combined with others.
const allCategoriesLabel = 'All';

/// Category filter chosen on the home screen, by chip label.
final homeFilterProvider = NotifierProvider<HomeFilter, Set<String>>(
  HomeFilter.new,
);

/// Which category labels the memories grid is narrowed to.
///
/// Empty means everything, which is what the `All` chip stands for. Several
/// labels are a union: Bills and Travel shows both, not the memories that
/// are somehow in each at once.
class HomeFilter extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  /// Narrows to just [label], or back to everything for `All`.
  void select(String label) =>
      state = label == allCategoriesLabel ? const {} : {label};

  /// Adds or drops [label] and leaves the rest alone.
  void toggle(String label) {
    if (label == allCategoriesLabel) {
      state = const {};
      return;
    }
    state = state.contains(label)
        ? ({...state}..remove(label))
        : {...state, label};
  }

  /// Takes a whole selection, as the picker hands one over.
  ///
  /// `All` in the set means everything, so it wins and the rest goes. This
  /// is deliberately statements and not an expression: written as a ternary
  /// with a cascade, the cascade binds to the whole ternary and tries to
  /// remove from the const empty set.
  void replace(Set<String> labels) {
    if (labels.contains(allCategoriesLabel)) {
      state = const {};
      return;
    }
    state = {...labels};
  }
}

/// What the last add produced: the counts, and the reason nothing will be
/// understood when something is blocking the queue.
@immutable
class AddedOutcome {
  const AddedOutcome(this.result, {this.block});

  final AddImagesResult result;

  /// Read once, right after the images were filed.
  final QueueBlock? block;
}

/// Result of the last add, shown as a toast on home until it is cleared.
final addedToastProvider = NotifierProvider<AddedToastState, AddedOutcome?>(
  AddedToastState.new,
);

class AddedToastState extends Notifier<AddedOutcome?> {
  @override
  AddedOutcome? build() => null;

  void show(AddImagesResult result, {QueueBlock? block}) =>
      state = AddedOutcome(result, block: block);

  void clear() => state = null;
}

/// Gallery images ticked on the Add screen, by content uri.
final gallerySelectionProvider =
    NotifierProvider<GallerySelection, Set<String>>(GallerySelection.new);

class GallerySelection extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void toggle(String uri) {
    final next = {...state};
    if (!next.remove(uri)) next.add(uri);
    state = next;
  }

  void selectAll(Iterable<String> uris) => state = {...uris};

  void clear() => state = const {};
}
