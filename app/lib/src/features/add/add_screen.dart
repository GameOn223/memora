import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:memora_core/memora_core.dart';

import '../../routing/router.dart';
import '../../services/app_services.dart';
import '../../state/data_version.dart';
import '../../state/queue.dart';
import '../../state/services.dart';
import '../../state/ui_state.dart';
import '../../theme/memora_colors.dart';
import '../../theme/memora_icons.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../../widgets/fading_rule.dart';
import '../../widgets/memory_image.dart';
import '../../widgets/memory_labels.dart';
import '../../widgets/outline_action.dart';
import '../../widgets/screen_header.dart';
import '../../widgets/tap_area.dart';
import '../../widgets/toggle_card.dart';

/// Pick images out of the device gallery. Nothing is imported on its own.
class AddScreen extends ConsumerStatefulWidget {
  const AddScreen({super.key});

  /// How many gallery images are fetched per page.
  static const pageSize = 90;

  @override
  ConsumerState<AddScreen> createState() => _AddScreenState();
}

class _AddScreenState extends ConsumerState<AddScreen> {
  final _scroll = ScrollController();
  final _images = <DeviceImage>[];
  List<_DateGroup> _groups = const [];
  GalleryAccess? _access;
  bool _loading = false;
  bool _hasMore = true;
  bool _adding = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    unawaited(_start());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  GalleryService get _gallery => ref.read(appServicesProvider).gallery;

  Future<void> _start() async {
    try {
      final access = await _gallery.access();
      if (!mounted) return;
      setState(() => _access = access);
      if (access == GalleryAccess.full || access == GalleryAccess.partial) {
        await _loadMore();
      }
    } on Object {
      if (mounted) {
        setState(() => _error = 'The gallery could not be read.');
      }
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loading || !_hasMore) return;
    final position = _scroll.position;
    if (position.pixels > position.maxScrollExtent - 600) {
      unawaited(_loadMore());
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _gallery.list(
        offset: _images.length,
        limit: AddScreen.pageSize,
      );
      if (!mounted) return;
      setState(() {
        _images.addAll(page.images);
        _hasMore = page.hasMore;
        _groups = _groupByDay(_images, ref.read(clockProvider).now());
      });
    } on Object {
      if (mounted) {
        setState(() => _error = 'The gallery could not be read.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Groups the loaded page once, instead of on every rebuild.
  static List<_DateGroup> _groupByDay(List<DeviceImage> images, DateTime now) {
    final groups = <String, List<DeviceImage>>{};
    for (final image in images) {
      (groups[dayLabel(image.takenAt, now)] ??= []).add(image);
    }
    return [for (final e in groups.entries) _DateGroup(e.key, e.value)];
  }

  Future<void> _requestAccess() async {
    try {
      final access = _access == GalleryAccess.permanentlyDenied
          ? await _openSettings()
          : await _gallery.requestAccess();
      if (!mounted) return;
      setState(() => _access = access);
      if (access == GalleryAccess.full || access == GalleryAccess.partial) {
        await _loadMore();
      }
    } on Object {
      if (mounted) {
        setState(() => _error = 'Android would not open that setting.');
      }
    }
  }

  Future<GalleryAccess> _openSettings() async {
    await _gallery.openAppSettings();
    return _gallery.access();
  }

  Future<void> _retry() async {
    setState(() {
      _error = null;
      _hasMore = true;
    });
    await (_images.isEmpty ? _start() : _loadMore());
  }

  Future<void> _addUris(List<String> uris) async {
    if (uris.isEmpty || _adding) return;
    setState(() {
      _adding = true;
      _error = null;
    });
    AddImagesResult? result;
    try {
      result = await _gallery.addToMemora(uris);
    } on Object {
      if (mounted) {
        setState(() => _error = 'Those images could not be added.');
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
    if (!mounted || result == null) return;
    // Images are filed either way. Ask the pipeline whether anything will
    // read them, so the toast can say so instead of leaving them to sit in
    // a queue that cannot move.
    QueueBlock? block;
    try {
      block = await ref.read(appServicesProvider).pipeline.currentBlock();
    } on Object {
      // The add still happened. Report it without the reason.
    }
    if (!mounted) return;
    ref.read(gallerySelectionProvider.notifier).clear();
    ref.read(addedToastProvider.notifier).show(result, block: block);
    await ref.read(dataVersionProvider.notifier).check();
    if (mounted) context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final denied =
        _access == GalleryAccess.denied ||
        _access == GalleryAccess.permanentlyDenied;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final blocked = _error != null && _images.isEmpty;

    return ColoredBox(
      color: c.bg,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ScreenHeader(
                title: 'Add from gallery',
                leading: HeaderLeading.close,
                onLeading: () => context.go(Routes.home),
                trailing: [
                  if (!denied && !blocked)
                    _SelectAllButton(
                      uris: [for (final image in _images) image.uri],
                    ),
                ],
              ),
              const FadingRule(),
              Expanded(
                child: switch ((denied, blocked)) {
                  (true, _) => _PermissionPanel(
                    permanent: _access == GalleryAccess.permanentlyDenied,
                    onAllow: _requestAccess,
                    onPicker: () => unawaited(_pickWithSystemPicker()),
                  ),
                  (_, true) => _FailurePanel(
                    message: _error!,
                    onRetry: () => unawaited(_retry()),
                    onPicker: () => unawaited(_pickWithSystemPicker()),
                  ),
                  _ => _GalleryGrid(
                    controller: _scroll,
                    groups: _groups,
                    partial: _access == GalleryAccess.partial,
                    onChooseMore: _requestAccess,
                  ),
                },
              ),
            ],
          ),
          if (!blocked)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // A fixed fade, then solid background, so the row behind
                  // never shows through the buttons.
                  SizedBox(
                    height: Space.s8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [c.bg, c.bg.withValues(alpha: 0)],
                        ),
                      ),
                    ),
                  ),
                  ColoredBox(
                    color: c.bg,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        Space.s4,
                        0,
                        Space.s4,
                        Space.s6 + bottomInset,
                      ),
                      child: _AddBar(
                        adding: _adding,
                        error: _images.isEmpty ? null : _error,
                        onAdd: (uris) => unawaited(_addUris(uris)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickWithSystemPicker() async {
    try {
      final uris = await _gallery.pickWithSystemPicker();
      await _addUris(uris);
    } on Object {
      if (mounted) {
        setState(() => _error = 'The system picker could not be opened.');
      }
    }
  }
}

/// One day of gallery images.
class _DateGroup {
  const _DateGroup(this.label, this.images);

  final String label;
  final List<DeviceImage> images;
}

/// Ticks or clears every loaded image. Watches the selection on its own, so
/// the grid doesn't rebuild with it.
class _SelectAllButton extends ConsumerWidget {
  const _SelectAllButton({required this.uris});

  final List<String> uris;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final count = ref.watch(gallerySelectionProvider.select((s) => s.length));
    final allSelected = uris.isNotEmpty && count == uris.length;
    return TapArea(
      onTap: () {
        final notifier = ref.read(gallerySelectionProvider.notifier);
        if (allSelected) {
          notifier.clear();
        } else {
          notifier.selectAll(uris);
        }
      },
      semanticLabel: allSelected ? 'Clear selection' : 'Select all images',
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s2,
          vertical: Space.s3,
        ),
        child: Text(
          allSelected ? 'Clear' : 'Select all',
          style: MemoraText.style(12, medium: true, color: c.accentInk),
        ),
      ),
    );
  }
}

/// The overnight card and the add button. Watches the selection so the grid
/// above it doesn't have to.
class _AddBar extends ConsumerWidget {
  const _AddBar({
    required this.adding,
    required this.error,
    required this.onAdd,
  });

  final bool adding;
  final String? error;
  final ValueChanged<List<String>> onAdd;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final selection = ref.watch(gallerySelectionProvider);
    final policy = ref.watch(queuePolicyProvider).value ?? const QueuePolicy();
    final overnight = policy.mode == QueueMode.overnight;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (error != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: Space.s2),
            child: Text(
              error!,
              style: MemoraText.style(12.5, color: c.accentInk),
            ),
          ),
        ],
        ToggleCard.compact(
          value: overnight,
          icon: MemoraIcons.moonStars,
          body: overnight
              ? 'Queued for tonight, while charging'
              : 'Process now, as you add them',
          onChanged: (value) => unawaited(
            ref
                .read(queuePolicyProvider.notifier)
                .setMode(value ? QueueMode.overnight : QueueMode.immediate),
          ),
        ),
        const SizedBox(height: Space.s2),
        OutlineAction(
          label: adding
              ? 'Adding…'
              : selection.isEmpty
              ? 'Select images to add'
              : 'Add ${imageCount(selection.length)}',
          icon: MemoraIcons.images,
          height: 46,
          tone: selection.isEmpty ? ActionTone.disabled : ActionTone.accent,
          onPressed: selection.isEmpty || adding
              ? null
              : () => onAdd(selection.toList()),
        ),
      ],
    );
  }
}

class _GalleryGrid extends StatelessWidget {
  const _GalleryGrid({
    required this.controller,
    required this.groups,
    required this.partial,
    required this.onChooseMore,
  });

  final ScrollController controller;
  final List<_DateGroup> groups;
  final bool partial;
  final VoidCallback onChooseMore;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CustomScrollView(
      controller: controller,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            Space.s6,
            Space.s4,
            Space.s6,
            128 + MediaQuery.paddingOf(context).bottom,
          ),
          sliver: SliverMainAxisGroup(
            slivers: [
              if (partial)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: Space.s4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Memora can only see the images you allowed.',
                            style: MemoraText.style(12, color: c.muted),
                          ),
                        ),
                        const SizedBox(width: Space.s3),
                        OutlineAction(
                          label: 'Choose more',
                          onPressed: onChooseMore,
                          height: 32,
                          fontSize: 12,
                          expand: false,
                          horizontalPadding: Space.s4,
                        ),
                      ],
                    ),
                  ),
                ),
              for (final group in groups)
                SliverMainAxisGroup(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: Space.s3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Flexible(
                              child: Text(
                                group.label.toUpperCase(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: MemoraText.caps(
                                  11,
                                  spacing: 1.2,
                                  color: c.text,
                                ),
                              ),
                            ),
                            const SizedBox(width: Space.s3),
                            Expanded(
                              child: Container(
                                height: 1,
                                margin: const EdgeInsets.only(bottom: 3),
                                color: c.lineSoft,
                              ),
                            ),
                            const SizedBox(width: Space.s3),
                            Text(
                              imageCount(group.images.length),
                              style: MemoraText.caps(
                                9.5,
                                spacing: 0.8,
                                tabular: true,
                                color: c.dim,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.only(bottom: Space.s6),
                      sliver: SliverGrid(
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              mainAxisSpacing: Space.s2,
                              crossAxisSpacing: Space.s2,
                              childAspectRatio: 3 / 4,
                            ),
                        delegate: SliverChildBuilderDelegate(
                          (context, i) => _GalleryCell(image: group.images[i]),
                          childCount: group.images.length,
                          findChildIndexCallback: (key) {
                            final uri = (key as ValueKey<String>).value;
                            final index = group.images.indexWhere(
                              (image) => image.uri == uri,
                            );
                            return index < 0 ? null : index;
                          },
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GalleryCell extends ConsumerWidget {
  _GalleryCell({required this.image}) : super(key: ValueKey(image.uri));

  final DeviceImage image;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    // Watching one entry keeps a tap from rebuilding every other cell.
    final selected = ref.watch(
      gallerySelectionProvider.select((s) => s.contains(image.uri)),
    );
    final taken = dayLabel(image.takenAt, ref.watch(clockProvider).now());
    return TapArea(
      onTap: () =>
          ref.read(gallerySelectionProvider.notifier).toggle(image.uri),
      semanticLabel: 'Image from $taken',
      selected: selected,
      minSize: 0,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Radii.sm),
          border: Border.all(color: selected ? c.accent : c.lineSoft),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            DeviceImageView(uri: image.uri),
            if (selected)
              DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: MemoraColors.selectionVeil,
                  ),
                ),
              ),
            Positioned(
              top: 5,
              right: 5,
              child: Container(
                width: 17,
                height: 17,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  // A little scrim keeps the empty circle readable on top
                  // of a bright screenshot.
                  color: selected ? c.accent : c.scrim.withValues(alpha: 0.45),
                  border: Border.all(color: selected ? c.accent : c.muted),
                ),
                child: selected
                    ? Icon(MemoraIconsFill.check, size: 9, color: c.bg)
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionPanel extends StatelessWidget {
  const _PermissionPanel({
    required this.permanent,
    required this.onAllow,
    required this.onPicker,
  });

  final bool permanent;
  final VoidCallback onAllow;
  final VoidCallback onPicker;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.s6, Space.s8, Space.s6, 160),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.accentTint,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: c.accentLine),
            ),
            child: Icon(MemoraIcons.images, size: 22, color: c.accent),
          ),
          const SizedBox(height: Space.s6),
          Text(
            'Memora needs your permission to read images.',
            style: MemoraText.style(
              20,
              medium: true,
              height: 1.3,
              spacing: -0.4,
              color: c.text,
            ),
          ),
          const SizedBox(height: Space.s4),
          Text(
            permanent
                ? 'Photo access is switched off for Memora. Turn it on in '
                      'Android settings, or pick images one batch at a time '
                      'with the system picker.'
                : 'Memora reads the images you pick and nothing else. You '
                      'can also use the system picker, which needs no '
                      'permission at all.',
            style: MemoraText.style(13.5, height: 1.6, color: c.muted),
          ),
          const SizedBox(height: Space.s8),
          OutlineAction(
            label: permanent ? 'Open Android settings' : 'Allow access',
            onPressed: onAllow,
          ),
          const SizedBox(height: Space.s2),
          OutlineAction(
            label: 'Pick with system picker',
            tone: ActionTone.neutral,
            onPressed: onPicker,
          ),
        ],
      ),
    );
  }
}

/// Shown when the gallery itself could not be read.
class _FailurePanel extends StatelessWidget {
  const _FailurePanel({
    required this.message,
    required this.onRetry,
    required this.onPicker,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onPicker;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(Space.s6, Space.s8, Space.s6, 160),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.surface2,
              borderRadius: BorderRadius.circular(Radii.md),
              border: Border.all(color: c.accentLine),
            ),
            child: Icon(MemoraIcons.warningCircle, size: 22, color: c.accent),
          ),
          const SizedBox(height: Space.s6),
          Text(
            message,
            style: MemoraText.style(
              20,
              medium: true,
              height: 1.3,
              spacing: -0.4,
              color: c.text,
            ),
          ),
          const SizedBox(height: Space.s4),
          Text(
            'Nothing was added. Try again, or pick images with the system '
            'picker instead.',
            style: MemoraText.style(13.5, height: 1.6, color: c.muted),
          ),
          const SizedBox(height: Space.s8),
          OutlineAction(label: 'Try again', onPressed: onRetry),
          const SizedBox(height: Space.s2),
          OutlineAction(
            label: 'Pick with system picker',
            tone: ActionTone.neutral,
            onPressed: onPicker,
          ),
        ],
      ),
    );
  }
}
