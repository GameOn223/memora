import 'package:flutter/widgets.dart';

/// Phosphor icons used by Memora.
///
/// The glyphs come from the font files bundled by the `phosphor_flutter`
/// package. Its Dart API can't be imported on current Flutter because it
/// extends `IconData`, which is now a final class, so the code points are
/// declared here instead. Add new icons from the Phosphor catalog as needed.
abstract final class MemoraIcons {
  static const _family = 'PhosphorRegular';
  static const _package = 'phosphor_flutter';

  static const arrowCounterClockwise = IconData(
    0xe038,
    fontFamily: _family,
    fontPackage: _package,
    matchTextDirection: true,
  );
  static const arrowLeft = IconData(
    0xe058,
    fontFamily: _family,
    fontPackage: _package,
    matchTextDirection: true,
  );
  static const arrowLineDown = IconData(
    0xe05c,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const arrowUp = IconData(
    0xe08e,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const arrowUpRight = IconData(
    0xe092,
    fontFamily: _family,
    fontPackage: _package,
    matchTextDirection: true,
  );
  static const arrowsClockwise = IconData(
    0xe094,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const bell = IconData(
    0xe0ce,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const caretDown = IconData(
    0xe136,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const caretRight = IconData(
    0xe13a,
    fontFamily: _family,
    fontPackage: _package,
    matchTextDirection: true,
  );
  static const chatTeardropText = IconData(
    0xe178,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const chatsCircle = IconData(
    0xe17e,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const checkCircle = IconData(
    0xe184,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const circleHalf = IconData(
    0xe18c,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const clockCounterClockwise = IconData(
    0xe1a0,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const cloud = IconData(
    0xe1aa,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const cloudArrowUp = IconData(
    0xe1ae,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const deviceMobile = IconData(
    0xe1e0,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const dotsNine = IconData(
    0xe1fc,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const dotsThreeVertical = IconData(
    0xe208,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const downloadSimple = IconData(
    0xe20c,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const export = IconData(
    0xeaf0,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const eye = IconData(
    0xe220,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const funnel = IconData(
    0xe266,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const gitBranch = IconData(
    0xe278,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const graph = IconData(
    0xeb58,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const gridFour = IconData(
    0xe296,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const handTap = IconData(
    0xec90,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const hardDrives = IconData(
    0xe2a0,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const image = IconData(
    0xe2ca,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const images = IconData(
    0xe836,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const key = IconData(
    0xe2d6,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const lightning = IconData(
    0xe2de,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const magnifyingGlass = IconData(
    0xe30c,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const moonStars = IconData(
    0xe58e,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const pause = IconData(
    0xe39e,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const play = IconData(
    0xe3d0,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const plus = IconData(
    0xe3d4,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const shieldCheck = IconData(
    0xe40c,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const slidersHorizontal = IconData(
    0xe434,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const sortAscending = IconData(
    0xe444,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const sparkle = IconData(
    0xe6a2,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const square = IconData(
    0xe45e,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const squaresFour = IconData(
    0xe464,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const stack = IconData(
    0xe466,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const trash = IconData(
    0xe4a6,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const warningCircle = IconData(
    0xe4e2,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const x = IconData(0xe4f6, fontFamily: _family, fontPackage: _package);
}

/// Filled Phosphor glyphs.
abstract final class MemoraIconsFill {
  static const _family = 'PhosphorFill';
  static const _package = 'phosphor_flutter';

  static const check = IconData(
    0xe182,
    fontFamily: _family,
    fontPackage: _package,
  );
  static const circle = IconData(
    0xe18a,
    fontFamily: _family,
    fontPackage: _package,
  );
}
