import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/datamodel.dart';

// Queue State Model
class QueueState {
  final SongDetail? current;
  final List<SongDetail> previous; // last 5 played
  final List<SongDetail> upcoming; // next 10
  final List<SongDetail> history; // last 10 (global)

  const QueueState({
    this.current,
    this.previous = const [],
    this.upcoming = const [],
    this.history = const [],
  });

  QueueState copyWith({
    SongDetail? current,
    List<SongDetail>? previous,
    List<SongDetail>? upcoming,
    List<SongDetail>? history,
  }) {
    return QueueState(
      current: current ?? this.current,
      previous: previous ?? this.previous,
      upcoming: upcoming ?? this.upcoming,
      history: history ?? this.history,
    );
  }
}

// Notifier to manage queue
class QueueNotifier extends StateNotifier<QueueState> {
  QueueNotifier() : super(const QueueState());

  /// Set a new song as current
  void play(SongDetail song) {
    final prev = [...state.previous];
    if (state.current != null) {
      prev.insert(0, state.current!);
      if (prev.length > 5) prev.removeLast();
    }

    final hist = [...state.history];
    hist.insert(0, song);
    if (hist.length > 10) hist.removeLast();

    state = state.copyWith(current: song, previous: prev, history: hist);
  }

  /// Skip to next (from upcoming)
  void next() {
    if (state.upcoming.isEmpty) return;
    final nextSong = state.upcoming.first;
    final rest = state.upcoming.skip(1).toList();
    play(nextSong);
    state = state.copyWith(upcoming: rest);
  }

  /// Go back to previous (rewind)
  void previousSong() {
    if (state.previous.isEmpty) return;
    final prevSong = state.previous.first;
    final rest = state.previous.skip(1).toList();

    final curr = state.current;
    final upcoming = [if (curr != null) curr, ...state.upcoming];
    if (upcoming.length > 10) upcoming.removeLast();

    state = state.copyWith(
      current: prevSong,
      previous: rest,
      upcoming: upcoming,
    );
  }

  /// Add songs to upcoming queue
  void addToQueue(List<SongDetail> songs) {
    final upcoming = [...state.upcoming, ...songs];
    state = state.copyWith(upcoming: upcoming.take(10).toList());
  }
}

// Riverpod provider
final queueProvider = StateNotifierProvider<QueueNotifier, QueueState>(
  (ref) => QueueNotifier(),
);
