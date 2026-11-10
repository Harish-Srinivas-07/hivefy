import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'ios_motion.dart';

/// iOS-style blur presets (like UIBlurEffect.Style). Pick one, or build your own.
class IosBlurStyle {
  const IosBlurStyle({required this.sigma, required this.tint});
  final double sigma;
  final Color tint;

  static const ultraThin = IosBlurStyle(sigma: 12, tint: Color(0x1FFFFFFF));
  static const thin = IosBlurStyle(sigma: 20, tint: Color(0x33FFFFFF));
  static const regular = IosBlurStyle(sigma: 28, tint: Color(0x4D1C1C1E));
  static const thick = IosBlurStyle(sigma: 40, tint: Color(0x991C1C1E));
  static const chrome = IosBlurStyle(sigma: 30, tint: Color(0xCC161616)); // nav / tab / mini player bars
  static const dark = IosBlurStyle(sigma: 36, tint: Color(0xF0181818)); // full player card

  IosBlurStyle copyWith({double? sigma, Color? tint}) =>
      IosBlurStyle(sigma: sigma ?? this.sigma, tint: tint ?? this.tint);
}

/// Frosted glass box. Blurs whatever is BEHIND it.
///
/// ```dart
/// IosBlur(style: IosBlurStyle.chrome, radius: 20, child: miniPlayerRow)
/// ```
/// - [radius] null = no corner clip (use inside an existing clip).
/// - [fade] 0..1 scales blur + tint for animations. Never wrap in Opacity (it kills backdrop blur).
class IosBlur extends StatelessWidget {
  const IosBlur({
    super.key,
    this.child,
    this.style = IosBlurStyle.regular,
    this.radius,
    this.fade = 1,
    this.border = false,
  });

  final Widget? child;
  final IosBlurStyle style;
  final double? radius;
  final double fade;
  final bool border; // hairline highlight edge like iOS glass

  @override
  Widget build(BuildContext context) {
    final f = fade.clamp(0.0, 1.0);
    final sigma = style.sigma * f;
    final tint = style.tint.withValues(alpha: style.tint.a * f);

    Widget box = ColoredBox(color: tint, child: child ?? const SizedBox.expand());
    if (sigma >= .1) {
      box = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.clamp),
        child: box,
      );
    }
    final r = radius;
    if (r == null) return box;

    final shape = IosMotion.squircle(r);
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: border
            ? ContinuousRectangleBorder(
                borderRadius: shape.borderRadius,
                side: BorderSide(color: Colors.white.withValues(alpha: .12 * f), width: .6),
              )
            : shape,
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: box,
      ),
    );
  }
}

/// Animates blur in/out smoothly (e.g. when a sheet or overlay appears).
class IosBlurTransition extends StatelessWidget {
  const IosBlurTransition({
    super.key,
    required this.visible,
    this.child,
    this.style = IosBlurStyle.regular,
    this.radius,
    this.duration = const Duration(milliseconds: 350),
  });

  final bool visible;
  final Widget? child;
  final IosBlurStyle style;
  final double? radius;
  final Duration duration;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: visible ? 1 : 0),
    duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration,
    curve: Curves.easeOutCubic,
    child: child,
    builder: (context, v, child) => IosBlur(style: style, radius: radius, fade: v, child: child),
  );
}

/// Progressive blur: clear on one edge, increasingly blurred toward the other
/// (iOS nav bars, artwork bottom edge, lyrics fade). Layers several blurs under graded masks.
///
/// ```dart
/// Positioned(bottom: 0, left: 0, right: 0, height: 90,
///   child: IgnorePointer(child: IosProgressiveBlur(from: Alignment.topCenter)))
/// ```
/// [from] = the CLEAR side. Blur grows toward the opposite side.
class IosProgressiveBlur extends StatelessWidget {
  const IosProgressiveBlur({
    super.key,
    this.from = Alignment.topCenter,
    this.sigmas = const [1.5, 3.0, 6.0, 10.0, 16.0, 24.0],
  });

  final Alignment from;
  final List<double> sigmas;

  @override
  Widget build(BuildContext context) {
    final to = Alignment(-from.x, -from.y);
    final n = sigmas.length;
    return Stack(
      fit: StackFit.expand,
      children: [
        for (var i = 0; i < n; i++)
          Positioned.fill(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) => LinearGradient(
                begin: from,
                end: to,
                colors: const [Colors.transparent, Colors.white],
                stops: [i / (n + 1), (i + 2) / (n + 1)],
              ).createShader(bounds),
              child: ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: sigmas[i], sigmaY: sigmas[i], tileMode: TileMode.clamp),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
