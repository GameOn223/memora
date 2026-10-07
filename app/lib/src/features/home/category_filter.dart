import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/memories.dart';
import '../../state/ui_state.dart';
import '../../theme/memora_colors.dart';
import '../../theme/memora_icons.dart';
import '../../theme/text_styles.dart';
import '../../theme/tokens.dart';
import '../../widgets/caps_label.dart';
import '../../widgets/chip_bar.dart';
import '../../widgets/tap_area.dart';

/// The category row above the memories grid.
///
/// A long sideways list of chips stops working once there are thirty
/// categories: the one you want is off the end and the grid toggle beside it
/// gets pushed around. So the row is a fixed two chips and a button, and
/// everything else lives in a picker that can be searched.
class CategoryFilter extends ConsumerWidget {
  const CategoryFilter({super.key, required this.height});

  /// How many category chips sit in the row, not counting `All`.
  static const visibleChips = 2;

  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final options = ref.watch(categoryOptionsProvider).value ?? const [];
    if (options.isEmpty) return const SizedBox.shrink();
    final selected = ref.watch(homeFilterProvider);
    final labels = [for (final o in options) o.label];
    final shown = chipsFor(labels, selected);
    final hidden = hiddenCount(shown, selected);

    return SizedBox(
      height: height,
      child: Row(
        children: [
          for (final label in shown) ...[
            SelectChip(
              label: label,
              selected: label == allCategoriesLabel
                  ? selected.isEmpty
                  : selected.contains(label),
              onTap: () => ref.read(homeFilterProvider.notifier).select(label),
              hitHeight: height,
            ),
            const SizedBox(width: Space.s2),
          ],
          _MoreButton(
            extra: hidden,
            hitHeight: height,
            onTap: () => _openPicker(context, ref, options, selected),
          ),
        ],
      ),
    );
  }

  /// `All` plus the chips worth showing: whichever categories are picked,
  /// then the most common ones to fill the space.
  static List<String> chipsFor(List<String> labels, Set<String> selected) {
    final rest = labels.where((l) => l != allCategoriesLabel);
    return [
      allCategoriesLabel,
      ...rest.where(selected.contains).take(visibleChips),
      ...rest
          .where((l) => !selected.contains(l))
          .take(visibleChips - selected.length.clamp(0, visibleChips)),
    ];
  }

  /// How many picked categories the row had no room to show. The row is a
  /// fixed width, so this is what the button carries instead.
  static int hiddenCount(List<String> shown, Set<String> selected) =>
      selected.length - shown.where(selected.contains).length;

  Future<void> _openPicker(
    BuildContext context,
    WidgetRef ref,
    List<CategoryOption> options,
    Set<String> selected,
  ) async {
    // showGeneralDialog, like the rest of the app, rather than
    // showModalBottomSheet: it leaves the height ours to set, so the action
    // at the bottom cannot end up under the edge of the screen. The Material
    // is not decoration either, without one the text falls back to the
    // yellow underlined debug style.
    final picked = await showGeneralDialog<Set<String>>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close categories',
      barrierColor: Colors.black54,
      pageBuilder: (context, _, _) => Material(
        type: MaterialType.transparency,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: _CategorySheet(options: options, selected: selected),
        ),
      ),
    );
    if (picked == null) return;
    ref.read(homeFilterProvider.notifier).replace(picked);
  }
}

/// Opens the picker, carrying how many picks the row could not show.
class _MoreButton extends StatelessWidget {
  const _MoreButton({
    required this.extra,
    required this.hitHeight,
    required this.onTap,
  });

  final int extra;
  final double hitHeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final label = extra > 0 ? '+$extra' : '+';
    return TapArea(
      onTap: onTap,
      button: true,
      semanticLabel: extra > 0
          ? 'All categories, $extra more chosen'
          : 'All categories',
      child: SizedBox(
        height: hitHeight,
        child: Center(
          child: Container(
            height: 28,
            constraints: const BoxConstraints(minWidth: 34),
            padding: const EdgeInsets.symmetric(horizontal: Space.s3),
            decoration: BoxDecoration(
              color: extra > 0 ? c.accent.withValues(alpha: 0.14) : null,
              border: Border.all(color: extra > 0 ? c.accent : c.line),
              borderRadius: BorderRadius.circular(Radii.lg),
            ),
            child: Center(
              child: Text(
                label,
                style: MemoraText.style(
                  12.5,
                  color: extra > 0 ? c.accent : c.muted,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Every category, searchable, with as many picked at once as you like.
class _CategorySheet extends StatefulWidget {
  const _CategorySheet({required this.options, required this.selected});

  final List<CategoryOption> options;
  final Set<String> selected;

  @override
  State<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends State<_CategorySheet> {
  final _search = TextEditingController();
  late final Set<String> _picked = {...widget.selected};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<CategoryOption> get _matches {
    final query = _search.text.trim().toLowerCase();
    return [
      for (final option in widget.options)
        if (option.label != allCategoriesLabel &&
            (query.isEmpty || option.label.toLowerCase().contains(query)))
          option,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final matches = _matches;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      // Lifted clear of the keyboard while the search field has focus.
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          border: Border(top: BorderSide(color: c.line)),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        // Room for the list, with the action and the search field always
        // reachable. The safe area comes off the top of that, not out of it.
        constraints: BoxConstraints(
          maxHeight:
              (MediaQuery.sizeOf(context).height -
                  MediaQuery.paddingOf(context).top -
                  bottom) *
              0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.s6,
                Space.s6,
                Space.s6,
                Space.s3,
              ),
              child: Row(
                children: [
                  const Expanded(child: CapsLabel('CATEGORIES')),
                  if (_picked.isNotEmpty)
                    GestureDetector(
                      onTap: () => setState(_picked.clear),
                      child: Text(
                        'Clear',
                        style: MemoraText.style(12.5, color: c.accent),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.s6),
              child: TextField(
                controller: _search,
                autocorrect: false,
                style: MemoraText.style(13.5, color: c.text),
                decoration: InputDecoration(
                  hintText: 'Search categories',
                  prefixIcon: Icon(
                    MemoraIcons.magnifyingGlass,
                    size: 16,
                    color: c.dim,
                  ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ),
            const SizedBox(height: Space.s2),
            Flexible(
              child: matches.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(Space.s6),
                      child: Text(
                        'Nothing called "${_search.text.trim()}".',
                        style: MemoraText.style(12.5, color: c.dim),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: Space.s3),
                      itemCount: matches.length,
                      itemBuilder: (context, i) {
                        final option = matches[i];
                        final on = _picked.contains(option.label);
                        return _CategoryTick(
                          label: option.label,
                          count: option.count,
                          ticked: on,
                          onTap: () => setState(() {
                            if (on) {
                              _picked.remove(option.label);
                            } else {
                              _picked.add(option.label);
                            }
                          }),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(Space.s6),
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(_picked),
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.accent,
                    borderRadius: BorderRadius.circular(Radii.md),
                  ),
                  child: Center(
                    child: Text(
                      _picked.isEmpty
                          ? 'Show everything'
                          : _picked.length == 1
                          ? 'Show ${_picked.first}'
                          : 'Show ${_picked.length} categories',
                      style: MemoraText.style(13.5, color: c.bg),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryTick extends StatelessWidget {
  const _CategoryTick({
    required this.label,
    required this.count,
    required this.ticked,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool ticked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return TapArea(
      onTap: onTap,
      button: true,
      toggled: ticked,
      semanticLabel: '$label, $count memories',
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Space.s6,
          vertical: Space.s3,
        ),
        child: Row(
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: ticked ? c.accent : null,
                border: Border.all(color: ticked ? c.accent : c.line),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: ticked
                  ? Icon(MemoraIconsFill.check, size: 13, color: c.bg)
                  : null,
            ),
            const SizedBox(width: Space.s3),
            Expanded(
              child: Text(label, style: MemoraText.style(13.5, color: c.text)),
            ),
            Text('$count', style: MemoraText.style(12, color: c.dim)),
          ],
        ),
      ),
    );
  }
}
