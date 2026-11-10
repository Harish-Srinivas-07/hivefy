import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/components/lyrics_lines.dart';
import 'package:hivefy/components/lyrics_offset.dart';
import 'package:hivefy/services/lyrics.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('parses timed TTML fragments without adding spaces between syllables', () {
    final lyrics = parseLyrics(
      '<tt xmlns:ttm="urn:test"><body><p begin="1s"><span begin="1s" end="1.4s">Hel</span><span begin="1.4s" end="2s">lo </span><span begin="2s">world</span><span ttm:role="x-bg">ignored</span></p></body></tt>',
      source: 'test',
      synced: true,
    )!;
    expect(lyrics.lines.single.text, 'Hello world');
    expect(lyrics.lines.single.words.map((word) => word.text), ['Hel', 'lo ', 'world']);
    expect(lyrics.lines.single.words.map((word) => word.start), [
      const Duration(seconds: 1),
      const Duration(milliseconds: 1400),
      const Duration(seconds: 2),
    ]);
    expect(lyrics.lines.single.words.first.end, const Duration(milliseconds: 1400));
  });

  test('parses enhanced LRC timings and preserves plain LRC behavior', () {
    final lyrics = parseLyrics(
      '[offset:200]\n[00:01.00]<00:01.00>Hello <00:02.50>world',
      source: 'test',
      synced: true,
    )!;
    expect(lyrics.lines.single.text, 'Hello world');
    expect(lyrics.lines.single.words.map((word) => word.start), [
      const Duration(milliseconds: 1200),
      const Duration(milliseconds: 2700),
    ]);
    expect(parseLyrics('[00:01.00]Ordinary line', source: 'test', synced: true)!.lines.single.words, isEmpty);
  });

  testWidgets('word highlighting follows timestamps, offset and backwards seeking', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final lyric = parseLyrics('[00:01.00]<00:01.00>Hello <00:02.00>world', source: 'test', synced: true)!;
    final positions = StreamController<Duration>.broadcast();
    addTearDown(positions.close);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: LyricsLines(songId: 'word-song', lyrics: lyric, positionStream: positions.stream, preview: true),
          ),
        ),
      ),
    );
    await tester.pump();
    final lyricStyle = tester.widget<AnimatedDefaultTextStyle>(
      find.ancestor(of: find.text('Hello world'), matching: find.byType(AnimatedDefaultTextStyle)).first,
    );
    expect(lyricStyle.style.fontFamily, startsWith('Manrope'));
    container.read(lyricsOffsetProvider('word-song')).value = 500;
    await tester.pump();
    final text = find.byWidgetPredicate((widget) => widget is Text && widget.textSpan?.toPlainText() == 'Hello world');
    List<InlineSpan> spans() => (tester.widget<Text>(text).textSpan! as TextSpan).children!;

    positions.add(const Duration(milliseconds: 1700));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 250));
    expect((spans()[0] as TextSpan).style!.color, Colors.white);
    expect((spans()[1] as TextSpan).style!.color, Colors.white.withValues(alpha: 0.48));

    positions.add(const Duration(milliseconds: 2700));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 250));
    expect((spans()[1] as TextSpan).style!.color, Colors.white);
    positions.add(const Duration(milliseconds: 1700));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 250));
    expect((spans()[1] as TextSpan).style!.color, Colors.white.withValues(alpha: 0.48));
  });
}
