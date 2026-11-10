import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/components/staggered_appearance.dart';

void main() {
  testWidgets('items appear in sequence and settle', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            StaggeredAppearance(index: 0, child: Text('first')),
            StaggeredAppearance(index: 4, child: Text('later')),
          ],
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 100));
    final first = tester.widget<AnimatedOpacity>(
      find.ancestor(of: find.text('first'), matching: find.byType(AnimatedOpacity)).first,
    );
    final later = tester.widget<AnimatedOpacity>(
      find.ancestor(of: find.text('later'), matching: find.byType(AnimatedOpacity)).first,
    );
    expect(first.opacity, 1);
    expect(later.opacity, 0);
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AnimatedOpacity>(find.ancestor(of: find.text('later'), matching: find.byType(AnimatedOpacity)).first)
          .opacity,
      1,
    );
  });
}
