import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/models/datamodel.dart';
import 'package:hivefy/models/database.dart';
import 'package:hivefy/services/audiohandler.dart';
import 'package:hivefy/shared/constants.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TestAudioPlayer implements AudioPlayer {
  final states = StreamController<PlayerState>.broadcast(sync: true);
  final processing = StreamController<ProcessingState>.broadcast();
  final positions = StreamController<Duration>.broadcast(sync: true);
  final buffered = StreamController<Duration>.broadcast(sync: true);
  final durations = StreamController<Duration?>.broadcast(sync: true);
  final Map<String, Duration> sourceDurations = {};
  final Set<String> failures = {};
  final Set<String> failedUris = {};
  final List<String> loadedIds = [];
  final List<Uri> loadedUris = [];
  AudioSource? _source;
  Duration? _duration;
  Duration _position = Duration.zero;
  ProcessingState _state = ProcessingState.idle;
  bool _playing = false;
  int playCount = 0;

  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Stream<ProcessingState> get processingStateStream => processing.stream;
  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Stream<Duration> get bufferedPositionStream => buffered.stream;
  @override
  Stream<Duration?> get durationStream => durations.stream;
  @override
  AudioSource? get audioSource => _source;
  @override
  Duration? get duration => _duration;
  @override
  Duration get position => _position;
  @override
  Duration get bufferedPosition => Duration.zero;
  @override
  ProcessingState get processingState => _state;
  @override
  bool get playing => _playing;
  @override
  double get speed => 1;

  @override
  Future<void> setLoopMode(LoopMode mode) async {}
  @override
  Future<void> stop() async {
    _playing = false;
    _state = ProcessingState.idle;
    processing.add(_state);
  }

  @override
  Future<void> pause() async {
    _playing = false;
  }

  @override
  Future<void> seek(Duration? position, {int? index}) async {
    _position = position ?? Duration.zero;
    _state = ProcessingState.ready;
  }

  @override
  Future<void> play() {
    _playing = true;
    playCount++;
    return Completer<void>().future;
  }

  @override
  Future<Duration?> setAudioSource(
    AudioSource audioSource, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    final id = ((audioSource as IndexedAudioSource).tag as MediaItem).id;
    if (audioSource is UriAudioSource) loadedUris.add(audioSource.uri);
    loadedIds.add(id);
    if (failures.contains(id) || (audioSource is UriAudioSource && failedUris.contains(audioSource.uri.toString()))) {
      throw StateError('Unable to load $id');
    }
    _source = audioSource;
    _duration = sourceDurations[id];
    _position = Duration.zero;
    _state = ProcessingState.ready;
    durations.add(_duration);
    processing.add(_state);
    return _duration;
  }

  void complete() {
    _state = ProcessingState.completed;
    _position = _duration ?? Duration.zero;
    processing.add(_state);
  }

  void reportDuration(Duration duration) {
    _duration = duration;
    durations.add(duration);
  }

  void reportPosition(Duration position) {
    _position = position;
    positions.add(position);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SongDetail track(String id, int seconds) => SongDetail(
  id: id,
  title: id,
  type: 'song',
  url: '',
  images: [],
  duration: '$seconds',
  downloadUrls: [SourceUrl(quality: 'test', url: 'https://example.com/$id')],
);

Future<void> waitUntil(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  expect(condition(), isTrue, reason: 'Playback did not reach the expected state');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('queue end adds up to ten unique radio songs and plays the first', () async {
    SharedPreferences.setMockInitialValues({});
    hasInternet.value = true;
    final player = TestAudioPlayer();
    final seed = SongDetail(
      id: 'seed',
      title: 'Seed',
      type: 'song',
      url: '',
      images: [],
      ytVideoId: 'seed',
      downloadUrls: [SourceUrl(quality: 'test', url: 'https://example.com/seed')],
    );
    final provider = Provider(
      (ref) => MyAudioHandler(
        ref,
        player: player,
        initializeSystem: false,
        cacheCompletedSong: (_) async {},
        fetchRadioSongs: (_) async => [seed, ...List.generate(12, (i) => track('radio$i', 60))],
      ),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = container.read(provider);
    await handler.loadQueue([seed]);
    player.complete();
    await waitUntil(() => handler.currentSong?.id == 'radio0');
    expect(handler.queueLength, 11);
    expect(handler.queueSongs.map((song) => song.id).toSet().length, 11);
  });

  test('late radio results do not replace a new queue', () async {
    SharedPreferences.setMockInitialValues({});
    hasInternet.value = true;
    final pending = Completer<List<SongDetail>>();
    final requested = Completer<void>();
    final player = TestAudioPlayer();
    final seed = SongDetail(
      id: 'seed',
      title: 'Seed',
      type: 'song',
      url: '',
      images: [],
      ytVideoId: 'seed',
      downloadUrls: [SourceUrl(quality: 'test', url: 'https://example.com/seed')],
    );
    final provider = Provider(
      (ref) => MyAudioHandler(
        ref,
        player: player,
        initializeSystem: false,
        cacheCompletedSong: (_) async {},
        fetchRadioSongs: (_) {
          requested.complete();
          return pending.future;
        },
      ),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = container.read(provider);
    await handler.loadQueue([seed]);
    player.complete();
    await requested.future;
    await handler.loadQueue([track('new', 60)], autoPlay: false);
    pending.complete([track('radio', 60)]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(handler.queueSongs.map((song) => song.id), ['new']);
    expect(handler.currentSong?.id, 'new');
  });

  test('expired queued streams are refreshed before playback', () async {
    SharedPreferences.setMockInitialValues({});
    hasInternet.value = true;
    final song = SongDetail(
      id: 'expired',
      title: 'Expired',
      type: 'song',
      url: '',
      images: [],
      ytVideoId: 'video',
      downloadUrls: [SourceUrl(quality: 'test', url: 'https://example.com/audio?expire=1')],
    );
    final player = TestAudioPlayer();
    final provider = Provider(
      (ref) => MyAudioHandler(
        ref,
        player: player,
        initializeSystem: false,
        resolveStreamUrl: (_) async => 'https://example.com/fresh',
      ),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = container.read(provider);
    await handler.loadQueue([song]);
    expect(player.loadedUris.map((uri) => uri.toString()), ['https://example.com/fresh']);
    expect(handler.currentSong?.id, 'expired');
  });

  test('a rejected YouTube stream is refreshed and retried once', () async {
    SharedPreferences.setMockInitialValues({});
    hasInternet.value = true;
    final song = SongDetail(
      id: 'rejected',
      title: 'Rejected',
      type: 'song',
      url: '',
      images: [],
      ytVideoId: 'video',
      downloadUrls: [SourceUrl(quality: 'test', url: 'https://example.com/rejected')],
    );
    final player = TestAudioPlayer()..failedUris.add('https://example.com/rejected');
    final provider = Provider(
      (ref) => MyAudioHandler(
        ref,
        player: player,
        initializeSystem: false,
        resolveStreamUrl: (_) async => 'https://example.com/fresh',
      ),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = container.read(provider);
    await handler.loadQueue([song]);
    expect(player.loadedUris.map((uri) => uri.toString()), [
      'https://example.com/rejected',
      'https://example.com/fresh',
    ]);
    expect(player.playCount, 1);
  });

  test('a late stream refresh cannot replace a newly selected queue', () async {
    SharedPreferences.setMockInitialValues({});
    hasInternet.value = true;
    final pending = Completer<String?>();
    final started = Completer<void>();
    final song = SongDetail(id: 'old', title: 'Old', type: 'song', url: '', images: [], ytVideoId: 'video');
    final player = TestAudioPlayer();
    final provider = Provider(
      (ref) => MyAudioHandler(
        ref,
        player: player,
        initializeSystem: false,
        resolveStreamUrl: (_) {
          started.complete();
          return pending.future;
        },
      ),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = container.read(provider);
    final oldPlayback = handler.loadQueue([song]);
    await started.future;
    await handler.loadQueue([track('new', 60)], autoPlay: false);
    pending.complete('https://example.com/old');
    await oldPlayback;
    expect(handler.currentSong?.id, 'new');
    expect(player.loadedIds, isEmpty);
  });

  test('an unplayable last song does not restart a completed queue', () async {
    SharedPreferences.setMockInitialValues({});
    hasInternet.value = true;
    final player = TestAudioPlayer()..failures.add('bad');
    final provider = Provider(
      (ref) => MyAudioHandler(ref, player: player, initializeSystem: false, cacheCompletedSong: (_) async {}),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = container.read(provider);
    await handler.loadQueue([track('first', 60), track('bad', 60)]);
    await handler.skipToNext();
    expect(handler.currentIndex, -1);
    await handler.skipToNext();
    await handler.play();
    expect(player.loadedIds, ['first', 'bad']);
    expect(player.playCount, 1);
    expect(handler.currentIndex, -1);
  });

  test('rejects implausible source durations and ignores stale duration events', () async {
    SharedPreferences.setMockInitialValues({});
    hasInternet.value = true;
    final player = TestAudioPlayer()
      ..sourceDurations.addAll({'short': const Duration(minutes: 8), 'next': const Duration(minutes: 2)});
    final provider = Provider((ref) => MyAudioHandler(ref, player: player, initializeSystem: false));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = container.read(provider);
    await handler.loadQueue([track('short', 165), track('next', 120)]);
    expect(handler.mediaItem.value?.duration, const Duration(seconds: 165));
    player.reportDuration(const Duration(minutes: 7));
    expect(handler.mediaItem.value?.duration, const Duration(seconds: 165));
    player.complete();
    await waitUntil(() => handler.mediaItem.value?.id == 'next');
    player.durations.add(const Duration(minutes: 8));
    expect(handler.mediaItem.value?.duration, const Duration(minutes: 2));
  });

  test('advances at the known end when the native duration is implausibly long', () async {
    SharedPreferences.setMockInitialValues({});
    hasInternet.value = true;
    final player = TestAudioPlayer()
      ..sourceDurations.addAll({'short': const Duration(minutes: 8), 'next': const Duration(minutes: 2)});
    final provider = Provider((ref) => MyAudioHandler(ref, player: player, initializeSystem: false));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = container.read(provider);
    await handler.loadQueue([track('short', 165), track('next', 120)]);
    player.reportPosition(const Duration(seconds: 164));
    expect(handler.currentSong?.id, 'short');
    player.reportPosition(const Duration(seconds: 165));
    await waitUntil(() => handler.mediaItem.value?.id == 'next');
    expect(player.loadedIds, ['short', 'next']);
  });

  test('queue is capped at 100 while preserving selected and newly added songs', () async {
    SharedPreferences.setMockInitialValues({});
    hasInternet.value = true;
    final player = TestAudioPlayer();
    final provider = Provider((ref) => MyAudioHandler(ref, player: player, initializeSystem: false));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = container.read(provider);
    final songs = List.generate(150, (index) => track('song$index', 60));

    for (final index in [0, 50, 120, 149]) {
      await handler.loadQueue(songs, startIndex: index, autoPlay: false);
      expect(handler.queueSongs.length, 100);
      expect(handler.currentSong?.id, 'song$index');
      expect(handler.queue.value.length, 100);
    }

    await handler.loadQueue(songs, autoPlay: false);
    await handler.addSongToQueue(track('added', 60));
    expect(handler.queueSongs.length, 100);
    expect(handler.currentSong?.id, 'song0');
    expect(handler.queueSongs.last.id, 'added');
    await handler.addSongNext(track('next', 60));
    expect(handler.queueSongs.length, 100);
    expect(handler.queueSongs[1].id, 'next');
    await handler.playSongNow(track('selected', 60));
    expect(handler.queueSongs.length, 100);
    expect(handler.currentSong?.id, 'selected');
    expect(handler.queue.value.length, 100);
  });

  test('adding to a full shuffled queue keeps the active order and selected song', () async {
    SharedPreferences.setMockInitialValues({});
    final player = TestAudioPlayer();
    final provider = Provider((ref) => MyAudioHandler(ref, player: player, initializeSystem: false));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = container.read(provider);
    await handler.loadQueue(List.generate(100, (index) => track('song$index', 60)), autoPlay: false);
    await handler.toggleShuffle();
    final current = handler.currentSong?.id;
    final previousOrder = handler.queueSongs.map((song) => song.id).toList();
    await handler.addSongNext(track('next', 60));
    expect(handler.isShuffle, isTrue);
    expect(handler.queueSongs.length, 100);
    expect(handler.currentSong?.id, current);
    expect(handler.queueSongs[1].id, 'next');
    expect(handler.queueSongs.skip(2).map((song) => song.id), previousOrder.skip(1).take(98));
  });

  test('restores a YouTube song with a fresh stream without starting playback', () async {
    SharedPreferences.setMockInitialValues({});
    hasInternet.value = true;
    final original = SongDetail(
      id: 'saved',
      title: 'Saved song',
      type: 'song',
      url: '',
      images: [],
      ytVideoId: 'video',
      downloadUrls: [SourceUrl(quality: 'test', url: 'https://example.com/expired')],
    );
    await AppDatabase.saveSongDetail(original);
    await LastQueueStorage.save([original]);
    final player = TestAudioPlayer()..sourceDurations['saved'] = const Duration(minutes: 3);
    final provider = Provider(
      (ref) => MyAudioHandler(
        ref,
        player: player,
        initializeSystem: false,
        resolveStreamUrl: (id) async => 'https://example.com/fresh',
      ),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = container.read(provider);
    await handler.restoreLastPlayed();
    expect(player.loadedUris.single.toString(), 'https://example.com/fresh');
    expect(handler.mediaItem.value?.duration, const Duration(minutes: 3));
    expect(handler.currentSong?.title, 'Saved song');
    expect(player.playCount, 0);
  });

  test('a late restore cannot replace a newly selected queue', () async {
    SharedPreferences.setMockInitialValues({});
    hasInternet.value = true;
    final saved = SongDetail(id: 'saved', title: 'Saved', type: 'song', url: '', images: [], ytVideoId: 'video');
    await AppDatabase.saveSongDetail(saved);
    await LastQueueStorage.save([saved]);
    final resolution = Completer<String?>();
    final player = TestAudioPlayer();
    final provider = Provider(
      (ref) => MyAudioHandler(ref, player: player, initializeSystem: false, resolveStreamUrl: (_) => resolution.future),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = container.read(provider);
    final restore = handler.restoreLastPlayed();
    await waitUntil(() => handler.currentSong?.id == 'saved');
    await handler.loadQueue([track('new', 120)], autoPlay: false);
    resolution.complete('https://example.com/old');
    await restore;
    expect(handler.currentSong?.id, 'new');
    expect(player.loadedIds, isEmpty);
  });

  test('play retries stream resolution if it was unavailable during restore', () async {
    SharedPreferences.setMockInitialValues({});
    hasInternet.value = true;
    final saved = SongDetail(
      id: 'retry',
      title: 'Retry',
      type: 'song',
      url: '',
      images: [],
      ytVideoId: 'video',
      downloadUrls: [SourceUrl(quality: 'test', url: 'https://example.com/expired')],
    );
    await AppDatabase.saveSongDetail(saved);
    await LastQueueStorage.save([saved]);
    var attempts = 0;
    final player = TestAudioPlayer();
    final provider = Provider(
      (ref) => MyAudioHandler(
        ref,
        player: player,
        initializeSystem: false,
        resolveStreamUrl: (_) async => ++attempts == 1 ? null : 'https://example.com/fresh',
      ),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = container.read(provider);
    await handler.restoreLastPlayed();
    expect(player.loadedUris, isEmpty);
    await handler.play();
    expect(player.loadedUris.single.toString(), 'https://example.com/fresh');
    expect(player.playCount, 1);
  });

  test('uses each loaded source duration and advances after playing a new queue from pause', () async {
    SharedPreferences.setMockInitialValues({});
    hasInternet.value = true;
    final player = TestAudioPlayer()
      ..sourceDurations.addAll({'a': const Duration(minutes: 5), 'b': const Duration(minutes: 2)});
    final provider = Provider(
      (ref) => MyAudioHandler(ref, player: player, initializeSystem: false, cacheCompletedSong: (_) async {}),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = container.read(provider);
    final events = <MediaItem?>[];
    final subscription = handler.mediaItem.listen(events.add);
    addTearDown(subscription.cancel);

    await handler.loadQueue([track('a', 240), track('b', 180)]);
    expect(handler.mediaItem.value?.duration, const Duration(minutes: 5));
    await handler.pause();
    await handler.loadQueue([track('a', 240), track('b', 180)]);
    player.complete();
    await waitUntil(() => handler.mediaItem.value?.id == 'b');
    expect(handler.mediaItem.value?.duration, const Duration(minutes: 2));
    expect(
      events
          .whereType<MediaItem>()
          .where((item) => item.id == 'a')
          .every((item) => item.duration == const Duration(minutes: 5)),
      isTrue,
    );
    await waitUntil(() => player.playCount >= 3);
  });

  test('repeat one handles successive completions and can advance after repeat is disabled', () async {
    SharedPreferences.setMockInitialValues({});
    hasInternet.value = true;
    final player = TestAudioPlayer()
      ..sourceDurations.addAll({'a': const Duration(seconds: 3), 'b': const Duration(seconds: 3)});
    final provider = Provider(
      (ref) => MyAudioHandler(ref, player: player, initializeSystem: false, cacheCompletedSong: (_) async {}),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = container.read(provider);
    await handler.loadQueue([track('a', 3), track('b', 3)]);
    handler.toggleRepeatMode();
    handler.toggleRepeatMode();
    player.complete();
    await waitUntil(() => player.playCount == 2);
    player.complete();
    await waitUntil(() => player.playCount == 3);
    expect(handler.currentSong?.id, 'a');
    handler.toggleRepeatMode();
    player.complete();
    await waitUntil(() => handler.mediaItem.value?.id == 'b');
    await waitUntil(() => player.playCount == 4);
  });

  test('skips a source that fails to load and plays the following song', () async {
    SharedPreferences.setMockInitialValues({});
    hasInternet.value = true;
    final player = TestAudioPlayer()
      ..sourceDurations.addAll({'a': const Duration(seconds: 3), 'c': const Duration(seconds: 4)})
      ..failures.add('bad');
    final provider = Provider(
      (ref) => MyAudioHandler(ref, player: player, initializeSystem: false, cacheCompletedSong: (_) async {}),
    );
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final handler = container.read(provider);
    await handler.loadQueue([track('a', 3), track('bad', 3), track('c', 4)]);
    player.complete();
    await waitUntil(() => handler.mediaItem.value?.id == 'c');
    expect(player.loadedIds, ['a', 'bad', 'c']);
    await waitUntil(() => player.playCount == 2);
  });
}
