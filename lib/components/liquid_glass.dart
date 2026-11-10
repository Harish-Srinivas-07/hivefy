import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// iOS "liquid glass" capsule, a Flutter port of BitChord's glass bar:
/// squircle pill (exponent 2.1), backdrop blur, dark surface tint (#121212 at 40%),
/// a directional 45 degree rim highlight, and a soft shadow drawn outside the shape only.
///
/// ```dart
/// LiquidGlass(child: Padding(padding: EdgeInsets.all(12), child: row))
/// ```
/// Lens refraction and vibrancy (saturation boost) from the native version are not
/// available in Flutter's BackdropFilter, so they are left out.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.blurSigma = 10,
    this.tint = const Color(0x66121212),
    this.exponent = 2.1,
    this.shadow = true,
    this.rim = true,
    this.rimAlpha = .5,
    this.rimAngle = 45,
  });

  final Widget child;

  /// Backdrop blur. 0 disables the blur (use for "reduce motion / blur").
  final double blurSigma;

  /// Fill over the blur.
  final Color tint;

  /// 2 = plain capsule. 2.1 is BitChord's squircle.
  final double exponent;
  final bool shadow;
  final bool rim;

  /// Brightness of the rim highlight, 0..1.
  final double rimAlpha;

  /// Direction the rim light comes from, degrees.
  final double rimAngle;

  @override
  Widget build(BuildContext context) {
    Widget surface = ColoredBox(color: tint, child: child);
    if (blurSigma > 0) {
      surface = BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma, tileMode: TileMode.clamp),
        child: surface,
      );
    }
    return CustomPaint(
      painter: shadow ? _ShadowPainter(exponent) : null,
      foregroundPainter: rim ? _RimPainter(exponent: exponent, alpha: rimAlpha, angle: rimAngle) : null,
      child: ClipPath(clipper: _PillClipper(exponent), child: surface),
    );
  }
}

/// Fully rounded squircle pill: each end is a superellipse quarter, |x|^n + |y|^n = 1
/// (same maths as BitChord's SquirclePillShape).
Path squirclePillPath(Size size, {double exponent = 2.1, int steps = 32}) {
  final r = math.min(size.width, size.height) / 2;
  if (r <= 0) return Path()..addRect(Offset.zero & size);
  final w = size.width;
  final h = size.height;
  final power = 2 / exponent;
  final path = Path();

  void quarter(double cx, double cy, double sx, double sy, bool towardEdge) {
    for (var i = 1; i <= steps; i++) {
      final step = towardEdge ? i : steps - i;
      final t = step * (math.pi / 2) / steps;
      final x = math.pow(math.max(math.cos(t), 0), power).toDouble();
      final y = math.pow(math.max(math.sin(t), 0), power).toDouble();
      path.lineTo(cx + sx * r * x, cy + sy * r * y);
    }
  }

  path.moveTo(r, 0);
  path.lineTo(w - r, 0);
  quarter(w - r, r, 1, -1, false);
  path.lineTo(w, h - r);
  quarter(w - r, h - r, 1, 1, true);
  path.lineTo(r, h);
  quarter(r, h - r, -1, 1, false);
  path.lineTo(0, r);
  quarter(r, r, -1, -1, true);
  path.close();
  return path;
}

class _PillClipper extends CustomClipper<Path> {
  const _PillClipper(this.exponent);
  final double exponent;

  @override
  Path getClip(Size size) => squirclePillPath(size, exponent: exponent);

  @override
  bool shouldReclip(_PillClipper old) => old.exponent != exponent;
}

/// Soft shadow (radius 24, offset y 4, black 10%) clipped to OUTSIDE the pill,
/// so it never darkens the glass itself.
class _ShadowPainter extends CustomPainter {
  const _ShadowPainter(this.exponent);
  final double exponent;

  @override
  void paint(Canvas canvas, Size size) {
    final shape = squirclePillPath(size, exponent: exponent);
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Rect.fromLTWH(-100, -100, size.width + 200, size.height + 200)),
      shape,
    );
    canvas.save();
    canvas.clipPath(outside);
    canvas.drawPath(
      shape.shift(const Offset(0, 4)),
      Paint()
        ..color = Colors.black.withValues(alpha: .10)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShadowPainter old) => old.exponent != exponent;
}

/// Hairline edge plus a directional highlight: bright where the edge faces the light,
/// bright again on the opposite side, dim in between.
class _RimPainter extends CustomPainter {
  const _RimPainter({required this.exponent, required this.alpha, required this.angle});
  final double exponent;
  final double alpha;
  final double angle;

  @override
  void paint(Canvas canvas, Size size) {
    final path = squirclePillPath(size, exponent: exponent);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .5
        ..color = Colors.white.withValues(alpha: .08),
    );
    final a = angle * math.pi / 180;
    final dir = Offset(math.cos(a), math.sin(a));
    final half = (size.width * dir.dx.abs() + size.height * dir.dy.abs()) / 2;
    final center = size.center(Offset.zero);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .8
        ..shader = ui.Gradient.linear(
          center - dir * half,
          center + dir * half,
          [
            Colors.white.withValues(alpha: alpha),
            Colors.white.withValues(alpha: .05),
            Colors.white.withValues(alpha: .05),
            Colors.white.withValues(alpha: alpha * .8),
          ],
          const [0, .3, .7, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_RimPainter old) => old.exponent != exponent || old.alpha != alpha || old.angle != angle;
}
