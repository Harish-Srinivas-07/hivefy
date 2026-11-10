import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/components/lyrics_lines.dart';
import 'package:hivefy/components/lyrics_offset.dart';
import 'package:hivefy/models/datamodel.dart';
import 'package:hivefy/services/lyrics.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses timed LRC and finds the correct line after seeking', () {
    final lyrics = parseLyrics(
      '[offset:100]\n[00:02.5][00:07.25]Repeat\n[00:01.000]First',
      source: 'test',
      synced: true,
    )!;
    expect(lyrics.lines.map((line) => line.text), ['First', 'Repeat', 'Repeat']);
    expect(lyrics.indexAt(const Duration(milliseconds: 1099)), -1);
    expect(lyrics.indexAt(const Duration(milliseconds: 1100)), 0);
    expect(lyrics.indexAt(const Duration(milliseconds: 7350)), 2);
    expect(parseLyrics('[ar:Artist]', source: 'test', synced: true), isNull);
  });

  test('selects closest timed search match and caches it', () async {
    SharedPreferences.setMockInitialValues({});
    final dio = Dio();
    var requests = 0;
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requests++;
          if (options.path.endsWith('/get')) {
            handler.resolve(Response(requestOptions: options, data: {}));
          } else {
            handler.resolve(
              Response(
                requestOptions: options,
                data: [
                  {'duration': 183, 'syncedLyrics': '[00:01.00]Further'},
                  {'duration': 181, 'syncedLyrics': '[00:01.00]Closest'},
                  {'duration': 250, 'syncedLyrics': '[00:01.00]Wrong length'},
                ],
              ),
            );
          }
        },
      ),
    );
    final song = SongDetail(
      id: 'lyrics-test',
      title: 'Track',
      type: 'song',
      url: '',
      images: [],
      primaryArtists: 'Artist',
      duration: '180',
      ytVideoId: 'video',
    );
    final service = LyricsService(dio: dio, youtubeLyrics: (_) async => null);
    final result = await service.fetch(song);
    expect(result?.lines.single.text, 'Closest');
    expect(result?.isSynced, isTrue);
    expect(requests, 2);
    expect((await service.fetch(song))?.lines.single.text, 'Closest');
    expect(requests, 2);
  });

  test('falls back to video lyrics without pretending they are synced', () async {
    SharedPreferences.setMockInitialValues({});
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(onRequest: (options, handler) => handler.reject(DioException(requestOptions: options))),
    );
    final song = SongDetail(
      id: 'fallback-test',
      title: 'Track',
      type: 'song',
      url: '',
      images: [],
      primaryArtists: 'Artist',
      ytVideoId: 'video',
    );
    final lyrics = await LyricsService(dio: dio, youtubeLyrics: (_) async => 'First line\nSecond line').fetch(song);
    expect(lyrics?.isSynced, isFalse);
    expect(lyrics?.lines.length, 2);
    expect(lyrics?.indexAt(const Duration(minutes: 1)), -1);
  });

  test('stops as soon as a provider returns usable lyrics', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <String>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options.path);
            handler.resolve(Response(requestOptions: options, data: {'plainLyrics': 'Immediate lyrics'}));
          },
        ),
      );
    final song = SongDetail(
      id: 'first-hit',
      title: 'Track',
      type: 'song',
      url: '',
      images: [],
      primaryArtists: 'Artist',
      ytVideoId: 'video',
    );
    final lyrics = await LyricsService(
      dio: dio,
      youtubeLyrics: (_) async => throw StateError('should not be called'),
    ).fetch(song);
    expect(lyrics?.lines.single.text, 'Immediate lyrics');
    expect(requests.length, 1);
  });

  test('a provider request bypasses a different cached source and saves only after selection', () async {
    SharedPreferences.setMockInitialValues({});
    final song = SongDetail(
      id: 'switch',
      title: 'Track',
      type: 'song',
      url: '',
      images: [],
      primaryArtists: 'Artist',
      ytVideoId: 'video',
    );
    final cached = parseLyrics('Old lyrics', source: 'LRCLIB', synced: false)!;
    var lyricRequests = 0;
    var transcriptRequests = 0;
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) =>
              handler.reject(DioException(requestOptions: options, error: 'Unexpected provider request')),
        ),
      );
    final service = LyricsService(
      dio: dio,
      youtubeLyrics: (_) async {
        lyricRequests++;
        return 'New lyrics';
      },
      youtubeTranscript: (_) async {
        transcriptRequests++;
        return null;
      },
    );
    await service.saveSelection(song, cached);
    final result = await service.fetch(song, provider: LyricsProvider.youtubeMusic);
    expect(result?.source, 'YouTube Music');
    expect(lyricRequests, 1);
    expect(transcriptRequests, 0);
    expect((await service.fetch(song))?.source, 'LRCLIB');
    await service.saveSelection(song, result!);
    expect((await service.fetch(song))?.source, 'YouTube Music');
  });

  test('falls through to Unison and parses timed TTML safely', () async {
    SharedPreferences.setMockInitialValues({});
    final requests = <String>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options.path);
            if (options.path.contains('unison')) {
              handler.resolve(
                Response(
                  requestOptions: options,
                  data: {
                    'success': true,
                    'data': {
                      'format': 'ttml',
                      'lyrics': '<tt><body><p begin="00:00:01.500">Hello <span>world</span></p></body></tt>',
                    },
                  },
                ),
              );
            } else {
              handler.reject(DioException(requestOptions: options));
            }
          },
        ),
      );
    final song = SongDetail(
      id: 'unison-test',
      title: 'Track',
      type: 'song',
      url: '',
      images: [],
      primaryArtists: 'Artist',
      ytVideoId: 'video',
    );
    final lyrics = await LyricsService(
      dio: dio,
      youtubeLyrics: (_) async => null,
      youtubeTranscript: (_) async => null,
    ).fetch(song);
    expect(lyrics?.source, 'Unison');
    expect(lyrics?.lines.single.text, 'Hello world');
    expect(lyrics?.lines.single.start, const Duration(milliseconds: 1500));
    expect(requests.any((url) => url.contains('kugou')), isFalse);
    expect(parseLyrics('<!DOCTYPE tt><tt><p begin="1s">bad</p></tt>', source: 'test', synced: true), isNull);
  });

  test('tries KuGou after earlier sources fail and decodes its timed lyrics', () async {
    SharedPreferences.setMockInitialValues({});
    final calls = <String>[];
    final dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            calls.add(options.path);
            dynamic data;
            if (options.path.contains('mobileservice.kugou.com')) {
              data = {
                'data': {
                  'info': [
                    {'duration': 180, 'hash': 'track-hash'},
                  ],
                },
              };
            } else if (options.path.contains('lyrics.kugou.com/search')) {
              data = {
                'candidates': [
                  {'id': 1, 'accesskey': 'key'},
                ],
              };
            } else if (options.path.contains('lyrics.kugou.com/download')) {
              data = {'content': base64.encode(utf8.encode('[00:02.00]Kugou line'))};
            } else {
              handler.reject(DioException(requestOptions: options));
              return;
            }
            handler.resolve(Response(requestOptions: options, data: data));
          },
        ),
      );
    final song = SongDetail(
      id: 'kugou-test',
      title: 'Track',
      type: 'song',
      url: '',
      images: [],
      primaryArtists: 'Artist',
      duration: '180',
      ytVideoId: 'video',
    );
    final lyrics = await LyricsService(
      dio: dio,
      youtubeLyrics: (_) async => null,
      youtubeTranscript: (_) async => null,
    ).fetch(song);
    expect(lyrics?.source, 'KuGou');
    expect(lyrics?.lines.single.text, 'Kugou line');
    expect(
      calls.indexWhere((url) => url.contains('unison')),
      lessThan(calls.indexWhere((url) => url.contains('mobileservice'))),
    );
  });

  testWidgets('offset controls persist per song and affect timing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final position = StreamController<Duration>.broadcast();
    addTearDown(position.close);
    final lyrics = parseLyrics('[00:01.00]First\n[00:02.00]Second', source: 'test', synced: true)!;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                LyricsLines(lyrics: lyrics, songId: 'offset', positionStream: position.stream, preview: true),
                const LyricsOffsetSheet(songId: 'offset'),
              ],
            ),
          ),
        ),
      ),
    );
    position.add(const Duration(milliseconds: 2200));
    await tester.pump();
    await tester.pumpAndSettle();
    final scrollable = find.descendant(of: find.byType(LyricsLines), matching: find.byType(Scrollable));
    expect(tester.state<ScrollableState>(scrollable).position.pixels, greaterThan(0));
    await tester.tap(find.byTooltip('Increase offset'));
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(scrollable).position.pixels, 0);
    expect(find.text('First'), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getInt('lyrics_offset_offset'), 500);
  });

  testWidgets('preview follows playback and seeking', (tester) async {
    final position = StreamController<Duration>.broadcast();
    addTearDown(position.close);
    final lyrics = parseLyrics(
      '[00:01.00]First\n[00:03.00]Second\n[00:05.00]Third\n[00:07.00]Fourth',
      source: 'test',
      synced: true,
    )!;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: LyricsLines(lyrics: lyrics, songId: 'preview', positionStream: position.stream, preview: true),
          ),
        ),
      ),
    );
    position.add(const Duration(seconds: 5));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Third'), findsOneWidget);
    expect(find.text('Fourth'), findsOneWidget);
    final scrollable = find.descendant(of: find.byType(LyricsLines), matching: find.byType(Scrollable));
    expect(tester.state<ScrollableState>(scrollable).position.pixels, greaterThan(0));
    position.add(const Duration(seconds: 1));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('First'), findsOneWidget);
    expect(tester.state<ScrollableState>(scrollable).position.pixels, 0);
  });
}
