import 'dart:async';

import 'package:flutter/material.dart';

/// A short, bounded stagger so long lists never leave items hidden for long.
class StaggeredAppearance extends StatefulWidget {
  const StaggeredAppearance({
    super.key,
    required this.index,
    required this.child,
    this.delayStep = const Duration(milliseconds: 45),
    this.fadeDuration = const Duration(milliseconds: 240),
    this.slideDuration = const Duration(milliseconds: 300),
  });

  final int index;
  final Widget child;
  final Duration delayStep;
  final Duration fadeDuration;
  final Duration slideDuration;

  @override
  State<StaggeredAppearance> createState() => _StaggeredAppearanceState();
}

class _StaggeredAppearanceState extends State<StaggeredAppearance> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delayStep * widget.index.clamp(0, 6), () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: widget.fadeDuration,
      curve: Curves.easeOut,
      child: AnimatedSlide(
        offset: _visible ? Offset.zero : const Offset(0, 0.06),
        duration: widget.slideDuration,
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
