import 'package:flutter/material.dart';

import '../utils/theme.dart';

class StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  StickyHeaderDelegate({required this.child, this.height = 60});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    // SizedBox.expand ensures the returned child fills the header's allocated height
    return SizedBox(
      height: height,
      child: Material(
        // optional: keep background / elevation behavior consistent
        color: spotifyBgColor,
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant StickyHeaderDelegate old) {
    return old.height != height || old.child != child;
  }
}
