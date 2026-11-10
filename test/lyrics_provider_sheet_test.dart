import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/components/lyrics_provider_sheet.dart';
import 'package:hivefy/models/datamodel.dart';
import 'package:hivefy/services/lyrics.dart';
import 'package:hivefy/shared/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeLyricsService extends LyricsService {
  final Map<LyricsProvider, Completer<Lyrics?>> requests = {};
  @override
  Future<Lyrics?> fetch(SongDetail song, {LyricsProvider? provider}) {
    return requests.putIfAbsent(provider!, () => Completer<Lyrics?>()).future;
  }
}

void main() {
  testWidgets('provider sheet checks, disables unavailable results, and switches on success', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final song = SongDetail(id: 'song', title: 'Track', type: 'song', url: '', images: []);
    final original = parseLyrics('Original', source: 'LRCLIB', synced: false)!;
    final replacement = parseLyrics('[00:01.00]New lyrics', source: 'Unison', synced: true)!;
    final service = FakeLyricsService();
    final container = ProviderContainer(overrides: [lyricsServiceProvider.overrideWithValue(service)]);
    addTearDown(container.dispose);
    container.read(currentSongProvider.notifier).state = song;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                final selected = ref.watch(selectedLyricsProvider(song.id)) ?? original;
                return Column(
                  children: [
                    Text('Selected: ${selected.source}'),
                    TextButton(
                      onPressed: () => showModalBottomSheet<void>(
                        context: context,
                        builder: (_) => LyricsProviderSheet(song: song, currentLyrics: selected),
                      ),
                      child: const Text('Open'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Current provider'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    await tester.tap(find.text('YouTube Music'));
    await tester.pump();
    expect(find.text('Checking…'), findsOneWidget);
    service.requests[LyricsProvider.youtubeMusic]!.complete(null);
    await tester.pump();
    expect(find.text('Not available'), findsOneWidget);
    final unavailable = tester.widget<ListTile>(
      find.ancestor(of: find.text('YouTube Music'), matching: find.byType(ListTile)),
    );
    expect(unavailable.enabled, isFalse);
    expect(find.text('Selected: LRCLIB'), findsOneWidget);

    await tester.tap(find.text('Unison'));
    await tester.pump();
    service.requests[LyricsProvider.unison]!.complete(replacement);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Selected: Unison'), findsOneWidget);
    final restored = await LyricsService().fetch(song);
    expect(restored?.source, 'Unison');
  });

  testWidgets('a result for a previous song does not replace lyrics after a song change', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final song = SongDetail(id: 'old-song', title: 'Old', type: 'song', url: '', images: []);
    final next = SongDetail(id: 'new-song', title: 'New', type: 'song', url: '', images: []);
    final original = parseLyrics('Original', source: 'LRCLIB', synced: false)!;
    final service = FakeLyricsService();
    final container = ProviderContainer(overrides: [lyricsServiceProvider.overrideWithValue(service)]);
    addTearDown(container.dispose);
    container.read(currentSongProvider.notifier).state = song;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (_) => LyricsProviderSheet(song: song, currentLyrics: original),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unison'));
    await tester.pump();
    container.read(currentSongProvider.notifier).state = next;
    await tester.pump();
    service.requests[LyricsProvider.unison]!.complete(parseLyrics('Old result', source: 'Unison', synced: false));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getString('lyrics_v1_old-song'), isNull);
  });
}
