import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/sleeptimer.dart';
import '../utils/theme.dart';

class SleepTimerSheet extends ConsumerStatefulWidget {
  const SleepTimerSheet({super.key});

  @override
  ConsumerState<SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends ConsumerState<SleepTimerSheet> {
  @override
  Widget build(BuildContext context) {
    final sleepState = ref.watch(sleepTimerProvider);
    final notifier = ref.read(sleepTimerProvider.notifier);

    final options = {
      SleepTimerOption.fiveMin: '5 minutes',
      SleepTimerOption.tenMin: '10 minutes',
      SleepTimerOption.fifteenMin: '15 minutes',
      SleepTimerOption.twentyMin: '20 minutes',
      SleepTimerOption.thirtyMin: '30 minutes',
      SleepTimerOption.fortyFiveMin: '45 minutes',
      SleepTimerOption.oneHour: '1 hour',
      SleepTimerOption.endOfTrack: 'End of Track',
    };

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Container(
        color: spotifyBgColor,
        padding: const EdgeInsets.only(top: 10),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              const Padding(
                padding: EdgeInsets.only(top: 8, bottom: 8),
                child: SizedBox(
                  width: 38,
                  height: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white30,
                      borderRadius: BorderRadius.all(Radius.circular(2)),
                    ),
                  ),
                ),
              ),

              const Text(
                'Sleep Timer',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 12),
              const Divider(color: Colors.white12, height: 1),

              // Scrollable list of options
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 12,
                  ),
                  child: Column(
                    children: [
                      ...options.entries.map((entry) {
                        final isActive = sleepState.option == entry.key;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeInOut,
                          decoration: BoxDecoration(
                            // color:
                            //     isActive
                            //         ? spotifyGreen.withOpacity(0.12)
                            //         : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 0,
                              horizontal: 12,
                            ),
                            onTap: () {
                              notifier.setTimer(entry.key);
                              Navigator.pop(context);
                            },
                            title: Text(
                              entry.value,
                              style: TextStyle(
                                fontSize: 14,
                                color: isActive ? spotifyGreen : Colors.white38,
                                fontWeight:
                                    isActive
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                              ),
                            ),
                            trailing:
                                isActive
                                    ? const Icon(
                                      Icons.check,
                                      color: spotifyGreen,
                                      size: 20,
                                    )
                                    : null,
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ),

              const Divider(color: Colors.white12, height: 1),

              if (sleepState.option != SleepTimerOption.off) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: TextButton(
                    onPressed: () => notifier.cancelTimer(),
                    child: const Text(
                      'Cancel Timer',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// To open from anywhere:
void showSleepTimerSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const SleepTimerSheet(),
  );
}
