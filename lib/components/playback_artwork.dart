import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../utils/ios_motion.dart';

class PlayerArtworkHero extends StatelessWidget {
  const PlayerArtworkHero({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// Moves, rounds and fades the artwork edge together as the player changes view.
class IosArtworkPosition extends StatefulWidget {
  const IosArtworkPosition({
    super.key,
    required this.rect,
    required this.child,
    this.radius = 0,
    this.bottomFade = 0,
    this.reduceMotion = false,
  });

  final Rect rect;
  final Widget child;
  final double radius;
  final double bottomFade;
  final bool reduceMotion;

  @override
  State<IosArtworkPosition> createState() => _IosArtworkPositionState();
}

class _IosArtworkPositionState extends State<IosArtworkPosition> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController.unbounded(vsync: this, value: 1);
  late Rect _from = widget.rect;
  late Rect _to = widget.rect;
  late double _fromRadius = widget.radius;
  late double _toRadius = widget.radius;
  late double _fromFade = widget.bottomFade;
  late double _toFade = widget.bottomFade;

  Rect get _currentRect => Rect.lerp(_from, _to, _controller.value)!;
  double get _currentRadius => _fromRadius + (_toRadius - _fromRadius) * _controller.value;
  double get _currentFade => _fromFade + (_toFade - _fromFade) * _controller.value;

  @override
  void didUpdateWidget(covariant IosArtworkPosition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.rect != oldWidget.rect ||
        widget.radius != oldWidget.radius ||
        widget.bottomFade != oldWidget.bottomFade) {
      _from = _currentRect;
      _to = widget.rect;
      _fromRadius = _currentRadius;
      _toRadius = widget.radius;
      _fromFade = _currentFade;
      _toFade = widget.bottomFade;
      _controller.stop();
      _controller.value = 0;
      if (!widget.reduceMotion) {
        _controller.animateWith(SpringSimulation(IosMotion.spring, 0, 1, 0));
      } else {
        _controller.value = 1;
      }
    } else if (widget.reduceMotion && !oldWidget.reduceMotion && _controller.value != 1) {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _controller,
    child: widget.child,
    builder: (context, child) => Positioned.fromRect(
      rect: _currentRect,
      child: ClipPath(
        clipper: ShapeBorderClipper(
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(_currentRadius.clamp(0.0, 24.0).toDouble()),
          ),
        ),
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Colors.white,
              Colors.white.withValues(alpha: 1 - _currentFade.clamp(0.0, 1.0)),
            ],
            stops: const [0, .75, 1],
          ).createShader(bounds),
          child: child,
        ),
      ),
    ),
  );
}

/// Progressive blur edge (used by the lyrics side fades).
class PlayerArtworkEdge extends StatelessWidget {
  const PlayerArtworkEdge({super.key});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (bounds) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.white],
      ).createShader(bounds),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10, tileMode: TileMode.clamp),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

Rect fullPlayerArtworkRect(Size size, EdgeInsets padding) {
  final availableHeight = (size.height - padding.top - padding.bottom).clamp(0.0, size.height);
  if (size.width > size.height) {
    final side = availableHeight.clamp(0.0, (size.width / 2).clamp(0.0, 560.0));
    return Rect.fromLTWH(0, padding.top, side, side);
  }
  final width = size.width.clamp(0.0, 560.0);
  final height = (availableHeight * .56).clamp(0.0, width * 1.15);
  return Rect.fromLTWH((size.width - width) / 2, 0, width, height);
}

double fullPlayerArtworkHeight(Size size, EdgeInsets padding) => fullPlayerArtworkRect(size, padding).height;

class PlaybackArtwork extends StatelessWidget {
  final bool isPlaying;
  final Widget child;

  const PlaybackArtwork({super.key, required this.isPlaying, required this.child});

  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: isPlaying ? 1.0 : 0.85,
    duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 350),
    curve: Curves.easeOutCubic,
    child: child,
  );
}
