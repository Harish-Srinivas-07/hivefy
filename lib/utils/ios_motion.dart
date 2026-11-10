import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

import 'ios_blur.dart';

/// Single source of truth for iOS-style motion, corners and blur.
/// Tune here, every player/sheet that uses it changes together.
abstract final class IosMotion {
  // ---- physics ----
  static final SpringDescription spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 600, ratio: 1);
  static const double projectionSeconds = .18; // flick lookahead when deciding open/close

  // ---- corners ----
  static const double artworkMiniRadius = 6;
  static const double sheetRadius = 40; // device-like corner while the card is mid-flight

  /// iOS continuous corner ("squircle"). Flutter's value must be ~1.8x a circular radius to look equal.
  static ContinuousRectangleBorder squircle(double radius) =>
      ContinuousRectangleBorder(borderRadius: BorderRadius.circular(radius * 1.8));

  /// Card radius over progress t: pill -> sheet corner -> square at the very end.
  static double cardRadius(double pillRadius, double t) {
    final c = Curves.easeOutCubic.transform(t.clamp(0.0, 1.0));
    final end = const Interval(.85, 1).transform(t.clamp(0.0, 1.0));
    return lerpDouble(pillRadius, sheetRadius, c)! * (1 - end);
  }

  // ---- blur / glass ----
  static const double glassBlur = 28;
  static const Color glassTintMini = Color(0x33FFFFFF);
  static const Color glassTintFull = Color(0xF0181818);
}

/// Clips to an iOS continuous rounded rect at an arbitrary rect.
class IosCardClipper extends CustomClipper<Path> {
  const IosCardClipper(this.rect, this.radius);
  final Rect rect;
  final double radius;

  @override
  Path getClip(Size size) => IosMotion.squircle(radius).getOuterPath(rect);

  @override
  bool shouldReclip(IosCardClipper old) => old.rect != rect || old.radius != radius;
}

/// Card glass that tints more as [progress] -> 1. Built on [IosBlur] (utils/ios_blur.dart).
/// Must sit inside a clip.
class IosGlass extends StatelessWidget {
  const IosGlass({super.key, required this.progress, this.fade = 1});
  final double progress; // 0..1
  final double fade; // 0..1

  @override
  Widget build(BuildContext context) {
    final p = progress.clamp(0.0, 1.0);
    final e = Curves.easeOut.transform(p);
    final tint = Color.lerp(glassTintMini, glassTintFull, e)!;
    // fully open: page covers everything, skip the expensive backdrop pass
    final style = IosBlurStyle(sigma: p >= 1 ? 0 : glassBlur * e, tint: tint);
    return IosBlur(style: style, fade: fade);
  }

  static const double glassBlur = IosMotion.glassBlur;
  static const Color glassTintMini = IosMotion.glassTintMini;
  static const Color glassTintFull = IosMotion.glassTintFull;
}
