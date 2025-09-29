import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../models/dailyfetches.dart';
import '../models/database.dart';
import '../models/datamodel.dart';
import '../services/jiosaavn.dart';
import '../shared/constants.dart';

enum RepeatMode { none, one, all }

class QueueManager extends StateNotifier<List<SongDetail>> {
  QueueManager(this._player, this._ref) : super([]) {
    _playerSub = _player.playerStateStream.listen(_onPlayerState);
    initLastPlayedSong();
  }

  final AudioPlayer _player;
  final Ref _ref;

  StreamSubscription<PlayerState>? _playerSub;
  bool _busy = false;
  int _currentIndex = -1;

  bool _shuffle = false;
  RepeatMode _repeatMode = RepeatMode.none;
  List<int>? _shuffleOrder;

  // --- getters
  int get currentIndex => _currentIndex;
  SongDetail? get currentSong =>
      (_currentIndex >= 0 && _currentIndex < state.length)
          ? state[_currentIndex]
          : null;
  bool get hasNext =>
      _shuffle
          ? _shuffleOrder != null &&
              _shuffleOrder!.indexOf(_currentIndex) + 1 < _shuffleOrder!.length
          : _currentIndex + 1 < state.length;
  bool get hasPrevious =>
      _shuffle
          ? _shuffleOrder != null && _shuffleOrder!.indexOf(_currentIndex) > 0
          : _currentIndex - 1 >= 0;

  bool get isShuffle => _shuffle;
  RepeatMode get repeatMode => _repeatMode;

  // --- public API

  void toggleShuffle() {
    _shuffle = !_shuffle;
    _ref.read(shuffleProvider.notifier).state = _shuffle;
    if (_shuffle) _generateShuffleOrder();
    state = List<SongDetail>.from(state);
  }

  void setRepeatMode(RepeatMode mode) {
    _repeatMode = mode;
    _ref.read(repeatModeProvider.notifier).state = mode;
    state = List<SongDetail>.from(state);
    debugPrint("[QueueManager] Repeat mode: $_repeatMode");
  }

  void toggleRepeatMode() {
    switch (_repeatMode) {
      case RepeatMode.none:
        setRepeatMode(RepeatMode.all);
        break;
      case RepeatMode.all:
        setRepeatMode(RepeatMode.one);
        break;
      case RepeatMode.one:
        setRepeatMode(RepeatMode.none);
        break;
    }
  }

  Future<void> loadQueue(List<SongDetail> songs, {int startIndex = 0}) async {
    if (songs.isEmpty) {
      final dbSongs = await AppDatabase.getAllSongs();
      if (dbSongs.isEmpty) return;
      state = List<SongDetail>.from(dbSongs);
      _currentIndex = 0;
      await _playCurrent();
      return;
    }

    state = List<SongDetail>.from(songs);
    _currentIndex = startIndex.clamp(0, state.length - 1);

    // Reset player before starting
    await _player.stop(); // stops any ongoing playback
    await _player.seek(Duration.zero);

    if (_shuffle) _generateShuffleOrder();

    await _playCurrent();
  }

  Future<void> playAt(int index) async {
    if (index < 0 || index >= state.length) return;
    _currentIndex = index;
    await _playCurrent();
  }

  void insertNext(SongDetail song) {
    final list = List<SongDetail>.from(state);
    final insertPos = (_currentIndex >= 0) ? _currentIndex + 1 : list.length;
    list.insert(insertPos, song);
    state = list;
  }

  void addToQueue(SongDetail song) {
    state = [...state, song];
  }

  Future<void> clear() async {
    _currentIndex = -1;
    state = [];
    try {
      await _player.stop();
    } catch (_) {}
    _ref.read(currentSongProvider.notifier).state = null;
  }

  Future<void> playNext() async {
    if (_repeatMode == RepeatMode.one) {
      await _playCurrent();
      return;
    }

    if (_shuffle && _shuffleOrder != null) {
      final nextIndex = _shuffleOrder!.indexOf(_currentIndex) + 1;
      if (nextIndex < _shuffleOrder!.length) {
        _currentIndex = _shuffleOrder![nextIndex];
      } else if (_repeatMode == RepeatMode.all) {
        _currentIndex = _shuffleOrder!.first;
      } else {
        _currentIndex = -1;
        _ref.read(currentSongProvider.notifier).state = null;
        return;
      }
    } else if (hasNext) {
      _currentIndex++;
    } else if (_repeatMode == RepeatMode.all) {
      _currentIndex = 0;
    } else {
      _currentIndex = -1;
      _ref.read(currentSongProvider.notifier).state = null;
      return;
    }

    await _playCurrent();
  }

  Future<void> playPrevious() async {
    if (_shuffle && _shuffleOrder != null) {
      final prevIndex = _shuffleOrder!.indexOf(_currentIndex) - 1;
      if (prevIndex >= 0) {
        _currentIndex = _shuffleOrder![prevIndex];
      } else if (_repeatMode == RepeatMode.all) {
        _currentIndex = _shuffleOrder!.last;
      } else {
        return;
      }
    } else if (hasPrevious) {
      _currentIndex--;
    } else if (_repeatMode == RepeatMode.all) {
      _currentIndex = state.length - 1;
    } else {
      return;
    }

    await _playCurrent();
  }

  Future<void> playSongNow(
    SongDetail song, {
    List<SongDetail>? contextQueue,
  }) async {
    if (contextQueue != null && contextQueue.isNotEmpty) {
      final idx = contextQueue.indexWhere((s) => s.id == song.id);
      await loadQueue(contextQueue, startIndex: (idx >= 0) ? idx : 0);
      if (idx < 0) {
        insertNext(song);
        await playNext();
      }
      return;
    }

    addToQueue(song);
    _currentIndex = state.length - 1;
    await _playCurrent();
  }

  // --- internal helpers

  Future<void> _playCurrent() async {
    if (_currentIndex < 0 || _currentIndex >= state.length) return;
    if (_busy) return;
    _busy = true;

    try {
      var song = state[_currentIndex];

      if (song.downloadUrls.isEmpty) {
        final dbSong = await AppDatabase.getSong(song.id);
        if (dbSong != null && dbSong.downloadUrls.isNotEmpty) {
          final newList = List<SongDetail>.from(state);
          newList[_currentIndex] = dbSong;
          state = newList;
          song = dbSong;
        } else {
          final fetched = await SaavnAPI().getSongDetails(ids: [song.id]);
          if (fetched.isNotEmpty) {
            final first = fetched.first;
            final newList = List<SongDetail>.from(state);
            newList[_currentIndex] = first;
            state = newList;
            await AppDatabase.saveSongDetail(first);
            song = first;
          }
        }
      }

      if (song.downloadUrls.isEmpty) {
        await playNext();
        return;
      }

      try {
        await _player.setUrl(song.downloadUrls.last.url);
        // Reset position explicitly
        await _player.seek(Duration.zero);
        _ref.read(currentSongProvider.notifier).state = song;
        // Persist last played song
        await LastPlayedSongStorage.save(song);
        await _player.play();
      } catch (e, st) {
        debugPrint("QueueManager: failed to play ${song.id}: $e\n$st");
        await playNext();
      }
    } finally {
      _busy = false;
    }
  }

  void _generateShuffleOrder() {
    _shuffleOrder = List.generate(state.length, (i) => i)..shuffle();
  }

  void _onPlayerState(PlayerState ps) {
    if (ps.processingState == ProcessingState.completed) {
      playNext();
    }
  }

  @override
  void dispose() {
    _playerSub?.cancel();
    super.dispose();
  }

  Future<void> initLastPlayedSong() async {
    final lastSong = await LastPlayedSongStorage.load();
    if (lastSong != null) {
      state = [lastSong]; // Load as single-song queue
      _currentIndex = 0;
      _ref.read(currentSongProvider.notifier).state = lastSong;

      // Optionally prepare player without auto-playing
      try {
        await _player.setUrl(lastSong.downloadUrls.last.url);
        await _player.seek(Duration.zero);
      } catch (_) {}
    }
  }
}
