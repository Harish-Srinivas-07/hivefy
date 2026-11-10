import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Defers font notifications that arrive during a frame on affected Flutter versions.
class FontSafeWidgetsBinding extends WidgetsFlutterBinding {
  @override
  Future<void> handleSystemMessage(Object systemMessage) async {
    if (systemMessage is Map && systemMessage['type'] == 'fontsChange') {
      while (schedulerPhase != SchedulerPhase.idle) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    await super.handleSystemMessage(systemMessage);
  }
}
