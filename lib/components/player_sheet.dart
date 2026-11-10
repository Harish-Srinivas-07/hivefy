import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../utils/ios_motion.dart';
import 'playback_artwork.dart';

/// App-wide handle to the player sheet. 0 = mini player, 1 = full player.
/// Everything (artwork, card, fades) reads [progress]; every input (tap, drag, back, pill)
/// goes through the methods below, so they can never disagree with each other.
final PlayerSheetController playerSheet = PlayerSheetController();

/// Reveals player content in stages as the sheet expands, including during a drag.
class PlayerEntrance extends StatelessWidget {
  const PlayerEntrance({super.key, required this.begin, required this.end, required this.child});

  final double begin;
  final double end;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return ValueListenableBuilder<double>(
      valueListenable: playerSheet.progress,
      child: child,
      builder: (context, progress, child) {
        final value = reduceMotion ? 1.0 : Interval(begin, end, curve: Curves.easeOutCubic).transform(progress);
        return IgnorePointer(
          ignoring: value < 1,
          child: Opacity(
            opacity: value,
            child: Transform.translate(offset: Offset(0, 12 * (1 - value)), child: child),
          ),
        );
      },
    );
  }
}

class PlayerSheetController {
  /// 0..1, drives every visual.
  final ValueNotifier<double> progress = ValueNotifier<double>(0);

  /// Whether the full player is mounted. It is mounted only while needed.
  final ValueNotifier<bool> engaged = ValueNotifier<bool>(false);

  /// Set by MiniPlayer.
  GlobalKey? miniArtworkKey;
  GlobalKey? miniBarKey;
  GlobalKey? fullArtworkKey;

  /// Global rects of the mini artwork and bar, measured when the sheet starts moving.
  Rect? miniArtworkRect;
  Rect? miniBarRect;
  Rect? _flightArtworkEnd;

  bool reduceMotion = false;

  AnimationController? _controller;
  Size _screen = const Size(400, 800);
  EdgeInsets _padding = EdgeInsets.zero;
  bool _closing = false;
  int _openRequest = 0;
  final Stopwatch _clock = Stopwatch()..start();
  double _sampleProgress = double.nan;
  int _sampleMicros = 0;
  double _dragVelocity = 0;
  static const int _sampleFreshMs = 80;
  static const double _minReportedVelocity = 50;

  /// True while the full player is showing or moving (used by the back button).
  bool get isOpen => engaged.value;

  /// Finger pixels that equal progress 0 -> 1 (mini artwork centre to full artwork centre),
  /// so the artwork follows the finger 1:1.
  double get travel {
    final begin = miniArtworkRect;
    if (begin == null) return 480;
    final end = _flightArtworkEnd ?? fullPlayerArtworkRect(_screen, _padding);
    return math.max(160.0, (begin.center.dy - end.center.dy).abs());
  }

  void setViewport(Size screen, EdgeInsets padding) {
    _screen = screen;
    _padding = padding;
  }

  void attach(AnimationController controller) {
    _controller?.removeListener(_sync);
    _controller = controller..addListener(_sync);
  }

  void detach(AnimationController controller) {
    if (!identical(_controller, controller)) return;
    controller.removeListener(_sync);
    _controller = null;
  }

  void _sync() {
    final c = _controller;
    if (c != null) progress.value = c.value;
  }

  Rect? _rectOf(GlobalKey? key) {
    final box = key?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// Measure the mini player and mount the full player (still invisible at progress 0).
  void prepare() {
    miniArtworkRect = _rectOf(miniArtworkKey) ?? miniArtworkRect;
    miniBarRect = _rectOf(miniBarKey) ?? miniBarRect;
    _flightArtworkEnd = null;
    engaged.value = true;
  }

  /// Capture the artwork's current position before closing or dragging the sheet.
  void prepareClose() {
    if (_controller?.value == 1) _flightArtworkEnd = _rectOf(fullArtworkKey);
  }

  /// Tap on the mini player.
  Future<void> open() async {
    final c = _controller;
    if (c == null || c.value >= 1) return;
    final request = ++_openRequest;
    _closing = false;
    final wasMounted = engaged.value;
    prepare();
    if (!wasMounted && !c.isAnimating) {
      // Let the full player build one frame before the spring starts, so the build
      // cost is not eaten out of the animation.
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
    }
    if (request != _openRequest || !identical(_controller, c) || !engaged.value) return;
    await _settle(1, 0);
  }

  Future<void> close() async {
    if (_controller == null || !engaged.value || _closing) return;
    prepareClose();
    _openRequest++;
    await _settle(0, 0);
  }

  /// Follow the finger. Interrupts any running spring.
  void dragTo(double p) {
    final c = _controller;
    if (c == null) return;
    prepareClose();
    _openRequest++;
    _closing = false;
    if (!engaged.value) prepare();
    c.value = p.clamp(0.0, 1.0);
    _sample(c.value);
  }

  void _sample(double progressNow) {
    final now = _clock.elapsedMicroseconds;
    final seconds = (now - _sampleMicros) / 1e6;
    if (_sampleProgress.isNaN || seconds > _sampleFreshMs / 1000 * 2) {
      _dragVelocity = 0;
    } else if (seconds > 0) {
      final instant = (progressNow - _sampleProgress) / seconds;
      _dragVelocity = _dragVelocity * .4 + instant * .6;
    }
    _sampleProgress = progressNow;
    _sampleMicros = now;
  }

  double _recentDragVelocity() {
    final ageMs = (_clock.elapsedMicroseconds - _sampleMicros) / 1000;
    return ageMs < _sampleFreshMs ? _dragVelocity : 0;
  }

  /// Finger lifted. [velocityY] in px/s, positive = moving down.
  void release(double velocityY) {
    final c = _controller;
    if (c == null) return;
    var v = -velocityY / travel;
    if (velocityY.abs() < _minReportedVelocity) v = _recentDragVelocity();
    _sampleProgress = double.nan;
    final open = c.value + v * IosMotion.projectionSeconds > .5;
    _settle(open ? 1 : 0, v);
  }

  Future<void> _settle(double target, double velocity) async {
    final c = _controller;
    if (c == null) return;
    _closing = target == 0;
    if (reduceMotion) {
      c.value = target;
    } else {
      // A new drag stops the ticker, so this future never completes and nothing below runs.
      await c.animateWith(SpringSimulation(IosMotion.spring, c.value, target, velocity));
      if (!identical(_controller, c)) return;
      c.value = target; // land exactly, the spring stops within 0.001
    }
    _closing = false;
    if (target == 0) {
      engaged.value = false;
      _flightArtworkEnd = null;
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }
}

/// Full-screen layer placed above the Scaffold (so it covers the bottom nav).
/// Draws the growing card, the flying artwork and hosts the full player.
class PlayerSheetLayer extends StatefulWidget {
  const PlayerSheetLayer({super.key, required this.player, required this.artwork});

  /// The full player screen.
  final Widget player;

  /// The artwork that flies from the mini player to the full player.
  final Widget artwork;

  @override
  State<PlayerSheetLayer> createState() => _PlayerSheetLayerState();
}

class _PlayerSheetLayerState extends State<PlayerSheetLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);
  late final Widget _page = RepaintBoundary(
    child: Material(type: MaterialType.transparency, child: widget.player),
  );

  @override
  void initState() {
    super.initState();
    playerSheet.attach(_controller);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    playerSheet.reduceMotion = MediaQuery.disableAnimationsOf(context);
  }

  @override
  void dispose() {
    playerSheet.detach(_controller);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screen = media.size;
    final end = fullPlayerArtworkRect(screen, media.viewPadding);
    playerSheet.setViewport(screen, media.viewPadding);

    return ValueListenableBuilder<bool>(
      valueListenable: playerSheet.engaged,
      builder: (context, engaged, _) {
        if (!engaged) return const SizedBox.shrink();
        final begin =
            playerSheet.miniArtworkRect ?? Rect.fromLTWH(40, screen.height - media.viewPadding.bottom - 128, 44, 44);
        final bar = playerSheet.miniBarRect ?? Rect.fromLTRB(12, begin.top - 9, screen.width - 12, begin.bottom + 9);
        return ValueListenableBuilder<double>(
          valueListenable: playerSheet.progress,
          child: _page,
          builder: (context, t, page) =>
              _frame(t.clamp(0.0, 1.0), page!, screen, begin, playerSheet._flightArtworkEnd ?? end, bar),
        );
      },
    );
  }

  Widget _frame(double t, Widget page, Size screen, Rect begin, Rect end, Rect bar) {
    final cardRect = Rect.lerp(bar, Offset.zero & screen, t)!;
    final radius = IosMotion.cardRadius(bar.height / 2, t);
    final artworkRect = Rect.lerp(begin, end, t)!;
    final compactArtwork = end.width < fullPlayerArtworkRect(screen, MediaQuery.viewPaddingOf(context)).width - 1;
    final cardFade = (t * 6).clamp(0.0, 1.0);
    final pageOpacity = const Interval(.05, .5, curve: Curves.easeOut).transform(t);
    final tint = IosMotion.glassTintFull;

    return IgnorePointer(
      ignoring: t <= 0,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // dim the app behind, blocks touches while moving
          if (t > 0) ColoredBox(color: Colors.black.withValues(alpha: .45 * t)),
          ClipPath(
            clipper: IosCardClipper(cardRect, radius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: tint.withValues(alpha: tint.a * cardFade)),
                Opacity(opacity: pageOpacity, child: page),
              ],
            ),
          ),
          // the one shared artwork, same rect/radius/fade as the finger-driven progress
          if (t > 0 && t < 1)
            Positioned.fromRect(
              rect: artworkRect,
              child: IgnorePointer(
                child: ClipPath(
                  clipper: ShapeBorderClipper(
                    shape: IosMotion.squircle(IosMotion.artworkMiniRadius * (1 - t) + (compactArtwork ? 8 * t : 0)),
                  ),
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (bounds) => LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: const [Colors.white, Colors.white, Colors.transparent],
                      stops: [0, compactArtwork ? 1 : .75 + .25 * (1 - t), 1],
                    ).createShader(bounds),
                    child: widget.artwork,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Wraps the mini player: tap opens, vertical drag pulls the sheet up with the finger.
/// Dragging back down mid-way shrinks it back to the mini player.
class PlayerSheetHandle extends StatefulWidget {
  const PlayerSheetHandle({super.key, required this.child});
  final Widget child;

  @override
  State<PlayerSheetHandle> createState() => _PlayerSheetHandleState();
}

class _PlayerSheetHandleState extends State<PlayerSheetHandle> {
  int? _pointer;
  Offset? _origin;
  VelocityTracker? _tracker;
  bool _dragging = false;
  double _baseDy = 0;

  void _down(PointerDownEvent e) {
    if (_pointer != null) return;
    _pointer = e.pointer;
    _origin = e.position;
    _dragging = false;
    _tracker = VelocityTracker.withKind(e.kind)..addPosition(e.timeStamp, e.position);
  }

  void _move(PointerMoveEvent e) {
    if (e.pointer != _pointer) return;
    _tracker?.addPosition(e.timeStamp, e.position);
    final origin = _origin;
    if (origin == null) return;
    if (!_dragging) {
      final o = e.position - origin;
      if (o.dy >= -kTouchSlop || o.dy.abs() <= o.dx.abs()) return;
      _dragging = true;
      _baseDy = e.position.dy;
      playerSheet.prepare();
    }
    playerSheet.dragTo((_baseDy - e.position.dy) / playerSheet.travel);
  }

  void _up(PointerUpEvent e) {
    if (e.pointer != _pointer) return;
    _tracker?.addPosition(e.timeStamp, e.position);
    if (_dragging) playerSheet.release(_tracker?.getVelocity().pixelsPerSecond.dy ?? 0);
    _reset();
  }

  void _cancel(PointerCancelEvent e) {
    if (e.pointer != _pointer) return;
    if (_dragging) playerSheet.release(0);
    _reset();
  }

  void _reset() {
    _pointer = null;
    _origin = null;
    _tracker = null;
    _dragging = false;
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: _down,
    onPointerMove: _move,
    onPointerUp: _up,
    onPointerCancel: _cancel,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        playerSheet.open();
      },
      child: widget.child,
    ),
  );
}
