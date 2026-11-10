import 'package:drag_and_drop_lists/drag_and_drop_lists.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/screens/features/queuesheet.dart';

void main() {
  for (final hasItems in [false, true]) {
    testWidgets('queue content fits a collapsed sheet with items: $hasItems', (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: 60,
                child: QueueSheetScroll(
                  scrollController: controller,
                  header: const SizedBox(height: 150, child: Text('Now playing')),
                  items: hasItems ? [DragAndDropItem(child: const SizedBox(height: 60, child: Text('Next song')))] : [],
                  onReorder: (_, __) {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(QueueSheetScroll), const Offset(0, -100));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(controller.offset, greaterThan(0));
    });
  }
}
