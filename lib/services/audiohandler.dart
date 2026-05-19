// lib/services/audiohandler.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/snackbar.dart';
import '../shared/player.dart';
import '../utils/theme.dart';
import 'defaultfetcher.dart';
import '../models/database.dart';
import '../models/datamodel.dart';
import 'offlinemanager.dart';
import '../services/jiosaavn.dart';
import '../shared/constants.dart';
import 'shufflemanager.dart';

enum RepeatMode { none, one, all }

/// One provider to rule them all 🚀
final audioHandlerProvider = FutureProvider<MyAudioHandler>((ref) async {
  final handler = await AudioService.init(
    builder: () => MyAudioHandler(ref),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.hivemind.hivefy.channel.audio',
      androidNotificationChannelName: 'Hivefy Audio Player',
      androidNotificationIcon: 'drawable/ic_launcher_foreground',
      androidShowNotificationBadge: true,
      androidResumeOnClick: true,
      androidStopForegroundOnPause: true,
      androidNotificationOngoing: true,
    ),
  );
  return handler;
});

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final Ref ref;
  final AudioPlayer _player = AudioPlayer();

  // Flags
  bool _isTransitioning = false;
  int _skipRetryCount = 0;
  static const int _maxSkipRetries = 5;
  bool _ignoreNextCompletion = false;

  // Shuffle manager
  final ShuffleManager _shuffleManager = ShuffleManager();
  ShuffleManager get shuffleManager => _shuffleManager;

  List<SongDetail> _queue = [];
  int _currentIndex = -1;

  Duration _lastPosition = Duration.zero;
  Timer? _playbackTimer;
  Timer? _bufferingTimer;

  final ValueNotifier<bool> _noInternetStop = ValueNotifier(false);
  ValueNotifier<bool> get noInternetStop => _noInternetStop;

  Stream<double> get volumeStream => _player.volumeStream;
  double get volume => _player.volume;

  MyAudioHandler(this.ref) {
    // keep system playbackState in sync
    _player.playerStateStream.listen(_updatePlaybackState);

    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.buffering) {
        _bufferingTimer?.cancel();
        _bufferingTimer = Timer(const Duration(seconds: 10), () async {
          if (_player.processingState == ProcessingState.buffering) {
            debugPrint("⚠️ Buffering timeout. Stopping.");
            await softStop();
            // 🚨 Show unstable network notification
            info("Unstable network. Pausing playback.", Severity.warning);
            _noInternetStop.value = true;
            Future.delayed(const Duration(seconds: 5), () {
              _noInternetStop.value = false;
            });
          }
        });
      } else {
        _bufferingTimer?.cancel();
      }
    });

    _player.setLoopMode(LoopMode.off); // Ensure loop is off by default
    _setupAudioSession();

    _player.positionStream.listen((pos) {
      final old = playbackState.value;
      playbackState.add(
        old.copyWith(
          updatePosition: pos,
          bufferedPosition: _player.bufferedPosition,
        ),
      );
    });

    _player.processingStateStream.listen((state) async {
      if (state == ProcessingState.completed) {
        await _onSongEnded();
      }
    });

    _player.bufferedPositionStream.listen((buf) {
      final old = playbackState.value;
      playbackState.add(old.copyWith(bufferedPosition: buf));
    });

    _player.durationStream.listen((dur) {
      final current = mediaItem.value;
      if (current != null && dur != null && current.duration != dur) {
        mediaItem.add(current.copyWith(duration: dur));
      }
    });

    _player.positionStream.listen((pos) async {
      final current = currentSong;
      if (current == null) return;

      final delta = pos - _lastPosition;
      if (delta.inSeconds >= 5) {
        _lastPosition = pos;

        _playbackTimer?.cancel();
        _playbackTimer = Timer(const Duration(seconds: 1), () async {
          await AppDatabase.addPlayedDuration(current.id, delta);
        });
      }
    });

    // Watchdog for stuck playback at end of song
    _player.positionStream.listen((pos) {
      final dur = _player.duration;
      if (dur != null &&
          pos >= dur &&
          pos > Duration.zero &&
          _player.playing &&
          !_isTransitioning &&
          _player.processingState != ProcessingState.completed) {
        debugPrint(
          "⚠️ Watchdog: Song stuck at end ($pos / $dur). Forcing completion.",
        );
        _onSongEnded(force: true);
      }
    });

    // resume last played song if exists
    Future.delayed(const Duration(seconds: 3)).then((_) {
      _initLastPlayed();
    });

    // 🌐 Internet Connectivity Watchdog
    hasInternet.addListener(() {
      if (!hasInternet.value) {
        final current = currentSong;
        if (current != null &&
            !offlineManager.isAvailableOffline(songId: current.id)) {
          if (_player.playing) {
            debugPrint("🌐 Lost internet. Pausing online song.");
            pause();
            // 🚨 Show lost connection notification
            info("Connection lost. Paused playback.", Severity.warning);
          }
        }
      }
    });
  }

  Future<void> _setupAudioSession() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    bool wasPlayingBeforeInterruption = false;

    // Listen to interruptions (e.g. phone calls)
    session.interruptionEventStream.listen((event) {
      if (event.begin) {
        wasPlayingBeforeInterruption = _player.playing;
        switch (event.type) {
          case AudioInterruptionType.pause:
            _player.pause();
            break;
          case AudioInterruptionType.duck:
            _player.setVolume(0.3);
            break;
          case AudioInterruptionType.unknown:
            break;
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.pause:
            if (wasPlayingBeforeInterruption) {
              _player.play();
            }
            break;
          case AudioInterruptionType.duck:
            _player.setVolume(1.0);
            break;
          case AudioInterruptionType.unknown:
            break;
        }
      }
    });

    // Listen to device changes (e.g. unplugging headphones)
    session.becomingNoisyEventStream.listen((_) {
      _player.pause();
    });
  }

  // --- Public getters
  SongDetail? get currentSong =>
      (_currentIndex >= 0 && _currentIndex < _queue.length)
      ? _queue[_currentIndex]
      : null;

  // safe hasNext / hasPrevious
  bool get hasNext => _currentIndex >= 0 && (_currentIndex + 1 < _queue.length);

  bool get hasPrevious => _currentIndex >= 0 && _queue.isNotEmpty;

  RepeatMode _repeat = RepeatMode.none;
  RepeatMode get repeatMode => _repeat;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  int get queueLength => _queue.length;
  List<SongDetail> get queueSongs => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;

  // --- Shuffle & repeat

  bool isShuffleChanging = false;
  bool get isShuffle => _shuffleManager.isShuffling;

  Future<void> toggleShuffle() async {
    if (_queue.isEmpty) return;

    isShuffleChanging = true;

    final current = currentSong;

    // Ensure ShuffleManager has the latest queue
    _shuffleManager.loadQueue(
      List.from(_queue),
      currentIndex: _currentIndex,
      clearHistory: false,
    );

    // Toggle shuffle state
    _shuffleManager.toggleShuffle(currentSong: current);

    // Sync handler queue and index
    _queue = List.from(_shuffleManager.currentQueue);
    _currentIndex = _shuffleManager.currentIndex;

    // Notify listeners
    queue.add(_queue.map(songToMediaItem).toList());
    ref.read(shuffleProvider.notifier).state = _shuffleManager.isShuffling;

    isShuffleChanging = false;
  }

  /// Explicitly turn shuffle OFF safely
  Future<void> disableShuffle() async {
    if (_shuffleManager.isShuffling) {
      final current = currentSong;

      // Toggle shuffle off without touching original playlist order
      _shuffleManager.toggleShuffle(currentSong: current);

      // Sync handler queue/index with original queue
      _queue = List.from(_shuffleManager.currentQueue);
      _currentIndex = _shuffleManager.currentIndex;

      // Notify listeners
      queue.add(_queue.map(songToMediaItem).toList());
      ref.read(shuffleProvider.notifier).state = false;
    }
  }

  Future<void> clearQueue({bool resetShuffle = true}) async {
    _isTransitioning = true;

    try {
      await _player.stop();

      _queue.clear();
      _currentIndex = -1;

      _queueSourceId = null;
      _queueSourceName = null;

      mediaItem.add(null);
      queue.add([]);

      if (resetShuffle) {
        _shuffleManager.loadQueue([]);
        ref.read(shuffleProvider.notifier).state = false;
      }

      await LastQueueStorage.clear();

      playbackState.add(
        playbackState.value.copyWith(
          playing: false,
          processingState: AudioProcessingState.idle,
          updatePosition: Duration.zero,
          bufferedPosition: Duration.zero,
          queueIndex: -1,
        ),
      );
    } finally {
      _isTransitioning = false;
    }
  }

  Future<void> _enforceQueueLimit() async {
    if (_queue.length > 100) {
      final cutoff = _queue.length - 100;
      if (_currentIndex >= cutoff) {
        _currentIndex -= cutoff;
      } else {
        _currentIndex = 0;
      }
      _queue = _queue.sublist(cutoff);

      // Sync with ShuffleManager (reloads queue to handle truncation safely)
      _shuffleManager.loadQueue(_queue, currentIndex: _currentIndex);

      await LastQueueStorage.save(_queue, currentIndex: _currentIndex);
    }
  }

  void updateQueueFromShuffle() {
    _queue = _shuffleManager.currentQueue;
    _currentIndex = _shuffleManager.currentIndex;
  }

  void toggleRepeatMode() {
    switch (_repeat) {
      case RepeatMode.none:
        _repeat = RepeatMode.all;
        break;
      case RepeatMode.all:
        _repeat = RepeatMode.one;
        break;
      case RepeatMode.one:
        _repeat = RepeatMode.none;
        break;
    }
    ref.read(repeatModeProvider.notifier).state = _repeat;
  }

  // --- AudioHandler API
  bool _isPausedManually = false;

  @override
  Future<void> pause() async {
    _isPausedManually = true;
    playbackState.add(playbackState.value.copyWith(playing: false));
    await _player.pause();
    await _player.pause(); // temporary bug need to fix later
  }

  @override
  Future<void> play() async {
    _isPausedManually = false;

    final current = currentSong;
    if (current != null &&
        !hasInternet.value &&
        !offlineManager.isAvailableOffline(songId: current.id)) {
      debugPrint("🚫 Cannot play online song while offline.");
      info("No internet. Cannot play online track.", Severity.warning);
      _noInternetStop.value = true;
      Future.delayed(const Duration(seconds: 3), () {
        _noInternetStop.value = false;
      });
      return;
    }

    if (_currentIndex < 0 && _queue.isNotEmpty) {
      _currentIndex = 0;
      await _playCurrent();
    } else {
      await _player.play();
    }
  }

  Future<void> _onSongEnded({bool force = false}) async {
    final paused = _isPausedManually;
    final transitioning = _isTransitioning;
    final ignore = _ignoreNextCompletion;

    debugPrint(
      '🏁 onSongEnded paused=$paused transitioning=$transitioning ignore=$ignore force=$force',
    );

    // 1. If we are already transitioning, ignore this completion event.
    // It's likely a side effect of stopping the player during transition.
    if (_isTransitioning) {
      debugPrint('⏭ Already transitioning. Ignoring completion event.');
      return;
    }

    // 2. Ignore "ghost" completions if explicitly flagged (e.g. from skip)
    if (_ignoreNextCompletion) {
      _ignoreNextCompletion = false;
      debugPrint('⏭ Ignored ghost completion');
      return;
    }

    // 3. Respect manual pause
    if (_isPausedManually && !force) {
      debugPrint('⏸ Song was paused manually, not advancing');
      return;
    }

    // 4. Trigger auto-cache (FIRE AND FORGET - do not await)
    final current = currentSong;
    if (current != null && !force) {
      // "listened full song" criteria met naturally here
      // Run unawaited to ensure it doesn't block the UI thread ever
      Future.microtask(() => offlineManager.cacheSong(current.id));
    }

    // 5. Advance to next song
    await _advanceToNext(manual: false, force: force);
  }

  Future<int?> _getNextPlayableIndex({
    int start = -1,
    bool backward = false,
  }) async {
    if (_queue.isEmpty) return null;

    final idx = start < 0 ? _currentIndex : start;
    if (backward) {
      if (idx <= 0) return null;
      return idx - 1;
    } else {
      if (idx >= _queue.length - 1) return null;
      return idx + 1;
    }
  }

  Future<void> _advanceToNext({
    required bool manual,
    bool force = false,
  }) async {
    debugPrint(
      '➡️ advanceToNext(manual=$manual) index=$_currentIndex '
      'shuffle=${_shuffleManager.isShuffling} repeat=$_repeat transitioning=$_isTransitioning',
    );

    if (_queue.isEmpty) return; // still block if empty

    // Relaxed check: Allow advance if explicitly completed OR if position >= duration - 500ms
    final threshold = const Duration(milliseconds: 500);
    final hasFinished =
        _player.processingState == ProcessingState.completed ||
        (_player.duration != null &&
            _player.position >= _player.duration! - threshold &&
            _player.position > Duration.zero);

    if (!force && !manual && (_isTransitioning || !hasFinished)) {
      return;
    }

    _isTransitioning = true;

    try {
      _ignoreNextCompletion = true;
      await _player.stop();

      // Handle repeat-one mode
      if (_repeat == RepeatMode.one && !manual) {
        await _player.seek(Duration.zero);
        await _player.play();
        return;
      }

      int? nextIndex;

      // Use ShuffleManager or regular logic
      if (_shuffleManager.isShuffling) {
        _shuffleManager.updateCurrentIndex(_currentIndex);
        nextIndex = _shuffleManager.getNextIndex();
      } else {
        nextIndex = await _getNextPlayableIndex();
      }

      if (nextIndex != null) {
        _currentIndex = nextIndex;
        _shuffleManager.updateCurrentIndex(_currentIndex);

        final song = _queue[_currentIndex];
        _shuffleManager.registerPlay(song);

        await _playCurrent(skipCompletedCheck: true);
        _skipRetryCount = 0;
        return;
      }

      // Handle repeat-all
      if (_repeat == RepeatMode.all && _queue.isNotEmpty) {
        if (_shuffleManager.isShuffling) {
          _shuffleManager.loadQueue(
            List.from(_shuffleManager.originalQueue),
            currentIndex: 0,
            clearHistory: true,
          );
          _queue = List.from(_shuffleManager.currentQueue);
        }
        _currentIndex = 0;
        _shuffleManager.updateCurrentIndex(0);
        await _playCurrent(skipCompletedCheck: true);
        _skipRetryCount = 0;
        return;
      }

      // No more songs - full stop
      debugPrint("🛑 End of queue reached. Stopping.");
      await _player.pause(); // Ensure paused first
      await softStop();

      _currentIndex = -1;
      _skipRetryCount = 0;
      mediaItem.add(null);

      // Explicitly force idle state to update UI immediately
      await Future.delayed(const Duration(milliseconds: 150));

      playbackState.add(
        playbackState.value.copyWith(
          playing: false,
          processingState: AudioProcessingState.idle,
          controls: [], // Clear controls
          systemActions: {}, // Clear system actions
          updatePosition: Duration.zero,
          bufferedPosition: Duration.zero,
          queueIndex: -1,
        ),
      );
    } finally {
      _isTransitioning = false;
    }
  }

  @override
  Future<void> skipToNext() async {
    debugPrint(
      '⏭️ skipToNext tapped | index=$_currentIndex transitioning=$_isTransitioning',
    );

    _ignoreNextCompletion = true; // Suppress any completion from aborted source
    await _advanceToNext(manual: true);
  }

  Future<void> addSongNext(SongDetail song) async {
    if (_queue.any((s) => s.id == song.id)) return;

    final insertIndex = (_currentIndex + 1).clamp(0, _queue.length);
    _queue.insert(insertIndex, song);

    // Sync with ShuffleManager
    _shuffleManager.insertSong(insertIndex, song);

    final updated = List<MediaItem>.from(queue.value);
    updated.insert(insertIndex, songToMediaItem(song));
    queue.add(updated);
    await LastQueueStorage.save(_queue, currentIndex: _currentIndex);
  }

  Future<void> addSongToQueue(SongDetail song) async {
    if (_queue.any((s) => s.id == song.id)) return;

    _queue.add(song);

    // Sync with ShuffleManager
    _shuffleManager.addSong(song);

    await _enforceQueueLimit();

    final updated = List<MediaItem>.from(queue.value)
      ..add(songToMediaItem(song));
    queue.add(updated);
    await LastQueueStorage.save(_queue, currentIndex: _currentIndex);
  }

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> stop() async {
    await _player.stop();
    await super.stop();
  }

  Future<void> softStop() async {
    _isPausedManually = true;
    await _player.pause();
    await _player.pause(); // temporary bug need to fix later
    await _player.seek(Duration.zero);

    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
        updatePosition: Duration.zero,
      ),
    );
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index >= 0 && index < _queue.length) {
      _currentIndex = index;
      _shuffleManager.updateCurrentIndex(index);
      await _playCurrent();
    }
  }

  @override
  Future<void> onTaskRemoved() async {
    await stop();
    return super.onTaskRemoved();
  }

  @override
  Future<void> seek(Duration position) async {
    await _player.seek(position);
    final old = playbackState.value;
    playbackState.add(old.copyWith(updatePosition: position));
  }

  @override
  Future<void> skipToPrevious() async {
    if (_queue.isEmpty) return; // Allow interruption even if transitioning!

    // Smart Previous: If played > 3s, restart song
    if (_player.position.inSeconds > 3) {
      await seek(Duration.zero);
      if (!_player.playing) {
        await play();
      }
      return;
    }

    _isTransitioning = true;
    _ignoreNextCompletion = true;

    try {
      await _player.stop();
      if (_repeat == RepeatMode.one) {
        await _player.seek(Duration.zero);
        await _player.play();
        return;
      }

      int? prevIndex;

      if (_shuffleManager.isShuffling) {
        _shuffleManager.updateCurrentIndex(_currentIndex);
        prevIndex = _shuffleManager.getPreviousIndex();
      } else if (hasPrevious) {
        prevIndex = _currentIndex - 1;
      }

      if (prevIndex != null && prevIndex >= 0) {
        _currentIndex = prevIndex;
        _shuffleManager.updateCurrentIndex(_currentIndex);
        await _playCurrent(skipCompletedCheck: true);
        _skipRetryCount = 0;
      } else if (_repeat == RepeatMode.all) {
        _currentIndex = _queue.length - 1;
        _shuffleManager.updateCurrentIndex(_currentIndex);
        await _playCurrent(skipCompletedCheck: true);
        _skipRetryCount = 0;
      } else {
        // Fallback: If no previous song exists (first song in queue and no repeat-all),
        // restart the current song from the beginning.
        await seek(Duration.zero);
        if (!_player.playing) {
          await play();
        }
      }
    } finally {
      _isTransitioning = false;
    }
  }

  @override
  Future<void> playMediaItem(MediaItem mediaItem) async {
    final idx = _queue.indexWhere((s) => s.id == mediaItem.id);
    if (idx >= 0 && idx != _currentIndex) {
      _currentIndex = idx;
      _shuffleManager.updateCurrentIndex(idx);
      await _playCurrent();
    } else {
      await _player.play();
    }
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    final song = await AppDatabase.getSong(mediaItem.id);
    if (song == null) return;

    // Avoid duplicates
    if (_queue.any((s) => s.id == song.id)) return;
    _queue.add(song);
    await _enforceQueueLimit();

    // 🔹 Update shuffle list without re-toggling shuffle
    _shuffleManager.addSong(song);

    queue.add(_queue.map(songToMediaItem).toList());
  }

  String? _queueSourceId;
  String? _queueNature;
  String? _queueSourceName;

  String? get queueSourceId => _queueSourceId;
  String? get queueNature => _queueNature;
  String? get queueSourceName => _queueSourceName;

  Future<void> loadQueue(
    List<SongDetail> songs, {
    int startIndex = 0,
    String? sourceId,
    String? nature,
    String? sourceName,
    bool autoPlay = true,
  }) async {
    await clearQueue(resetShuffle: false);

    _queueSourceId = sourceId;
    _queueSourceName = sourceName;
    _queueNature = nature;

    if (songs.isEmpty) return;
    _queue = List.from(songs);
    await _enforceQueueLimit();

    final safeStartIndex = startIndex.clamp(0, _queue.length - 1);

    // 🔹 Always load through shuffle manager for unified state
    _shuffleManager.loadQueue(_queue, currentIndex: safeStartIndex);

    if (_shuffleManager.isShuffling) {
      _queue = _shuffleManager.currentQueue;
      _currentIndex = _shuffleManager.currentIndex;
    } else {
      _currentIndex = safeStartIndex;
    }

    queue.add(_queue.map(songToMediaItem).toList());
    await LastQueueStorage.save(_queue, currentIndex: _currentIndex);

    if (autoPlay) await _playCurrent();
  }

  Future<void> playSongNow(SongDetail song, {bool insertNext = false}) async {
    final existingIndex = _queue.indexWhere((s) => s.id == song.id);

    if (existingIndex >= 0) {
      _currentIndex = existingIndex;
      _shuffleManager.updateCurrentIndex(existingIndex);
    } else {
      final insertIndex = insertNext
          ? (_currentIndex + 1).clamp(0, _queue.length)
          : _queue.length;

      _queue.insert(insertIndex, song);
      _currentIndex = insertIndex;

      // Sync with ShuffleManager
      _shuffleManager.insertSong(insertIndex, song);
      _shuffleManager.updateCurrentIndex(insertIndex);

      queue.add(_queue.map(songToMediaItem).toList());
      _queueSourceName = song.album;
      _queueSourceId = 'Search';
    }

    await LastQueueStorage.save(_queue, currentIndex: _currentIndex);
    await _playCurrent();
  }

  // --- Helpers
  Future<void> _playCurrent({bool skipCompletedCheck = false}) async {
    debugPrint(
      '▶️ playCurrent index=$_currentIndex'
      ' retry=$_skipRetryCount'
      ' ignoreCompletion=$_ignoreNextCompletion',
    );

    if (_currentIndex < 0 || _currentIndex >= _queue.length) {
      await softStop();
      return;
    }

    // Circuit breaker for consecutive failures
    if (_skipRetryCount >= _maxSkipRetries) {
      debugPrint('⚠️ Too many consecutive skip failures. Stopping.');
      await softStop();
      _skipRetryCount = 0;
      _playbackTimer?.cancel();
      _lastPosition = Duration.zero;
      return;
    }

    // Reset duration tracking for new song
    _playbackTimer?.cancel();
    _lastPosition = Duration.zero;

    var song = _queue[_currentIndex];

    // Fetch details if missing
    if (song.downloadUrls.isEmpty) {
      final fetched = await SaavnAPI().getSongDetails(ids: [song.id]);
      if (fetched.isNotEmpty) {
        song = fetched.first;
        _queue[_currentIndex] = song;

        // 🔹 Sync updated song metadata with ShuffleManager
        _shuffleManager.updateSongInQueue(song);

        await AppDatabase.saveSongDetail(song);
      }
    }

    // NO RECURSIVE CALLS - break the loop cleanly
    if (song.downloadUrls.isEmpty) {
      info('Song has no playable URL', Severity.warning);
      _skipRetryCount++;

      if (skipCompletedCheck) {
        // Already in transition, don't recurse
        return;
      }

      // Advance to next only if this was the initial attempt
      await _advanceToNext(manual: true);
      return;
    }

    // Update state
    ref.read(currentSongProvider.notifier).state = song;
    await LastQueueStorage.save(_queue, currentIndex: _currentIndex);
    await LastPlayedSongStorage.save(song);

    try {
      // Pause to prevent state reset issues
      if (_player.playing) {
        _ignoreNextCompletion = true;
        await _player.pause();
      }

      final localPath = offlineManager.getLocalPath(song.id);

      if (localPath != null && File(localPath).existsSync()) {
        debugPrint("▶ Playing offline: $localPath");
        await _player.setAudioSource(
          AudioSource.uri(Uri.file(localPath), tag: songToMediaItem(song)),
        );
      } else {
        if (!hasInternet.value) {
          debugPrint("⚠️ No internet and song not cached. Skipping.");
          _skipRetryCount++;
          await _tryNextOfflineOrStop();
          return;
        }
        debugPrint("▶ Playing online: ${song.downloadUrls.last.url}");
        await _player.setAudioSource(
          AudioSource.uri(
            Uri.parse(song.downloadUrls.last.url),
            tag: songToMediaItem(song),
          ),
        );
      }

      mediaItem.add(songToMediaItem(song));
      // 🚀 Bluetooth Sync Fix: Force state update and wait before playing
      // to ensure slow head units capture the new MediaItem metadata.
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.ready,
        ),
      );
      await Future.delayed(const Duration(milliseconds: 200));
      _player.play();
      debugPrint("✅ Playback started successfully for ${song.title}");

      _ignoreNextCompletion = false;
      _shuffleManager.registerPlay(song);

      // Reset retry count on successful play
      _skipRetryCount = 0;
    } catch (e, st) {
      debugPrint("❌ Error loading song ${song.title}: $e\n$st");
      _skipRetryCount++;

      if (skipCompletedCheck) {
        // Already in transition, don't recurse
        return;
      }

      // Advance to next only if this was the initial attempt
      debugPrint("⏭️ Retrying with next song due to error...");
      await _advanceToNext(manual: true);
    }
  }

  Future<void> _tryNextOfflineOrStop() async {
    // Look ahead in queue for any cached/downloaded song
    for (int i = _currentIndex + 1; i < _queue.length; i++) {
      final song = _queue[i];
      final localPath = offlineManager.getLocalPath(song.id);
      if (localPath != null && File(localPath).existsSync()) {
        _currentIndex = i;
        _shuffleManager.updateCurrentIndex(i);
        await _playCurrent(skipCompletedCheck: true);
        return;
      }
    }

    // No offline songs found ahead
    debugPrint("🛑 No offline songs available. Stopping.");
    await softStop();
    _noInternetStop.value = true;
    Future.delayed(const Duration(seconds: 5), () {
      _noInternetStop.value = false;
    });
  }

  Future<void> _updatePlaybackState(PlayerState ps) async {
    final hasMedia = mediaItem.value != null;
    final position = _player.position;

    final effectiveControls = [
      if (hasPrevious) MediaControl.skipToPrevious,
      ps.playing ? MediaControl.pause : MediaControl.play,
      MediaControl.stop,
      if (hasNext) MediaControl.skipToNext,
    ];

    // Find the index of Play/Pause and Next within the CURRENT list
    List<int> compactIndices = [];
    if (effectiveControls.contains(MediaControl.skipToPrevious)) {
      compactIndices.add(
        effectiveControls.indexOf(MediaControl.skipToPrevious),
      );
    }
    compactIndices.add(
      effectiveControls.indexWhere(
        (c) => c == MediaControl.play || c == MediaControl.pause,
      ),
    );
    if (effectiveControls.contains(MediaControl.skipToNext)) {
      compactIndices.add(effectiveControls.indexOf(MediaControl.skipToNext));
    }

    final processingState = {
      ProcessingState.idle: hasMedia
          ? AudioProcessingState.ready
          : AudioProcessingState.idle,
      ProcessingState.loading: AudioProcessingState.loading,
      ProcessingState.buffering: AudioProcessingState.buffering,
      ProcessingState.ready: AudioProcessingState.ready,
      ProcessingState.completed: AudioProcessingState.completed,
    }[ps.processingState]!;

    playbackState.add(
      playbackState.value.copyWith(
        playing: ps.playing,
        processingState: processingState,
        updatePosition: position,
        bufferedPosition: _player.bufferedPosition,
        controls: effectiveControls,
        androidCompactActionIndices: compactIndices,
        systemActions: const {
          // Scrubber (Seek bar) support
          MediaAction.seek,

          // Previous / Next Track support
          MediaAction.skipToNext,
          MediaAction.skipToPrevious,

          // Playback Toggle support (Headset buttons)
          MediaAction.playPause,

          // Direct voice command support
          MediaAction.play,
          MediaAction.pause,
          MediaAction.stop,
        },
        queueIndex: _currentIndex,
        // 🚀 Progress Bar Fix: Stop interpolation during loading/buffering
        speed:
            (ps.processingState == ProcessingState.buffering ||
                ps.processingState == ProcessingState.loading)
            ? 0.0
            : _player.speed,
      ),
    );
  }

  Future<void> _initLastPlayed() async {
    debugPrint('--> Initializing last played queue...');
    final lastQueueData = await LastQueueStorage.load();

    // 🔹 Reset shuffle manager properly
    _shuffleManager.loadQueue([]);
    ref.read(shuffleProvider.notifier).state = false;
    debugPrint('--> ShuffleManager reset to non-shuffling mode');

    if (lastQueueData != null) {
      final songs = lastQueueData.songs;
      final startIndex = lastQueueData.currentIndex;
      _queueSourceId = 'Last played';
      _queueSourceName = 'Last Played';

      if (songs.isNotEmpty) {
        debugPrint('--> Restoring queue: $lastQueueData');
        _queue = List.from(songs);
        _currentIndex = startIndex.clamp(0, _queue.length - 1);

        // 🔹 Sync with ShuffleManager (non-shuffling on restore)
        _shuffleManager.loadQueue(_queue, currentIndex: _currentIndex);

        queue.add(_queue.map(songToMediaItem).toList());
        await LastQueueStorage.save(_queue, currentIndex: _currentIndex);

        final current = _queue[_currentIndex];
        ref.read(currentSongProvider.notifier).state = current;

        // 🔹 Use single audio source to match manual queue management
        try {
          final local = offlineManager.getLocalPath(current.id);
          final uri = (local != null && File(local).existsSync())
              ? Uri.file(local)
              : (current.downloadUrls.isNotEmpty
                    ? Uri.parse(current.downloadUrls.last.url)
                    : null);

          if (uri != null) {
            await _player.setAudioSource(
              AudioSource.uri(uri, tag: songToMediaItem(current)),
              initialPosition: Duration.zero,
            );
          } else {
            debugPrint('⚠️ Initial song has no playable URL');
          }

          mediaItem.add(songToMediaItem(current));

          unawaited(() async {
            if (current.images.isNotEmpty) {
              final dominant = await getDominantColorFromImage(
                current.images.last.url,
              );
              ref.read(playerColourProvider.notifier).state = getDominantDarker(
                dominant,
              );
            }
          }());

          debugPrint('--> Last played queue restored (single source mode).');
        } catch (e, st) {
          debugPrint('--> initLastPlayed (queue loaded) error: $e\n$st');
        }

        return;
      }
    }

    // 🔹 fallback: restore single last played song if full queue not found
    final last = await LastPlayedSongStorage.load();
    if (last != null) {
      _queue = [last];
      _currentIndex = 0;

      // 🔹 Sync with ShuffleManager
      _shuffleManager.loadQueue(_queue, currentIndex: _currentIndex);

      queue.add([songToMediaItem(last)]);
      _queueSourceName = 'Last Played';
      _queueSourceId = last.id;
      ref.read(currentSongProvider.notifier).state = last;

      try {
        final localPath = offlineManager.getLocalPath(last.id);
        final uri = (localPath != null && File(localPath).existsSync())
            ? Uri.file(localPath)
            : (last.downloadUrls.isNotEmpty
                  ? Uri.parse(last.downloadUrls.last.url)
                  : null);

        if (uri == null) {
          debugPrint('⚠️ Fallback last-played song has no playable URL');
          return;
        }

        await _player.setAudioSource(
          AudioSource.uri(uri, tag: songToMediaItem(last)),
        );

        mediaItem.add(songToMediaItem(last));

        if (last.images.isNotEmpty) {
          final dominant = await getDominantColorFromImage(
            last.images.last.url,
          );
          ref.read(playerColourProvider.notifier).state = getDominantDarker(
            dominant,
          );
        }

        debugPrint('--> Fallback single last-played loaded (not autoplaying).');
      } catch (e, st) {
        debugPrint('--> initLastPlayed (single) error: $e\n$st');
      }
    }
  }
}

MediaItem songToMediaItem(SongDetail song) {
  return MediaItem(
    id: song.id,
    title: song.title.isNotEmpty ? song.title : 'Unknown',
    album: song.albumName ?? song.album,
    artist: song.primaryArtists.isNotEmpty
        ? song.primaryArtists
        : (song.contributors.primary.isNotEmpty
              ? song.contributors.primary.map((a) => a.title).join(", ")
              : 'Unknown'),
    genre: song.albumName ?? song.album,
    duration: song.duration != null
        ? Duration(seconds: int.tryParse(song.duration!) ?? 0)
        : null,
    artUri: (song.images.isNotEmpty && song.images.last.url.isNotEmpty)
        ? Uri.tryParse(song.images.last.url)
        : null,
    artHeaders: {},
    displayTitle: song.title.isNotEmpty ? song.title : 'Unknown',
    displaySubtitle: song.albumName ?? song.album,
    displayDescription: song.description,
    extras: {
      'explicit': song.explicitContent.toString(),
      'language': song.language,
      'label': song.label ?? '',
      'year': song.year?.toString() ?? '',
      'releaseDate': song.releaseDate ?? '',
      'contributors_primary': song.contributors.primary
          .map((a) => a.title)
          .toList(),
      'contributors_featured': song.contributors.featured
          .map((a) => a.title)
          .toList(),
      'contributors_all': song.contributors.all.map((a) => a.title).toList(),
      'downloadUrls': song.downloadUrls
          .map((d) => {'url': d.url, 'quality': d.quality})
          .toList(),
    },
  );
}
