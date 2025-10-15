import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'audiohandler.dart';

/// Sleep timer durations
enum SleepTimerOption {
  off,
  fiveMin,
  tenMin,
  fifteenMin,
  twentyMin,
  thirtyMin,
  fortyFiveMin,
  oneHour,
  endOfTrack,
}

class SleepTimerState {
  final SleepTimerOption option;
  final Duration? remaining;
  const SleepTimerState({required this.option, this.remaining});

  SleepTimerState copyWith({SleepTimerOption? option, Duration? remaining}) {
    return SleepTimerState(
      option: option ?? this.option,
      remaining: remaining ?? this.remaining,
    );
  }
}

class SleepTimerNotifier extends StateNotifier<SleepTimerState> {
  final Ref ref;
  Timer? _timer;
  StreamSubscription? _trackEndSub;

  SleepTimerNotifier(this.ref)
    : super(const SleepTimerState(option: SleepTimerOption.off));

  void setTimer(SleepTimerOption option) async {
    _cancelAll();

    // If user disabled timer
    if (option == SleepTimerOption.off) {
      state = const SleepTimerState(option: SleepTimerOption.off);
      return;
    }

    // Handle "End of Track"
    if (option == SleepTimerOption.endOfTrack) {
      final audioHandler = await ref.read(audioHandlerProvider.future);
      _trackEndSub = audioHandler.playerStateStream.listen((ps) async {
        if (ps.processingState == ProcessingState.completed) {
          await audioHandler.pause();
          cancelTimer();
        }
      });
      state = const SleepTimerState(option: SleepTimerOption.endOfTrack);
      return;
    }

    // Handle timed durations
    final duration = _mapOptionToDuration(option);
    if (duration == null) return;

    state = SleepTimerState(option: option, remaining: duration);

    _timer = Timer(duration, () async {
      final handler = await ref.read(audioHandlerProvider.future);
      await handler.pause();
      state = const SleepTimerState(option: SleepTimerOption.off);
    });
  }

  void cancelTimer() => _cancelAll();

  void _cancelAll() {
    _timer?.cancel();
    _timer = null;
    _trackEndSub?.cancel();
    _trackEndSub = null;
    state = const SleepTimerState(option: SleepTimerOption.off);
  }

  Duration? _mapOptionToDuration(SleepTimerOption option) {
    switch (option) {
      case SleepTimerOption.fiveMin:
        return const Duration(minutes: 5);
      case SleepTimerOption.tenMin:
        return const Duration(minutes: 10);
      case SleepTimerOption.fifteenMin:
        return const Duration(minutes: 15);
      case SleepTimerOption.twentyMin:
        return const Duration(minutes: 20);
      case SleepTimerOption.thirtyMin:
        return const Duration(minutes: 30);
      case SleepTimerOption.fortyFiveMin:
        return const Duration(minutes: 45);
      case SleepTimerOption.oneHour:
        return const Duration(hours: 1);
      default:
        return null;
    }
  }

  @override
  void dispose() {
    _cancelAll();
    super.dispose();
  }
}

final sleepTimerProvider =
    StateNotifierProvider<SleepTimerNotifier, SleepTimerState>(
      (ref) => SleepTimerNotifier(ref),
    );
