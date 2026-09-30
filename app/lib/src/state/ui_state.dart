import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/app_services.dart';

/// Category filter chosen on the home screen, by chip label.
final homeFilterProvider = NotifierProvider<HomeFilter, String>(HomeFilter.new);

class HomeFilter extends Notifier<String> {
  @override
  String build() => 'All';

  void select(String label) => state = label;
}

/// Result of the last add, shown as a toast on home until it is cleared.
final addedToastProvider = NotifierProvider<AddedToastState, AddImagesResult?>(
  AddedToastState.new,
);

class AddedToastState extends Notifier<AddImagesResult?> {
  @override
  AddImagesResult? build() => null;

  void show(AddImagesResult result) => state = result;

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
