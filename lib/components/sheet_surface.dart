import 'package:flutter/material.dart';

/// A dark surface that does not need to re-filter the player during animation.
class SheetSurface extends StatelessWidget {
  const SheetSurface({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xff303030), Color(0xff1b1b1b)],
      ),
    ),
    child: child,
  );
}
