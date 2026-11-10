import 'package:flutter/material.dart';
import 'package:hivefy/utils/theme.dart';

class CollapsingPageHeader extends StatelessWidget {
  const CollapsingPageHeader({super.key, required this.title, required this.isTitleCollapsed});

  final String title;
  final bool isTitleCollapsed;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 160,
      backgroundColor: getDominantDarker(spotifyGreen),
      leading: const BackButton(color: Colors.white),
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final minHeight = kToolbarHeight;
          final maxHeight = 160.0;
          final collapsePercent = ((constraints.maxHeight - minHeight) / (maxHeight - minHeight)).clamp(0.0, 1.0);

          return FlexibleSpaceBar(
            centerTitle: false,
            titlePadding: EdgeInsets.only(left: isTitleCollapsed ? 72 : 16, bottom: 16, right: 16),
            title: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: isTitleCollapsed ? 1.0 : 0.0,
              child: Text(
                title,
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 22),
              ),
            ),
            background: Container(
              color: spotifyBgColor,
              child: Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 32),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Opacity(
                    opacity: collapsePercent,
                    child: Text(
                      title,
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 28),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
