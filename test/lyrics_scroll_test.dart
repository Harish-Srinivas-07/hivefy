import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/components/lyrics_lines.dart';
import 'package:hivefy/components/staggered_appearance.dart';
import 'package:hivefy/services/lyrics.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('player lyrics appear one line at a time', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final positions = StreamController<Duration>.broadcast();
    addTearDown(positions.close);
    final lyrics = parseLyrics('[00:01.00]First\n[00:02.00]Second', source: 'test', synced: true)!;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: LyricsLines(songId: 'entrance', lyrics: lyrics, positionStream: positions.stream, glassStyle: true),
          ),
        ),
      ),
    );

    double targetOpacity(String line) {
      final entrance = find.ancestor(of: find.text(line), matching: find.byType(StaggeredAppearance));
      return tester
          .widget<AnimatedOpacity>(find.descendant(of: entrance, matching: find.byType(AnimatedOpacity)))
          .opacity;
    }

    await tester.pump(const Duration(milliseconds: 30));
    expect(targetOpacity('First'), 1);
    expect(targetOpacity('Second'), 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(targetOpacity('Second'), 1);
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('preview slides existing lines upward and keeps the final line visible', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final positions = StreamController<Duration>.broadcast();
    addTearDown(positions.close);
    final lyrics = parseLyrics('[00:01.00]First\n[00:02.00]Second\n[00:03.00]Third', source: 'test', synced: true)!;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: LyricsLines(songId: 'slide', lyrics: lyrics, positionStream: positions.stream, preview: true),
          ),
        ),
      ),
    );
    positions.add(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scroll.position.pixels, 0);
    final initialY = tester.getTopLeft(find.text('First')).dy;

    positions.add(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 150));
    expect(scroll.position.pixels, greaterThan(0));
    expect(tester.getTopLeft(find.text('First')).dy, lessThan(initialY));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);

    positions.add(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    final lastOffset = scroll.position.pixels;
    expect(lastOffset, greaterThan(0));
    expect(find.text('Third'), findsOneWidget);
    positions.add(const Duration(seconds: 20));
    await tester.pumpAndSettle();
    expect(scroll.position.pixels, lastOffset);
  });

  testWidgets('full lyrics scroll without moving an enclosing player scroll view', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final positions = StreamController<Duration>.broadcast();
    addTearDown(positions.close);
    final outer = ScrollController();
    addTearDown(outer.dispose);
    final lyrics = parseLyrics('[00:01.00]First\n[00:02.00]Second', source: 'test', synced: true)!;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: outer,
              child: SizedBox(
                height: 200,
                child: LyricsLines(songId: 'full', lyrics: lyrics, positionStream: positions.stream),
              ),
            ),
          ),
        ),
      ),
    );
    positions.add(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    positions.add(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    final inner = tester.state<ScrollableState>(
      find.descendant(of: find.byType(LyricsLines), matching: find.byType(Scrollable)),
    );
    expect(inner.position.pixels, greaterThan(0));
    expect(outer.offset, 0);
  });
}
