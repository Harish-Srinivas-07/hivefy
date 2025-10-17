// lib/shared/audio_handler.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
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
      // androidStopForegroundOnPause: false,
    ),
  );
  return handler;
});

class MyAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  final Ref ref;
  final AudioPlayer _player = AudioPlayer();

  List<SongDetail> _queue = [];
  int _currentIndex = -1;

  bool _shuffle = false;
  RepeatMode _repeat = RepeatMode.none;

  MyAudioHandler(this.ref) {
    // keep system playbackState in sync
    _player.playerStateStream.listen(_updatePlaybackState);

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

    // duration watch
    Duration lastPosition = Duration.zero;
    Timer? playbackTimer;

    _player.positionStream.listen((pos) async {
      final current = currentSong;
      if (current == null) return;

      final delta = pos - lastPosition;
      if (delta.inSeconds >= 5) {
        // only update every 5 seconds
        lastPosition = pos;

        playbackTimer?.cancel();
        playbackTimer = Timer(const Duration(seconds: 1), () async {
          await AppDatabase.addPlayedDuration(current.id, delta);
        });
      }
    });

    // resume last played song if exists
    disableShuffle(); // turn shuffle off
    _initLastPlayed();
  }

  // --- Public getters
  SongDetail? get currentSong =>
      (_currentIndex >= 0 && _currentIndex < _queue.length)
          ? _queue[_currentIndex]
          : null;

  // safe hasNext / hasPrevious
  bool get hasNext => _currentIndex >= 0 && (_currentIndex + 1 < _queue.length);

  bool get hasPrevious => _currentIndex > 0 && (_currentIndex < _queue.length);

  bool get isShuffle => _shuffle;
  RepeatMode get repeatMode => _repeat;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  int get queueLength => _queue.length;
  List<SongDetail> get queueSongs => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;

  // --- Shuffle & repeat
  List<SongDetail>? _originalQueue;
  bool isShuffleChanging = false;

  Future<void> toggleShuffle() async {
    isShuffleChanging = true;
    _shuffle = !_shuffle;
    final current = currentSong;

    if (_shuffle) {
      _originalQueue ??= List.from(_queue); // backup only if not already

      if (current != null) {
        // Keep current song at its current index
        final beforeCurrent = _queue.sublist(0, _currentIndex + 1);
        final afterCurrent = _queue.sublist(_currentIndex + 1)..shuffle();

        _queue = [...beforeCurrent, ...afterCurrent];
        // currentIndex remains the same
      } else {
        _queue.shuffle();
        _currentIndex = 0;
      }
    } else {
      if (_originalQueue != null) {
        final currentId = current?.id;
        _queue = List.from(_originalQueue!);
        _originalQueue = null;

        if (currentId != null) {
          _currentIndex = _queue.indexWhere((s) => s.id == currentId);
        }
      }
    }

    // Broadcast new queue
    queue.add(_queue.map(songToMediaItem).toList());
    ref.read(shuffleProvider.notifier).state = _shuffle;
    isShuffleChanging = false;
  }

  /// Turn shuffle OFF if currently enabled
  Future<void> disableShuffle() async {
    if (_shuffle) {
      toggleShuffle(); // toggleShuffle will restore original queue
    }
  }

  Future<void> reorderQueue(int oldIndex, int newIndex) async {
    if (oldIndex < 0 ||
        newIndex < 0 ||
        oldIndex >= _queue.length ||
        newIndex >= _queue.length) {
      debugPrint("Invalid indices for reordering.");
      return;
    }

    final moved = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, moved);

    if (_currentIndex == oldIndex) {
      _currentIndex = newIndex;
    } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
      _currentIndex++;
    }

    queue.add(_queue.map(songToMediaItem).toList());
    await LastQueueStorage.save(_queue, currentIndex: _currentIndex);
  }

  void _enforceQueueLimit() async {
    if (_queue.length > 50) {
      _queue = _queue.sublist(_queue.length - 50);
      _currentIndex = _queue.length - 1;
      await LastQueueStorage.save(_queue, currentIndex: _currentIndex);
    }
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
    await _player.pause();
  }

  @override
  Future<void> play() async {
    _isPausedManually = false;
    if (_currentIndex < 0 && _queue.isNotEmpty) {
      _currentIndex = 0;
      await _playCurrent();
    } else {
      await _player.play();
    }
  }

  Future<void> _onSongEnded() async {
    if (_isPausedManually) {
      debugPrint('--> Song ended, paused manually, not skipping.');
      return;
    }

    // Repeat one: just restart current song
    if (_repeat == RepeatMode.one) {
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }

    // Get next playable index considering offline availability
    int? nextIndex = await _getNextPlayableIndex();

    if (nextIndex != null) {
      _currentIndex = nextIndex;
      await _playCurrent(skipCompletedCheck: true);
      return;
    }

    // No next index found
    if (_repeat == RepeatMode.all && _queue.isNotEmpty) {
      _currentIndex = 0;
      await _playCurrent(skipCompletedCheck: true);
      return;
    }

    // Nothing to play, stop playback
    await stop();
    _currentIndex = -1;
    mediaItem.add(null);
    playbackState.add(
      playbackState.value.copyWith(
        playing: false,
        processingState: AudioProcessingState.idle,
        updatePosition: Duration.zero,
        bufferedPosition: Duration.zero,
        queueIndex: -1,
      ),
    );
  }

  Future<int?> _getNextPlayableIndex({
    int start = -1,
    bool backward = false,
  }) async {
    if (_queue.isEmpty) return null;

    int idx = start < 0 ? _currentIndex : start;
    int attempts = 0;

    while (attempts < _queue.length) {
      idx =
          backward
              ? (idx - 1 + _queue.length) % _queue.length
              : (idx + 1) % _queue.length;

      final song = _queue[idx];

      if (offlineManager.isAvailableOffline(songId: song.id) ||
          hasInternet.value) {
        return idx;
      }

      attempts++;
    }

    return null;
  }

  @override
  Future<void> skipToNext() async {
    if (_queue.isEmpty) return;

    if (_repeat == RepeatMode.one) {
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }

    final nextIndex = await _getNextPlayableIndex();
    if (nextIndex != null) {
      _currentIndex = nextIndex;
      await _playCurrent();
    } else if (_repeat == RepeatMode.all && _queue.isNotEmpty) {
      _currentIndex = 0;
      await _playCurrent();
    } else {
      await stop();
    }
  }

  Future<void> addSongNext(SongDetail song) async {
    if (_queue.any((s) => s.id == song.id)) return;

    final insertIndex = (_currentIndex + 1).clamp(0, _queue.length);
    _queue.insert(insertIndex, song);

    final updated = List<MediaItem>.from(queue.value);
    updated.insert(insertIndex, songToMediaItem(song));
    queue.add(updated);
    await LastQueueStorage.save(_queue, currentIndex: _currentIndex);
  }

  Future<void> addSongToQueue(SongDetail song) async {
    if (_queue.any((s) => s.id == song.id)) return;

    _queue.add(song);
    _enforceQueueLimit();

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

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index >= 0 && index < _queue.length) {
      _currentIndex = index;
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
    if (_queue.isEmpty) return;

    if (_repeat == RepeatMode.one) {
      await _player.seek(Duration.zero);
      await _player.play();
      return;
    }

    if (hasPrevious) {
      _currentIndex--;
      await _playCurrent();
    } else if (_repeat == RepeatMode.all) {
      _currentIndex = _queue.length - 1;
      await _playCurrent();
    }
  }

  @override
  Future<void> playMediaItem(MediaItem mediaItem) async {
    final idx = _queue.indexWhere((s) => s.id == mediaItem.id);
    if (idx >= 0 && idx != _currentIndex) {
      _currentIndex = idx;
      await _playCurrent();
    } else {
      await _player.play();
    }
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    final song = await AppDatabase.getSong(mediaItem.id);
    if (song == null) return;

    // avoid duplicates, then add at end
    _queue.removeWhere((s) => s.id == song.id);
    _queue.add(song);
    _enforceQueueLimit();

    // if shuffle on, re-shuffle but keep current song first
    if (_shuffle && _queue.length > 1) {
      final current = _queue[_currentIndex];
      _queue.remove(current);
      _queue.shuffle();
      _queue.insert(0, current);
      _currentIndex = 0;
    }

    queue.add(_queue.map(songToMediaItem).toList());
  }

  String? _queueSourceId;
  String? _queueSourceName;

  String? get queueSourceId => _queueSourceId;
  String? get queueSourceName => _queueSourceName;

  Future<void> loadQueue(
    List<SongDetail> songs, {
    int startIndex = 0,
    String? sourceId,
    String? sourceName,
    bool autoPlay = true,
  }) async {
    // 🔹 Clear existing queue first
    _queue.clear();
    _currentIndex = -1;
    _queueSourceId = sourceId;
    _queueSourceName = sourceName;

    // Broadcast empty queue to listeners
    queue.add([]);

    // Load new queue
    _queue = List.from(songs);
    _enforceQueueLimit();

    if (_queue.isEmpty) return;

    // Ensure incoming startIndex is in-range relative to original songs list
    final safeStartIndex = startIndex.clamp(0, songs.length - 1);

    if (_shuffle) {
      // Shuffle the whole queue but start with the requested song
      final startSongId = songs[safeStartIndex].id;
      _queue.shuffle();

      // Find the position of the requested start song in shuffled queue
      _currentIndex = _queue.indexWhere((s) => s.id == startSongId);
      if (_currentIndex < 0) _currentIndex = 0;
    } else {
      _currentIndex = safeStartIndex.clamp(0, _queue.length - 1);
    }

    // Broadcast new queue
    queue.add(_queue.map(songToMediaItem).toList());
    await LastQueueStorage.save(_queue, currentIndex: _currentIndex);

    // Start playing
    // Only play if autoPlay is true
    if (autoPlay) {
      await _playCurrent();
    }
  }

  Future<void> playSongNow(SongDetail song, {bool insertNext = false}) async {
    final existingIndex = _queue.indexWhere((s) => s.id == song.id);

    if (existingIndex >= 0) {
      _currentIndex = existingIndex;
    } else {
      final insertIndex =
          insertNext
              ? (_currentIndex + 1).clamp(0, _queue.length)
              : _currentIndex + 1;

      _queue.insert(insertIndex, song);
      _currentIndex = insertIndex;

      queue.add(_queue.map(songToMediaItem).toList());
      _queueSourceName = song.album;
      _queueSourceId = 'Search';
    }

    await LastQueueStorage.save(_queue, currentIndex: _currentIndex);
    await _playCurrent();
  }

  // --- Helpers
  Future<void> _playCurrent({bool skipCompletedCheck = false}) async {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) {
      await stop();
      return;
    }

    var song = _queue[_currentIndex];

    // fetch details if missing
    if (song.downloadUrls.isEmpty) {
      final fetched = await SaavnAPI().getSongDetails(ids: [song.id]);
      if (fetched.isNotEmpty) {
        song = fetched.first;
        _queue[_currentIndex] = song;
        await AppDatabase.saveSongDetail(song);
      }
    }

    if (song.downloadUrls.isEmpty) {
      info('Playback error, skipping to next song', Severity.warning);
      if (!skipCompletedCheck) await skipToNext();
      return;
    }

    ref.read(currentSongProvider.notifier).state = song;
    await LastPlayedSongStorage.save(song);

    try {
      final localPath = offlineManager.getLocalPath(song.id);

      if (localPath != null && File(localPath).existsSync()) {
        debugPrint("▶ Playing offline: $localPath");
        await _player.setAudioSource(
          AudioSource.uri(Uri.file(localPath), tag: songToMediaItem(song)),
        );
      } else {
        debugPrint("▶ Playing online: ${song.downloadUrls.last.url}");
        await _player.setAudioSource(
          AudioSource.uri(
            Uri.parse(song.downloadUrls.last.url),
            tag: songToMediaItem(song),
          ),
        );
      }

      mediaItem.add(songToMediaItem(song));
      await _player.play();
    } catch (e, st) {
      debugPrint("Error loading song: $e\n$st");
      if (!skipCompletedCheck) await skipToNext();
    }
  }

  Future<void> _updatePlaybackState(PlayerState ps) async {
    final hasMedia = mediaItem.value != null;
    final position = _player.position;

    final processingState =
        {
          ProcessingState.idle:
              hasMedia ? AudioProcessingState.ready : AudioProcessingState.idle,
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
        controls: [
          MediaControl.skipToPrevious,
          ps.playing ? MediaControl.pause : MediaControl.play,
          MediaControl.stop,
          MediaControl.skipToNext,
        ],
        androidCompactActionIndices: const [0, 1, 3],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        queueIndex: _currentIndex,
        speed: _player.speed,
      ),
    );
  }

  Future<void> _initLastPlayed() async {
    debugPrint('--> Initializing last played queue...');
    final lastQueueData = await LastQueueStorage.load();
    _shuffle = false;
    debugPrint('--> Shuffle set to false');

    if (lastQueueData != null) {
      final songs = lastQueueData.songs;
      final startIndex = lastQueueData.currentIndex;
      _queueSourceId = 'Last played';
      _queueSourceName = 'Last Played';

      if (songs.isNotEmpty) {
        debugPrint('--> Restoring queue: $lastQueueData');
        _queue = List.from(songs);
        _currentIndex = startIndex.clamp(0, _queue.length - 1);

        queue.add(_queue.map(songToMediaItem).toList());
        await LastQueueStorage.save(_queue, currentIndex: _currentIndex);

        final current = _queue[_currentIndex];
        ref.read(currentSongProvider.notifier).state = current;

        try {
          final sources =
              _queue.map((s) {
                final local = offlineManager.getLocalPath(s.id);
                final uri =
                    (local != null && File(local).existsSync())
                        ? Uri.file(local)
                        : Uri.parse(s.downloadUrls.last.url);
                return AudioSource.uri(uri, tag: songToMediaItem(s));
              }).toList();

          await _player.setAudioSources(
            sources,
            initialIndex: _currentIndex,
            initialPosition: Duration.zero,
          );

          mediaItem.add(songToMediaItem(current));

          final dominant = await getDominantColorFromImage(
            current.images.last.url,
          );
          ref.read(playerColourProvider.notifier).state = getDominantDarker(
            dominant,
          );

          debugPrint('--> Last played queue restored (not autoplaying).');
        } catch (e, st) {
          debugPrint('--> initLastPlayed (queue) error: $e\n$st');
        }

        return;
      }
    }

    // fallback: single last played song (previous logic)
    final last = await LastPlayedSongStorage.load();
    if (last != null) {
      _queue = [last];
      _currentIndex = 0;
      queue.add([songToMediaItem(last)]);
      _queueSourceName = 'Last Played';
      _queueSourceId = last.id;
      ref.read(currentSongProvider.notifier).state = last;

      try {
        final localPath = offlineManager.getLocalPath(last.id);
        final uri =
            (localPath != null && File(localPath).existsSync())
                ? Uri.file(localPath)
                : Uri.parse(last.downloadUrls.last.url);

        await _player.setAudioSource(
          AudioSource.uri(uri, tag: songToMediaItem(last)),
        );

        mediaItem.add(songToMediaItem(last));

        final dominant = await getDominantColorFromImage(last.images.last.url);
        ref.read(playerColourProvider.notifier).state = getDominantDarker(
          dominant,
        );

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
    artist:
        song.primaryArtists.isNotEmpty
            ? song.primaryArtists
            : (song.contributors.primary.isNotEmpty
                ? song.contributors.primary.map((a) => a.title).join(", ")
                : 'Unknown'),
    genre: song.albumName ?? song.album,
    duration:
        song.duration != null
            ? Duration(seconds: int.tryParse(song.duration!) ?? 0)
            : null,
    artUri:
        (song.images.isNotEmpty && song.images.last.url.isNotEmpty)
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
      'contributors_primary':
          song.contributors.primary.map((a) => a.title).toList(),
      'contributors_featured':
          song.contributors.featured.map((a) => a.title).toList(),
      'contributors_all': song.contributors.all.map((a) => a.title).toList(),
      'downloadUrls':
          song.downloadUrls
              .map((d) => {'url': d.url, 'quality': d.quality})
              .toList(),
    },
  );
}
