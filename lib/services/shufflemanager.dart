import 'dart:math';
import '../models/datamodel.dart';

class ShuffleManager {
  List<SongDetail> _originalQueue = [];
  List<SongDetail> _shuffledQueue = [];

  bool _isShuffling = false;
  bool _isShuffleChanging = false;
  int _currentIndex = -1;

  final List<String> _recentlyPlayed = [];
  final int _historyLimit = 10;

  bool get isShuffling => _isShuffling;
  bool get isShuffleChanging => _isShuffleChanging;
  List<SongDetail> get currentQueue =>
      _isShuffling ? _shuffledQueue : _originalQueue;
  int get currentIndex => _currentIndex;
  List<SongDetail> get originalQueue => List.unmodifiable(_originalQueue);
  SongDetail? get currentSong =>
      (currentQueue.isEmpty ||
          _currentIndex < 0 ||
          _currentIndex >= currentQueue.length)
      ? null
      : currentQueue[_currentIndex];

  void loadQueue(
    List<SongDetail> queue, {
    int currentIndex = 0,
    bool clearHistory = true,
  }) {
    _originalQueue = List.from(queue);
    _currentIndex = queue.isEmpty
        ? -1
        : currentIndex.clamp(0, queue.length - 1);

    if (clearHistory) {
      _recentlyPlayed.clear();
    }

    if (_isShuffling) _applyShuffle(currentSong: currentSong);
  }

  void toggleShuffle({SongDetail? currentSong}) {
    if (_isShuffleChanging) return;
    _isShuffleChanging = true;

    try {
      final current = currentSong ?? this.currentSong;

      if (current == null) return;

      if (_isShuffling) {
        _isShuffling = false;
        _shuffledQueue.clear();

        final idx = _originalQueue.indexWhere((s) => s.id == current.id);
        _currentIndex = idx >= 0
            ? idx
            : _currentIndex.clamp(0, _originalQueue.length - 1);
      } else {
        _isShuffling = true;
        _applyShuffle(currentSong: current);
      }
    } finally {
      _isShuffleChanging = false;
    }
  }

  void _applyShuffle({SongDetail? currentSong}) {
    if (_originalQueue.isEmpty) return;

    final rng = Random();

    final current =
        currentSong ??
        (_currentIndex >= 0 && _currentIndex < _originalQueue.length
            ? _originalQueue[_currentIndex]
            : _originalQueue.first);

    final candidates = List<SongDetail>.from(_originalQueue)
      ..removeWhere((s) => s.id == current.id);

    final filtered = candidates
        .where((s) => !_recentlyPlayed.contains(s.id))
        .toList();
    if (filtered.isEmpty) filtered.addAll(candidates);

    filtered.shuffle(rng);

    _shuffledQueue = [current, ...filtered];
    _currentIndex = 0;
  }

  int? getNextIndex() {
    if (currentQueue.isEmpty || _currentIndex < 0) return null;
    final next = _currentIndex + 1;
    if (next >= currentQueue.length) return null;
    return next;
  }

  int? getPreviousIndex() {
    if (currentQueue.isEmpty || _currentIndex < 0) return null;
    final prev = _currentIndex - 1;
    if (prev < 0) return null;
    return prev;
  }

  void registerPlay(SongDetail song) {
    _recentlyPlayed.remove(song.id);
    _recentlyPlayed.insert(0, song.id);
    if (_recentlyPlayed.length > _historyLimit) {
      _recentlyPlayed.removeLast();
    }
  }

  void resetHistory() {
    _recentlyPlayed.clear();
  }

  void addSong(SongDetail song) {
    if (_originalQueue.any((s) => s.id == song.id)) return;

    _originalQueue.add(song);

    if (_isShuffling) {
      final insertPos = _shuffledQueue.length > 1
          ? Random().nextInt(_shuffledQueue.length - 1) + 1
          : 1;
      _shuffledQueue.insert(insertPos.clamp(0, _shuffledQueue.length), song);
    }
  }

  void removeSong(String songId) {
    final wasCurrentSong = currentSong?.id == songId;

    _originalQueue.removeWhere((s) => s.id == songId);
    _shuffledQueue.removeWhere((s) => s.id == songId);

    if (_currentIndex >= currentQueue.length) {
      _currentIndex = currentQueue.isEmpty ? -1 : currentQueue.length - 1;
    }

    if (wasCurrentSong && currentQueue.isNotEmpty) {
      _currentIndex = _currentIndex.clamp(0, currentQueue.length - 1);
    }
  }

  void reorder(int oldIndex, int newIndex) {
    oldIndex = oldIndex.clamp(0, currentQueue.length - 1);
    newIndex = newIndex.clamp(0, currentQueue.length - 1);
    if (oldIndex == newIndex) return;

    if (_isShuffling) {
      final movedSong = _shuffledQueue.removeAt(oldIndex);
      _shuffledQueue.insert(newIndex, movedSong);

      if (oldIndex == _currentIndex) {
        _currentIndex = newIndex;
      } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
        _currentIndex--;
      } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
        _currentIndex++;
      }
    } else {
      final movedSong = _originalQueue.removeAt(oldIndex);
      _originalQueue.insert(newIndex, movedSong);

      if (oldIndex == _currentIndex) {
        _currentIndex = newIndex;
      } else if (oldIndex < _currentIndex && newIndex >= _currentIndex) {
        _currentIndex--;
      } else if (oldIndex > _currentIndex && newIndex <= _currentIndex) {
        _currentIndex++;
      }
    }
  }

  void updateCurrentIndex(int index) {
    if (index >= 0 && index < currentQueue.length) {
      _currentIndex = index;
    }
  }

  void insertSong(int index, SongDetail song) {
    if (_isShuffling) {
      _shuffledQueue.insert(index.clamp(0, _shuffledQueue.length), song);
      if (!_originalQueue.any((s) => s.id == song.id)) {
        _originalQueue.add(song);
      }
      if (index <= _currentIndex) {
        _currentIndex++;
      }
      _recentlyPlayed.insert(0, song.id);
    } else {
      _originalQueue.insert(index.clamp(0, _originalQueue.length), song);
      if (index <= _currentIndex) {
        _currentIndex++;
      }
    }
  }

  void updateSongInQueue(SongDetail song) {
    final origIdx = _originalQueue.indexWhere((s) => s.id == song.id);
    if (origIdx != -1) {
      _originalQueue[origIdx] = song;
    }

    final shuffleIdx = _shuffledQueue.indexWhere((s) => s.id == song.id);
    if (shuffleIdx != -1) {
      _shuffledQueue[shuffleIdx] = song;
    }
  }
}
