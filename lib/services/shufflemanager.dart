// lib\services\shufflemanager.dart
import 'dart:math';
import '../models/datamodel.dart';

/// Handles all shuffle logic independently of AudioHandler.
/// Inspired by Spotify-style weighted shuffling (avoids repeats and preserves current song).
class ShuffleManager {
  List<SongDetail> _originalQueue = [];
  List<SongDetail> _shuffledQueue = [];

  bool _isShuffling = false;
  bool _isShuffleChanging = false;
  int _currentIndex = -1;

  /// Keeps a lightweight playback history so recently played songs appear later in shuffle.
  final List<String> _recentlyPlayed = [];
  final int _historyLimit = 10;

  // --- Public getters
  bool get isShuffling => _isShuffling;
  bool get isShuffleChanging => _isShuffleChanging;
  List<SongDetail> get currentQueue =>
      _isShuffling ? _shuffledQueue : _originalQueue;
  int get currentIndex => _currentIndex;
  SongDetail? get currentSong =>
      currentQueue.isEmpty ? null : currentQueue[_currentIndex];

  /// Initialize with a queue and current index.
  void loadQueue(List<SongDetail> queue, {int currentIndex = 0}) {
    _originalQueue = List.from(queue);
    _currentIndex =
        queue.isEmpty ? -1 : currentIndex.clamp(0, queue.length - 1);
    if (_isShuffling) _applyShuffle(currentSong: currentSong);
  }

  /// Toggle shuffle mode (safe re-entry guarded by [_isShuffleChanging]).
  void toggleShuffle({SongDetail? currentSong}) {
    if (_isShuffleChanging) return;
    _isShuffleChanging = true;

    final current = currentSong ?? this.currentSong;

    if (_isShuffling) {
      // Disable shuffle
      _isShuffling = false;
      _shuffledQueue.clear();

      if (current != null) {
        final idx = _originalQueue.indexWhere((s) => s.id == current.id);
        _currentIndex =
            idx >= 0 ? idx : _currentIndex.clamp(0, _originalQueue.length - 1);
      }
    } else {
      // Enable shuffle
      _isShuffling = true;
      _applyShuffle(currentSong: current);
    }

    _isShuffleChanging = false;
  }

  /// Weighted shuffle ensuring the current song starts first.
  void _applyShuffle({SongDetail? currentSong}) {
    if (_originalQueue.isEmpty) return;

    final rng = Random();

    // Ensure current song exists
    final current = currentSong ?? currentQueue[_currentIndex];

    // Candidates for shuffle: all except current
    final candidates = List<SongDetail>.from(_originalQueue)
      ..removeWhere((s) => s.id == current.id);

    // Weighted shuffle: recently played songs less likely
    final filtered =
        candidates.where((s) => !_recentlyPlayed.contains(s.id)).toList();
    if (filtered.isEmpty) filtered.addAll(candidates);

    filtered.shuffle(rng);

    // Place current song at the same logical position
    _shuffledQueue = [current, ...filtered];

    // Current song index always points to the current song
    _currentIndex = _shuffledQueue.indexWhere((s) => s.id == current.id);
  }

  /// Get the next index considering shuffle mode.
  int? getNextIndex() {
    if (currentQueue.isEmpty) return null;
    final next = (_currentIndex + 1) % currentQueue.length;
    _currentIndex = next;
    _registerPlay(currentQueue[next]);
    return next;
  }

  /// Get the previous index considering shuffle mode.
  int? getPreviousIndex() {
    if (currentQueue.isEmpty) return null;
    final prev =
        (_currentIndex - 1 + currentQueue.length) % currentQueue.length;
    _currentIndex = prev;
    _registerPlay(currentQueue[prev]);
    return prev;
  }

  /// Register a song as recently played (for weighted shuffle bias).
  void _registerPlay(SongDetail song) {
    _recentlyPlayed.remove(song.id);
    _recentlyPlayed.insert(0, song.id);
    if (_recentlyPlayed.length > _historyLimit) {
      _recentlyPlayed.removeLast();
    }
  }

  // --- Queue modification helpers

  /// Add a song while maintaining current shuffle mode.
  void addSong(SongDetail song) {
    if (_originalQueue.any((s) => s.id == song.id)) return;

    _originalQueue.add(song);

    if (_isShuffling) {
      // Insert near the end, less likely to interrupt current playback
      final insertPos =
          _shuffledQueue.length > 1
              ? Random().nextInt(_shuffledQueue.length - 1) + 1
              : 1;
      _shuffledQueue.insert(insertPos.clamp(0, _shuffledQueue.length), song);
    }
  }

  /// Remove a song from both queues safely.
  void removeSong(String songId) {
    _originalQueue.removeWhere((s) => s.id == songId);
    _shuffledQueue.removeWhere((s) => s.id == songId);

    if (_currentIndex >= currentQueue.length) {
      _currentIndex = currentQueue.isEmpty ? -1 : currentQueue.length - 1;
    }
  }

  /// Reorder a song in the queue safely.
  /// Updates both original and shuffled queues based on current shuffle mode.
  void reorder(int oldIndex, int newIndex) {
    oldIndex = oldIndex.clamp(0, currentQueue.length - 1);
    newIndex = newIndex.clamp(0, currentQueue.length - 1);
    if (oldIndex == newIndex) return;

    if (_isShuffling) {
      final movedSong = _shuffledQueue.removeAt(oldIndex);
      _shuffledQueue.insert(newIndex, movedSong);

      final origIndex = _originalQueue.indexWhere((s) => s.id == movedSong.id);
      if (origIndex != -1) {
        _originalQueue.removeAt(origIndex);
        _originalQueue.insert(
          origIndex.clamp(0, _originalQueue.length),
          movedSong,
        );
      }

      _currentIndex = _shuffledQueue.indexWhere((s) => s.id == currentSong?.id);
    } else {
      final movedSong = _originalQueue.removeAt(oldIndex);
      _originalQueue.insert(newIndex, movedSong);
      _currentIndex = _originalQueue.indexWhere((s) => s.id == currentSong?.id);
    }
  }
}
