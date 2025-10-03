// lib/shared/audio_handler.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/snackbar.dart';
import '../models/dailyfetches.dart';
import '../models/database.dart';
import '../models/datamodel.dart';
import '../services/jiosaavn.dart';
import '../shared/constants.dart';

enum RepeatMode { none, one, all }

/// One provider to rule them all 🚀
final audioHandlerProvider = FutureProvider<MyAudioHandler>((ref) async {
  final handler = await AudioService.init(
    builder: () => MyAudioHandler(ref),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.hivemind.hivefy.channel.audio',
      androidNotificationChannelName: 'Hivefy Audio',
      androidNotificationIcon: 'drawable/ic_launcher_foreground',
      androidShowNotificationBadge: true,
      androidResumeOnClick: true,
      androidStopForegroundOnPause: false,
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
  List<int>? _shuffleOrder;

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

    // resume last played song if exists
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

  // --- Shuffle & repeat
  void toggleShuffle() {
    _shuffle = !_shuffle;
    if (_shuffle) _generateShuffleOrder();
    ref.read(shuffleProvider.notifier).state = _shuffle;
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
  @override
  Future<void> play() async {
    try {
      if (_currentIndex < 0 && _queue.isNotEmpty) {
        _currentIndex = 0;
        await _playCurrent();
      } else {
        await _player.play();
      }
    } catch (e, st) {
      debugPrint('Play failed: $e\n$st');
    }
  }

  @override
  Future<void> pause() async {
    if (_player.audioSource == null) return;

    // update UI immediately
    playbackState.add(playbackState.value.copyWith(playing: false));
    await _player.pause();
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
  Future<void> skipToNext() async {
    if (_repeat == RepeatMode.one) {
      await _playCurrent();
      return;
    }

    if (_shuffle && _shuffleOrder != null) {
      final idx = _shuffleOrder!.indexOf(_currentIndex);
      if (idx + 1 < _shuffleOrder!.length) {
        _currentIndex = _shuffleOrder![idx + 1];
      } else if (_repeat == RepeatMode.all) {
        _currentIndex = _shuffleOrder!.first;
      } else {
        return;
      }
    } else if (hasNext) {
      _currentIndex++;
    } else if (_repeat == RepeatMode.all) {
      if (_shuffle) {
        _generateShuffleOrder();
        _currentIndex = _shuffleOrder!.first;
      } else {
        _currentIndex = 0;
      }
    } else {
      return;
    }

    await _playCurrent();
  }

  @override
  Future<void> skipToPrevious() async {
    if (_shuffle && _shuffleOrder != null) {
      final idx = _shuffleOrder!.indexOf(_currentIndex);
      if (idx > 0) {
        _currentIndex = _shuffleOrder![idx - 1];
      } else if (_repeat == RepeatMode.all) {
        _currentIndex = _shuffleOrder!.last;
      } else {
        return;
      }
    } else if (hasPrevious) {
      _currentIndex--;
    } else if (_repeat == RepeatMode.all) {
      _currentIndex = _queue.length - 1;
    } else {
      return;
    }

    await _playCurrent();
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

    _queue.removeWhere((s) => s.id == song.id);
    _queue.add(song);

    if (_shuffle) {
      _shuffleOrder ??= List.generate(_queue.length - 1, (i) => i);
      _shuffleOrder!.add(_queue.length - 1);
    }

    queue.add(_queue.map(songToMediaItem).toList());
  }

  Future<void> loadQueue(List<SongDetail> songs, {int startIndex = 0}) async {
    _queue = List.from(songs);
    if (_shuffle) _generateShuffleOrder();

    _currentIndex = startIndex.clamp(0, _queue.length - 1);
    queue.add(_queue.map(songToMediaItem).toList());
    await _playCurrent();
  }

  Future<void> playSongNow(
    SongDetail song, {
    List<SongDetail>? contextQueue,
    bool insertNext = false,
  }) async {
    if (contextQueue != null && contextQueue.isNotEmpty) {
      await loadQueue(
        contextQueue,
        startIndex: contextQueue
            .indexWhere((s) => s.id == song.id)
            .clamp(0, contextQueue.length - 1),
      );
    } else {
      final existingIndex = _queue.indexWhere((s) => s.id == song.id);
      if (existingIndex >= 0) {
        _currentIndex = existingIndex;
      } else if (insertNext) {
        _queue.insert(_currentIndex + 1, song);
        _currentIndex++;
      } else {
        _queue.add(song);
        _currentIndex = _queue.length - 1;
      }

      if (_shuffle) _generateShuffleOrder();
      queue.add(_queue.map(songToMediaItem).toList());
      await _playCurrent();
    }
  }

  // --- Helpers
  Future<void> _playCurrent() async {
    if (_currentIndex < 0 || _currentIndex >= _queue.length) return;
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
      info('Oops! Playback error skip to next song', Severity.warning);
      await skipToNext();
      return;
    }
    ref.read(currentSongProvider.notifier).state = song;
    await LastPlayedSongStorage.save(song);

    try {
      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(song.downloadUrls.last.url),
          tag: songToMediaItem(song),
        ),
      );
      mediaItem.add(songToMediaItem(song));

      await _player.play();
    } catch (e, st) {
      // skip to next if error
      debugPrint("Error loading song: $e\n$st");
      await skipToNext();
    }
  }

  Future<void> _updatePlaybackState(PlayerState ps) async {
    final hasMedia = mediaItem.value != null;
    final isPlaying = ps.playing;
    final position = _player.position;

    // Map just_audio states to audio_service states
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
        playing: isPlaying,
        processingState: processingState,
        updatePosition: position,
        controls: [
          MediaControl.skipToPrevious,
          isPlaying ? MediaControl.pause : MediaControl.play,
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

    if (ps.processingState == ProcessingState.completed) {
      if (_repeat == RepeatMode.one) {
        await _playCurrent();
      } else if (hasNext || _repeat == RepeatMode.all) {
        await skipToNext();
      } else if (_queue.isEmpty) {
        await pause();
        await stop();
        _currentIndex = -1;
        // clear mediaItem so UI knows nothing is playing
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
        return;
      }
    }
  }

  void _generateShuffleOrder() {
    _shuffleOrder = List.generate(_queue.length, (i) => i)..shuffle();
  }

  Future<void> _initLastPlayed() async {
    final last = await LastPlayedSongStorage.load();
    if (last != null) {
      _queue = [last];
      _currentIndex = 0;
      queue.add([songToMediaItem(last)]);
      ref.read(currentSongProvider.notifier).state = last;

      try {
        await _player.setAudioSource(
          AudioSource.uri(
            Uri.parse(last.downloadUrls.last.url),
            tag: songToMediaItem(last),
          ),
        );

        mediaItem.add(songToMediaItem(last));
      } catch (e) {
        debugPrint('--> initLastPlayed catch: $e');
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
