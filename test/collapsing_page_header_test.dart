import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/components/collapsing_page_header.dart';
import 'package:hivefy/utils/theme.dart';

void main() {
  testWidgets('preserves expanded and collapsed header styling', (tester) async {
    Future<void> pumpHeader(bool collapsed) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomScrollView(
              slivers: [CollapsingPageHeader(title: 'Settings', isTitleCollapsed: collapsed)],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpHeader(false);
    final appBar = tester.widget<SliverAppBar>(find.byType(SliverAppBar));
    expect(appBar.pinned, isTrue);
    expect(appBar.expandedHeight, 160);
    expect(appBar.backgroundColor, getDominantDarker(spotifyGreen));
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 0);
    expect(find.text('Settings', skipOffstage: false), findsNWidgets(2));

    await pumpHeader(true);
    expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 1);
    final flexibleSpace = tester.widget<FlexibleSpaceBar>(find.byType(FlexibleSpaceBar));
    expect(flexibleSpace.titlePadding, const EdgeInsets.only(left: 72, bottom: 16, right: 16));
  });
}
