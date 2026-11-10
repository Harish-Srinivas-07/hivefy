import 'package:flutter/material.dart';

/// Hides the navigation bar while scrolling through content and reveals it as
/// soon as the user scrolls back toward the top.
class ScrollAwareNavigation extends StatefulWidget {
  const ScrollAwareNavigation({
    super.key,
    required this.body,
    required this.navigationBar,
    required this.tabIndex,
    this.drawer,
    this.scaffoldKey,
    this.backgroundColor,
  });

  final Widget body;
  final Widget navigationBar;
  final int tabIndex;
  final Widget? drawer;
  final GlobalKey<ScaffoldState>? scaffoldKey;
  final Color? backgroundColor;

  @override
  State<ScrollAwareNavigation> createState() => _ScrollAwareNavigationState();
}

class _ScrollAwareNavigationState extends State<ScrollAwareNavigation> {
  bool _visible = true;
  double _distance = 0;

  @override
  void didUpdateWidget(covariant ScrollAwareNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabIndex != widget.tabIndex) {
      _visible = true;
      _distance = 0;
    }
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is ScrollStartNotification && notification.dragDetails != null) {
      _distance = 0;
    } else if (notification is ScrollUpdateNotification && notification.dragDetails != null) {
      final delta = notification.scrollDelta ?? 0;
      if (delta == 0) return false;
      if (_distance.sign != delta.sign) _distance = 0;
      _distance += delta;
      if (_visible && _distance >= 16) {
        setState(() => _visible = false);
        _distance = 0;
      } else if (!_visible && _distance <= -6) {
        setState(() => _visible = true);
        _distance = 0;
      }
    } else if (notification is OverscrollNotification &&
        notification.dragDetails != null &&
        notification.overscroll < 0 &&
        !_visible) {
      setState(() => _visible = true);
      _distance = 0;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: widget.scaffoldKey,
      backgroundColor: widget.backgroundColor,
      drawer: widget.drawer,
      body: NotificationListener<ScrollNotification>(onNotification: _onScroll, child: widget.body),
      bottomNavigationBar: AnimatedSize(
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: Alignment.bottomCenter,
        child: ClipRect(
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: _visible ? 1 : 0,
            child: IgnorePointer(
              ignoring: !_visible,
              child: ExcludeSemantics(excluding: !_visible, child: widget.navigationBar),
            ),
          ),
        ),
      ),
    );
  }
}
