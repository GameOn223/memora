import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Makes [child] tappable with a press fade, an accessible label and a hit
/// area of at least [minSize] square, without changing how it looks.
///
/// The hit area grows around the child's center. Taps in the grown area only
/// arrive when every ancestor also contains that point, so place small
/// controls in rows that are at least [minSize] tall.
class TapArea extends StatelessWidget {
  const TapArea({
    super.key,
    required this.onTap,
    required this.child,
    this.semanticLabel,
    this.button = true,
    this.selected,
    this.toggled,
    this.minSize = kMinTapTarget,
  });

  final VoidCallback? onTap;
  final Widget child;

  /// Read by screen readers. When null, labels of descendants are merged.
  final String? semanticLabel;
  final bool button;
  final bool? selected;
  final bool? toggled;
  final double minSize;

  @override
  Widget build(BuildContext context) {
    return _TapTarget(
      minSize: minSize,
      label: semanticLabel,
      onTap: onTap,
      button: button,
      selected: selected,
      toggled: toggled,
      textDirection: Directionality.of(context),
      child: _Pressable(
        onTap: onTap,
        child: semanticLabel == null ? child : ExcludeSemantics(child: child),
      ),
    );
  }
}

class _Pressable extends StatefulWidget {
  const _Pressable({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (_down != down && mounted) setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: widget.onTap,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      child: AnimatedOpacity(
        opacity: _down ? 0.55 : 1,
        duration: const Duration(milliseconds: 90),
        child: widget.child,
      ),
    );
  }
}

class _TapTarget extends SingleChildRenderObjectWidget {
  const _TapTarget({
    required this.minSize,
    required this.label,
    required this.onTap,
    required this.button,
    required this.selected,
    required this.toggled,
    required this.textDirection,
    required super.child,
  });

  final double minSize;
  final String? label;
  final VoidCallback? onTap;
  final bool button;
  final bool? selected;
  final bool? toggled;
  final TextDirection textDirection;

  @override
  RenderTapTarget createRenderObject(BuildContext context) => RenderTapTarget(
    minSize: minSize,
    label: label,
    onTap: onTap,
    button: button,
    selected: selected,
    toggled: toggled,
    textDirection: textDirection,
  );

  @override
  void updateRenderObject(BuildContext context, RenderTapTarget renderObject) {
    renderObject
      ..minSize = minSize
      ..label = label
      ..onTap = onTap
      ..button = button
      ..selected = selected
      ..toggled = toggled
      ..textDirection = textDirection;
  }
}

/// Render object behind [TapArea]. Public so tests can measure hit areas.
class RenderTapTarget extends RenderProxyBox {
  RenderTapTarget({
    required this._minSize,
    required this._label,
    required this._onTap,
    required this._button,
    required this._selected,
    required this._toggled,
    required this._textDirection,
  });

  double _minSize;
  set minSize(double value) {
    if (value == _minSize) return;
    _minSize = value;
    markNeedsSemanticsUpdate();
  }

  String? _label;
  set label(String? value) {
    if (value == _label) return;
    _label = value;
    markNeedsSemanticsUpdate();
  }

  VoidCallback? _onTap;
  set onTap(VoidCallback? value) {
    if ((value == null) != (_onTap == null)) markNeedsSemanticsUpdate();
    _onTap = value;
  }

  bool _button;
  set button(bool value) {
    if (value == _button) return;
    _button = value;
    markNeedsSemanticsUpdate();
  }

  bool? _selected;
  set selected(bool? value) {
    if (value == _selected) return;
    _selected = value;
    markNeedsSemanticsUpdate();
  }

  bool? _toggled;
  set toggled(bool? value) {
    if (value == _toggled) return;
    _toggled = value;
    markNeedsSemanticsUpdate();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    markNeedsSemanticsUpdate();
  }

  /// The tappable rectangle in local coordinates.
  Rect get tapRect {
    final width = math.max(size.width, _minSize);
    final height = math.max(size.height, _minSize);
    return Rect.fromCenter(
      center: size.center(Offset.zero),
      width: width,
      height: height,
    );
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!tapRect.contains(position)) return false;
    final inside = Offset(
      clampDouble(position.dx, 0, math.max(0, size.width - 0.01)),
      clampDouble(position.dy, 0, math.max(0, size.height - 0.01)),
    );
    child?.hitTest(result, position: inside);
    result.add(BoxHitTestEntry(this, position));
    return true;
  }

  @override
  Rect get semanticBounds => tapRect;

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    config
      ..isSemanticBoundary = true
      ..isMergingSemanticsOfDescendants = true
      ..textDirection = _textDirection
      ..isButton = _button
      ..isEnabled = _onTap != null;
    if (_label != null) config.label = _label!;
    if (_onTap != null) config.onTap = () => _onTap?.call();
    if (_selected != null) config.isSelected = _selected!;
    if (_toggled != null) config.isToggled = _toggled;
  }
}
