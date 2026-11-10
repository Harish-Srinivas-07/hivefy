import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/lyrics.dart';
import 'lyrics_offset.dart';
import 'staggered_appearance.dart';

class LyricsLines extends ConsumerStatefulWidget {
  const LyricsLines({
    super.key,
    required this.lyrics,
    required this.positionStream,
    required this.songId,
    this.preview = false,
    this.glassStyle = false,
    this.onSeek,
  });
  final Lyrics lyrics;
  final String songId;
  final Stream<Duration> positionStream;
  final bool preview;
  final bool glassStyle;
  final ValueChanged<Duration>? onSeek;

  @override
  ConsumerState<LyricsLines> createState() => _LyricsLinesState();
}

class _LyricsLinesState extends ConsumerState<LyricsLines> {
  final ScrollController _controller = ScrollController();
  int _lastIndex = -2;
  bool _hasInitialPosition = false;
  bool _allowAutoScrollAnimation = false;
  Timer? _initialScrollTimer;
  List<GlobalKey> _keys = [];

  @override
  void initState() {
    super.initState();
    _resetKeys();
    _suppressInitialScrollAnimation();
  }

  @override
  void didUpdateWidget(covariant LyricsLines oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyrics != widget.lyrics) {
      _resetKeys();
      _suppressInitialScrollAnimation();
    }
  }

  void _resetKeys() {
    _keys = List.generate(widget.lyrics.lines.length, (_) => GlobalKey());
    _lastIndex = -2;
    _hasInitialPosition = false;
  }

  void _suppressInitialScrollAnimation() {
    _initialScrollTimer?.cancel();
    _allowAutoScrollAnimation = false;
    _initialScrollTimer = Timer(const Duration(milliseconds: 700), () {
      _allowAutoScrollAnimation = true;
    });
  }

  @override
  void dispose() {
    _initialScrollTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: ref.watch(lyricsOffsetProvider(widget.songId)),
      builder: (context, offset, _) => StreamBuilder<Duration>(
        stream: widget.positionStream,
        builder: (context, snapshot) {
          final lyricPosition = (snapshot.data ?? Duration.zero) - Duration(milliseconds: offset);
          final current = widget.lyrics.indexAt(lyricPosition);
          if (widget.lyrics.isSynced && current != _lastIndex) {
            _lastIndex = current;
            if (current >= 0) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted || _lastIndex != current) return;
                final target = _keys[current].currentContext?.findRenderObject();
                if (target != null && _controller.hasClients) {
                  final animate =
                      _hasInitialPosition && _allowAutoScrollAnimation && !MediaQuery.disableAnimationsOf(context);
                  _controller.position.ensureVisible(
                    target,
                    duration: animate ? const Duration(milliseconds: 450) : Duration.zero,
                    curve: Curves.easeOutCubic,
                    alignment: widget.preview ? 0 : (widget.glassStyle ? 0.62 : 0.25),
                  );
                }
                _hasInitialPosition = true;
              });
            } else {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _lastIndex == current && _controller.hasClients) {
                  if (!_hasInitialPosition || !_allowAutoScrollAnimation || MediaQuery.disableAnimationsOf(context)) {
                    _controller.jumpTo(0);
                  } else {
                    _controller.animateTo(0, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
                  }
                }
                if (mounted && _lastIndex == current) _hasInitialPosition = true;
              });
            }
          }
          if (widget.preview) {
            return SizedBox(height: 132, child: _scrollingLines(current, lyricPosition, offset, bottomPadding: 132));
          }
          return LayoutBuilder(
            builder: (context, constraints) => _scrollingLines(
              current,
              lyricPosition,
              offset,
              bottomPadding: constraints.maxHeight.isFinite ? constraints.maxHeight * 0.45 : 90,
            ),
          );
        },
      ),
    );
  }

  Widget _scrollingLines(int current, Duration position, int offset, {required double bottomPadding}) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: SingleChildScrollView(
        controller: _controller,
        physics: widget.preview ? const NeverScrollableScrollPhysics() : null,
        padding: EdgeInsets.fromLTRB(
          widget.preview ? 0 : 26,
          widget.preview ? 0 : 24,
          widget.preview ? 0 : 26,
          bottomPadding,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var index = 0; index < widget.lyrics.lines.length; index++)
              Container(
                key: _keys[index],
                padding: EdgeInsets.symmetric(vertical: widget.preview ? 4 : 8),
                child: widget.glassStyle && !widget.preview
                    ? StaggeredAppearance(
                        index: (index - (current < 0 ? 0 : current)).clamp(0, 6),
                        delayStep: const Duration(milliseconds: 90),
                        fadeDuration: const Duration(milliseconds: 400),
                        slideDuration: const Duration(milliseconds: 450),
                        child: _line(
                          widget.lyrics.lines[index],
                          offset: offset,
                          position: position,
                          active: widget.lyrics.isSynced && index == current,
                          upcoming: widget.lyrics.isSynced && index > current,
                        ),
                      )
                    : _line(
                        widget.lyrics.lines[index],
                        offset: offset,
                        position: position,
                        active: widget.lyrics.isSynced && index == current,
                        upcoming: widget.lyrics.isSynced ? index > current : widget.preview && index > 0,
                      ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _line(
    LyricLine line, {
    required int offset,
    required Duration position,
    required bool active,
    required bool upcoming,
  }) {
    final target = line.start + Duration(milliseconds: offset);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final timedWords = line.words.any((word) => word.start != null);
    var activeWord = -1;
    if (active && timedWords) {
      for (var i = 0; i < line.words.length; i++) {
        final start = line.words[i].start;
        if (start != null && start <= position) activeWord = i;
      }
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.lyrics.isSynced && widget.onSeek != null
          ? () => widget.onSeek!(target.isNegative ? Duration.zero : target)
          : null,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: widget.glassStyle && widget.lyrics.isSynced && !active ? 0.45 : 0,
          sigmaY: widget.glassStyle && widget.lyrics.isSynced && !active ? 0.45 : 0,
        ),
        child: AnimatedScale(
          scale: active && !reduceMotion ? 1.025 : 1,
          alignment: Alignment.centerLeft,
          duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
          curve: Curves.easeOutBack,
          child: AnimatedDefaultTextStyle(
            duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 300),
            style: DefaultTextStyle.of(context).style.copyWith(
              color: widget.glassStyle && widget.lyrics.isSynced && !active
                  ? Colors.white.withValues(alpha: 0.4)
                  : upcoming
                  ? Colors.white.withValues(alpha: 0.48)
                  : Colors.white,
              fontSize: widget.preview ? 19 : 22,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
            child: active && timedWords
                ? TweenAnimationBuilder<double>(
                    key: ValueKey('${line.start.inMilliseconds}:$activeWord'),
                    tween: Tween(begin: 0, end: 1),
                    duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
                    builder: (context, progress, _) => Text.rich(
                      TextSpan(
                        children: [
                          for (var i = 0; i < line.words.length; i++)
                            TextSpan(
                              text: line.words[i].text,
                              style: TextStyle(
                                color: i < activeWord
                                    ? Colors.white
                                    : i == activeWord
                                    ? Color.lerp(Colors.white.withValues(alpha: 0.48), Colors.white, progress)
                                    : Colors.white.withValues(alpha: 0.48),
                              ),
                            ),
                        ],
                      ),
                      maxLines: widget.preview ? 2 : null,
                      overflow: widget.preview ? TextOverflow.ellipsis : null,
                    ),
                  )
                : Text(
                    line.text,
                    maxLines: widget.preview ? 2 : null,
                    overflow: widget.preview ? TextOverflow.ellipsis : null,
                  ),
          ),
        ),
      ),
    );
  }
}
