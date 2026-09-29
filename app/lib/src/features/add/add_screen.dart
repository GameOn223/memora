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
  GalleryAccess? _access;
  bool _loading = false;
  bool _hasMore = true;
  bool _adding = false;

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
    final access = await _gallery.access();
    if (!mounted) return;
    setState(() => _access = access);
    if (access == GalleryAccess.full || access == GalleryAccess.partial) {
      await _loadMore();
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
    setState(() => _loading = true);
    final page = await _gallery.list(
      offset: _images.length,
      limit: AddScreen.pageSize,
    );
    if (!mounted) return;
    setState(() {
      _images.addAll(page.images);
      _hasMore = page.hasMore;
      _loading = false;
    });
  }

  Future<void> _requestAccess() async {
    final access = _access == GalleryAccess.permanentlyDenied
        ? await _openSettings()
        : await _gallery.requestAccess();
    if (!mounted) return;
    setState(() => _access = access);
    if (access == GalleryAccess.full || access == GalleryAccess.partial) {
      await _loadMore();
    }
  }

  Future<GalleryAccess> _openSettings() async {
    await _gallery.openAppSettings();
    return _gallery.access();
  }

  Future<void> _addUris(List<String> uris) async {
    if (uris.isEmpty || _adding) return;
    setState(() => _adding = true);
    final result = await _gallery.addToMemora(uris);
    if (!mounted) return;
    setState(() => _adding = false);
    ref.read(gallerySelectionProvider.notifier).clear();
    ref.read(addedToastProvider.notifier).show(result);
    await ref.read(dataVersionProvider.notifier).check();
    if (mounted) context.go(Routes.home);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final selection = ref.watch(gallerySelectionProvider);
    final policy = ref.watch(queuePolicyProvider).value ?? const QueuePolicy();
    final overnight = policy.mode == QueueMode.overnight;
    final now = ref.watch(clockProvider).now();
    final denied =
        _access == GalleryAccess.denied ||
        _access == GalleryAccess.permanentlyDenied;
    final allSelected =
        _images.isNotEmpty && selection.length == _images.length;
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final groups = <String, List<DeviceImage>>{};
    for (final image in _images) {
      (groups[dayLabel(image.takenAt, now)] ??= []).add(image);
    }

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
                  if (!denied)
                    TapArea(
                      onTap: () {
                        final notifier = ref.read(
                          gallerySelectionProvider.notifier,
                        );
                        if (allSelected) {
                          notifier.clear();
                        } else {
                          notifier.selectAll([
                            for (final image in _images) image.uri,
                          ]);
                        }
                      },
                      semanticLabel: allSelected
                          ? 'Clear selection'
                          : 'Select all images',
                      minSize: 0,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.s2,
                          vertical: Space.s3,
                        ),
                        child: Text(
                          allSelected ? 'Clear' : 'Select all',
                          style: MemoraText.style(
                            12,
                            medium: true,
                            color: c.accentInk,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const FadingRule(),
              Expanded(
                child: denied
                    ? _PermissionPanel(
                        permanent: _access == GalleryAccess.permanentlyDenied,
                        onAllow: _requestAccess,
                        onPicker: () async {
                          final uris = await _gallery.pickWithSystemPicker();
                          await _addUris(uris);
                        },
                      )
                    : _GalleryGrid(
                        controller: _scroll,
                        groups: groups,
                        selection: selection,
                        partial: _access == GalleryAccess.partial,
                        onChooseMore: _requestAccess,
                        onToggle: (uri) => ref
                            .read(gallerySelectionProvider.notifier)
                            .toggle(uri),
                      ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [c.bg, c.bg, c.bg.withValues(alpha: 0)],
                  stops: const [0, 0.68, 1],
                ),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  Space.s4,
                  Space.s4,
                  Space.s4,
                  Space.s6 + bottomInset,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ToggleCard.compact(
                      value: overnight,
                      icon: MemoraIcons.moonStars,
                      body: overnight
                          ? 'Queued for tonight, while charging'
                          : 'Process now, as you add them',
                      onChanged: (value) => ref
                          .read(queuePolicyProvider.notifier)
                          .setMode(
                            value ? QueueMode.overnight : QueueMode.immediate,
                          ),
                    ),
                    const SizedBox(height: Space.s2),
                    OutlineAction(
                      label: _adding
                          ? 'Adding…'
                          : selection.isEmpty
                          ? 'Select images to add'
                          : 'Add ${imageCount(selection.length)}',
                      icon: MemoraIcons.images,
                      height: 46,
                      tone: selection.isEmpty
                          ? ActionTone.disabled
                          : ActionTone.accent,
                      onPressed: selection.isEmpty || _adding
                          ? null
                          : () => _addUris(selection.toList()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GalleryGrid extends StatelessWidget {
  const _GalleryGrid({
    required this.controller,
    required this.groups,
    required this.selection,
    required this.partial,
    required this.onToggle,
    required this.onChooseMore,
  });

  final ScrollController controller;
  final Map<String, List<DeviceImage>> groups;
  final Set<String> selection;
  final bool partial;
  final ValueChanged<String> onToggle;
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
              for (final group in groups.entries)
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
                                group.key.toUpperCase(),
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
                              imageCount(group.value.length),
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
                        delegate: SliverChildBuilderDelegate((context, i) {
                          final image = group.value[i];
                          return _GalleryCell(
                            image: image,
                            selected: selection.contains(image.uri),
                            onTap: () => onToggle(image.uri),
                          );
                        }, childCount: group.value.length),
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
  const _GalleryCell({
    required this.image,
    required this.selected,
    required this.onTap,
  });

  final DeviceImage image;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.colors;
    final gallery = ref.watch(appServicesProvider).gallery;
    return TapArea(
      onTap: onTap,
      semanticLabel: 'Image from ${dayLabel(image.takenAt, image.takenAt)}',
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
            BytesImageView(
              cacheKey: image.uri,
              load: () => gallery.thumbnail(image.uri),
            ),
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
                  color: selected ? c.accent : null,
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
