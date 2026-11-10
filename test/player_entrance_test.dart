import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/components/player_sheet.dart';

void main() {
  testWidgets('player elements reveal in order as the sheet expands and reverse with it', (tester) async {
    playerSheet.progress.value = 0;
    addTearDown(() => playerSheet.progress.value = 0);
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            PlayerEntrance(begin: .3, end: .6, child: Text('Title')),
            PlayerEntrance(begin: .7, end: .9, child: Text('Controls')),
          ],
        ),
      ),
    );
    double opacity(String text) => tester
        .widget<Opacity>(find.ancestor(of: find.text(text, skipOffstage: false), matching: find.byType(Opacity)).first)
        .opacity;

    expect(opacity('Title'), 0);
    expect(opacity('Controls'), 0);
    playerSheet.progress.value = .65;
    await tester.pump();
    expect(opacity('Title'), 1);
    expect(opacity('Controls'), 0);
    playerSheet.progress.value = 1;
    await tester.pump();
    expect(opacity('Controls'), 1);
    playerSheet.progress.value = .4;
    await tester.pump();
    expect(opacity('Title'), greaterThan(0));
    expect(opacity('Title'), lessThan(1));
    expect(opacity('Controls'), 0);
  });

  testWidgets('reduced motion shows player elements immediately', (tester) async {
    playerSheet.progress.value = 0;
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: PlayerEntrance(begin: .7, end: 1, child: Text('Controls')),
        ),
      ),
    );
    final opacity = tester.widget<Opacity>(find.ancestor(of: find.text('Controls'), matching: find.byType(Opacity)));
    expect(opacity.opacity, 1);
  });
}
