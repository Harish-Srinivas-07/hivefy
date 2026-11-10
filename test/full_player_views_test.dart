import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/components/shimmers.dart';
import 'package:hivefy/components/player_sheet.dart';
import 'package:hivefy/models/datamodel.dart';
import 'package:hivefy/services/audiohandler.dart';
import 'package:hivefy/services/lyrics.dart';
import 'package:hivefy/shared/constants.dart';
import 'package:hivefy/shared/player.dart';
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Handler extends Fake implements MyAudioHandler {
  _Handler(this.song, {this.extraSongs = const []});
  final SongDetail song;
  final List<SongDetail> extraSongs;
  final skips = <int>[];
  int index = 0;
  final _state = BehaviorSubject<PlaybackState>.seeded(PlaybackState(playing: true));
  final _media = BehaviorSubject<MediaItem?>.seeded(
    const MediaItem(id: 'song', title: 'Song', duration: Duration(seconds: 100)),
  );
  final _queue = BehaviorSubject<List<MediaItem>>.seeded([const MediaItem(id: 'song', title: 'Song')]);
  @override
  BehaviorSubject<PlaybackState> get playbackState => _state;
  @override
  BehaviorSubject<MediaItem?> get mediaItem => _media;
  @override
  BehaviorSubject<List<MediaItem>> get queue => _queue;
  @override
  Stream<PlayerState> get playerStateStream => Stream.value(PlayerState(true, ProcessingState.ready));
  @override
  Stream<Duration> get positionStream => Stream.value(const Duration(seconds: 2));
  @override
  Stream<double> get volumeStream => Stream.value(.5);
  @override
  double get volume => .5;
  @override
  int get currentIndex => index;
  @override
  int get queueLength => 1 + extraSongs.length;
  @override
  List<SongDetail> get queueSongs => [song, ...extraSongs];
  @override
  String? get queueSourceName => 'Test mix';
  @override
  bool get isShuffleChanging => false;
  @override
  bool get hasNext => index + 1 < queueLength;
  @override
  bool get hasPrevious => false;
  @override
  Future<void> seek(Duration position) async {}
  @override
  Future<void> skipToQueueItem(int value) async {
    skips.add(value);
    index = value;
    _state.add(PlaybackState(playing: true));
  }

  @override
  Future<void> setVolume(double value) async {}
  Future<void> disposeStreams() async {
    await _state.close();
    await _media.close();
    await _queue.close();
  }
}

void main() {
  testWidgets('song options move with the title between player and lyrics', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final song = SongDetail(id: 'song', title: 'Song', type: 'song', url: '', images: []);
    final handler = _Handler(song);
    addTearDown(handler.disposeStreams);
    playerSheet.progress.value = 1;
    addTearDown(() => playerSheet.progress.value = 0);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWith((ref) async => handler),
          currentSongProvider.overrideWith((ref) => song),
          songLyricsProvider(song).overrideWith((ref) async => null),
          connectedBluetoothDeviceProvider.overrideWith((ref) => Stream.value(null)),
        ],
        child: const MaterialApp(home: Scaffold(body: FullPlayerScreen())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final options = find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == 'Song options');
    final fullY = tester.getCenter(options).dy;
    await tester.tap(find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == 'Lyrics'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final movingY = tester.getCenter(options).dy;
    await tester.pump(const Duration(milliseconds: 150));
    final compactY = tester.getCenter(options).dy;
    expect(compactY, closeTo(66, .01));
    expect(movingY, lessThan(fullY));
    expect(movingY, greaterThan(compactY));

    await tester.tap(find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == 'Lyrics'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.getCenter(options).dy, greaterThan(compactY));
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.getCenter(options).dy, closeTo(fullY, .01));
  });

  testWidgets('reversing a sheet drag does not scroll the player content', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final song = SongDetail(id: 'song', title: 'Song', type: 'song', url: '', images: []);
    final handler = _Handler(song);
    final scrollController = ScrollController();
    addTearDown(handler.disposeStreams);
    addTearDown(scrollController.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWith((ref) async => handler),
          currentSongProvider.overrideWith((ref) => song),
          songLyricsProvider(song).overrideWith((ref) async => null),
          connectedBluetoothDeviceProvider.overrideWith((ref) => Stream.value(null)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: PlayerSheetLayer(
              player: FullPlayerScreen(scrollController: scrollController),
              artwork: const ColoredBox(color: Colors.blue),
            ),
          ),
        ),
      ),
    );
    playerSheet.prepare();
    playerSheet.dragTo(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final gesture = await tester.startGesture(const Offset(195, 350));
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();
    final draggedDown = playerSheet.progress.value;
    expect(draggedDown, lessThan(1));
    await gesture.moveBy(const Offset(0, -60));
    await tester.pump();
    expect(playerSheet.progress.value, greaterThan(draggedDown));
    expect(scrollController.offset, 0);
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    playerSheet.engaged.value = false;
    playerSheet.progress.value = 0;
  });

  for (final size in [const Size(360, 640), const Size(390, 844)]) {
    testWidgets('lyrics and queue controls stay raised above the bottom at $size', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final song = SongDetail(id: 'song', title: 'Song', type: 'song', url: '', images: []);
      final handler = _Handler(song);
      addTearDown(handler.disposeStreams);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioHandlerProvider.overrideWith((ref) async => handler),
            currentSongProvider.overrideWith((ref) => song),
            songLyricsProvider(song).overrideWith((ref) async => null),
            connectedBluetoothDeviceProvider.overrideWith((ref) => Stream.value(null)),
          ],
          child: const MaterialApp(home: Scaffold(body: FullPlayerScreen())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final lyrics = find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == 'Lyrics');
      final queue = find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == 'Queue');
      expect(tester.getBottomLeft(lyrics).dy, lessThan(size.height - 30));
      expect(tester.getCenter(queue).dy, closeTo(tester.getCenter(lyrics).dy, .01));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final size in [const Size(360, 640), const Size(320, 568)]) {
    testWidgets('player switches between inline lyrics and queue at $size', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final song = SongDetail(id: 'song', title: 'Song', type: 'song', url: '', images: []);
      const lyrics = Lyrics(
        lines: [LyricLine(Duration.zero, 'First line')],
        isSynced: true,
        source: 'Test',
        raw: 'First line',
      );
      final handler = _Handler(song);
      addTearDown(handler.disposeStreams);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioHandlerProvider.overrideWith((ref) async => handler),
            currentSongProvider.overrideWith((ref) => song),
            songLyricsProvider(song).overrideWith((ref) async => lyrics),
            connectedBluetoothDeviceProvider.overrideWith((ref) => Stream.value(null)),
          ],
          child: const MaterialApp(home: Scaffold(body: FullPlayerScreen())),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('This phone'), findsOneWidget);
      expect(find.text('Playing Test mix'), findsOneWidget);
      final lyricsCenter = tester.getCenter(
        find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == 'Lyrics'),
      );
      final outputCenter = tester.getCenter(find.text('This phone'));
      final queueCenter = tester.getCenter(
        find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == 'Queue'),
      );
      final playControl = find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == 'Pause');
      final playControlY = tester.getCenter(playControl).dy;
      final lyricsControlY = lyricsCenter.dy;
      final queueControlY = queueCenter.dy;
      expect(outputCenter.dx, greaterThan(lyricsCenter.dx));
      expect(outputCenter.dx, lessThan(queueCenter.dx));
      expect(tester.getSize(find.byType(PageView)).width, size.width);
      expect(tester.getSize(find.byType(PageView)).height, closeTo((size.height * .52).clamp(0.0, size.width), .01));
      expect(tester.getSize(find.byKey(const ValueKey('full-player-artwork'))).width, size.width);
      expect(
        tester.getTopLeft(find.text('Song').first).dx,
        closeTo(tester.getTopLeft(find.byType(PlayerSeekBar)).dx + 24 * (size.height < 600 ? .68 : .82), .01),
      );
      expect(
        find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == 'Audio output'),
        findsNothing,
      );
      expect(find.text('First line'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == 'Lyrics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('inline-lyrics')), findsOneWidget);
      expect(tester.getCenter(playControl).dy, closeTo(playControlY, .01));
      expect(
        tester
            .getCenter(find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == 'Lyrics'))
            .dy,
        closeTo(lyricsControlY, .01),
      );
      expect(
        tester
            .getCenter(find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == 'Queue'))
            .dy,
        closeTo(queueControlY, .01),
      );
      expect(tester.getSize(find.byKey(const ValueKey('full-player-artwork'))).width, 56);
      expect(tester.getTopLeft(find.byKey(const ValueKey('full-player-artwork'))).dx, 20);
      final compactImage = find.descendant(
        of: find.byKey(const ValueKey('full-player-artwork')),
        matching: find.byType(CacheNetWorkImg),
      );
      expect(tester.getSize(compactImage), const Size(56, 56));
      expect(tester.getCenter(compactImage), tester.getCenter(find.byKey(const ValueKey('full-player-artwork'))));
      expect(find.text('Lyrics by Test'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Lyrics by Test')).dy,
        greaterThan(tester.getTopLeft(find.text('First line')).dy),
      );
      expect(
        tester.getTopLeft(find.text('Lyrics by Test')).dy,
        lessThan(tester.getTopLeft(find.byType(PlayerSeekBar)).dy),
      );
      expect(find.byType(PlayerSeekBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == 'Queue'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('inline-queue')), findsOneWidget);
      expect(find.text('Now playing'), findsNothing);
      expect(find.text('Song'), findsOneWidget);
      expect(tester.getCenter(playControl).dy, closeTo(playControlY, .01));
      expect(
        tester
            .getCenter(find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == 'Lyrics'))
            .dy,
        closeTo(lyricsControlY, .01),
      );
      expect(
        tester
            .getCenter(
              find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == 'Close queue'),
            )
            .dy,
        closeTo(queueControlY, .01),
      );
      expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
      expect(find.text('This phone'), findsNothing);
      expect(tester.getCenter(find.byIcon(Icons.volume_up_rounded)).dy, closeTo(queueControlY, .01));
      expect(tester.takeException(), isNull);
      await tester.tap(
        find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == 'Close queue'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(const ValueKey('inline-queue')), findsNothing);
      expect(find.byType(PlayerSeekBar), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('artwork swipe selects the next song without playback updates snapping it back', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final song = SongDetail(id: 'song', title: 'Song', type: 'song', url: '', images: []);
    final next = SongDetail(id: 'next', title: 'Next', type: 'song', url: '', images: []);
    final handler = _Handler(song, extraSongs: [next]);
    addTearDown(handler.disposeStreams);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          audioHandlerProvider.overrideWith((ref) async => handler),
          currentSongProvider.overrideWith((ref) => song),
          songLyricsProvider(song).overrideWith((ref) async => null),
          connectedBluetoothDeviceProvider.overrideWith((ref) => Stream.value('AirPods')),
        ],
        child: const MaterialApp(home: Scaffold(body: FullPlayerScreen())),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final page = find.byType(PageView);
    await tester.drag(page, const Offset(0, -120));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    final gesture = await tester.startGesture(tester.getCenter(page));
    await gesture.moveBy(const Offset(-30, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(-200, 0));
    await tester.pump();
    handler._state.add(PlaybackState(playing: true));
    await tester.pump();
    expect(tester.widget<PageView>(page).controller!.page!, greaterThan(.3));
    expect(handler.skips, isEmpty);
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(handler.skips, [1]);
    expect(tester.widget<PageView>(page).controller!.page, 1);
    expect(find.byIcon(Icons.earbuds_rounded), findsOneWidget);
    expect(
      tester.getCenter(find.byIcon(Icons.earbuds_rounded)).dx,
      greaterThan(
        tester
            .getCenter(find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == 'Lyrics'))
            .dx,
      ),
    );
    expect(
      tester.getCenter(find.byIcon(Icons.earbuds_rounded)).dx,
      lessThan(
        tester
            .getCenter(find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == 'Queue'))
            .dx,
      ),
    );
    await tester.tap(find.byIcon(Icons.earbuds_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Audio Output'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    Navigator.of(tester.element(find.text('Audio Output'))).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  for (final size in [const Size(844, 390), const Size(480, 250), const Size(1024, 1366)]) {
    testWidgets('player fits $size with large system text', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final song = SongDetail(id: 'song', title: 'Song', type: 'song', url: '', images: []);
      const lyrics = Lyrics(
        lines: [LyricLine(Duration.zero, 'First line')],
        isSynced: true,
        source: 'Test',
        raw: 'First line',
      );
      final handler = _Handler(song);
      addTearDown(handler.disposeStreams);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            audioHandlerProvider.overrideWith((ref) async => handler),
            currentSongProvider.overrideWith((ref) => song),
            songLyricsProvider(song).overrideWith((ref) async => lyrics),
            connectedBluetoothDeviceProvider.overrideWith((ref) => Stream.value(null)),
          ],
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(size: size, textScaler: const TextScaler.linear(1.8)),
              child: const Scaffold(body: FullPlayerScreen()),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final artwork = tester.getSize(find.byType(PageView));
      expect(artwork.width, lessThanOrEqualTo(560));
      if (size.width > size.height) {
        expect(artwork.height, closeTo(artwork.width, .01));
        expect(tester.getTopLeft(find.byType(PlayerSeekBar)).dx, greaterThanOrEqualTo(artwork.width));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
