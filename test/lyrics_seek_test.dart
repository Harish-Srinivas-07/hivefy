import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/components/lyrics_lines.dart';
import 'package:hivefy/components/lyrics_offset.dart';
import 'package:hivefy/services/lyrics.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('tapping synced lines seeks to their adjusted timestamps', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final lyrics = parseLyrics('[00:01.000]First\n[00:10.000]Second', source: 'test', synced: true)!;
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final positions = <Duration>[];
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: LyricsLines(
              songId: 'song',
              lyrics: lyrics,
              positionStream: const Stream.empty(),
              onSeek: positions.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    container.read(lyricsOffsetProvider('song')).value = 1500;
    await tester.pump();
    await tester.tap(find.text('Second'));
    expect(positions.last, const Duration(milliseconds: 11500));
    container.read(lyricsOffsetProvider('song')).value = -2000;
    await tester.pump();
    await tester.tap(find.text('First'));
    expect(positions.last, Duration.zero);
  });

  testWidgets('preview lines seek while plain lyrics do not', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final positions = <Duration>[];
    final timed = parseLyrics('[00:02.000]Timed line', source: 'test', synced: true)!;
    final plain = parseLyrics('Plain line', source: 'test', synced: false)!;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                LyricsLines(
                  songId: 'timed',
                  lyrics: timed,
                  positionStream: const Stream.empty(),
                  preview: true,
                  onSeek: positions.add,
                ),
                Expanded(
                  child: LyricsLines(
                    songId: 'plain',
                    lyrics: plain,
                    positionStream: const Stream.empty(),
                    onSeek: positions.add,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Timed line'));
    await tester.tap(find.text('Plain line'));
    expect(positions, [const Duration(seconds: 2)]);
  });
}
