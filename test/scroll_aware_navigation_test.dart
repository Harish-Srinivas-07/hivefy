import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/components/scroll_aware_navigation.dart';

void main() {
  testWidgets('vertical scrolling hides and reveals navigation on every tab', (tester) async {
    final tab = ValueNotifier(0);
    addTearDown(tab.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<int>(
          valueListenable: tab,
          builder: (context, index, _) => ScrollAwareNavigation(
            tabIndex: index,
            backgroundColor: const Color(0xff121212),
            navigationBar: const SizedBox(key: ValueKey('navigation'), height: 60),
            body: IndexedStack(
              index: index,
              children: List.generate(
                3,
                (index) => ListView.builder(
                  key: ValueKey('list-$index'),
                  itemExtent: 80,
                  itemCount: 30,
                  itemBuilder: (_, item) => Text('Tab $index item $item'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final bar = find.byType(AnimatedSize);
    expect(tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor, const Color(0xff121212));
    for (var index = 0; index < 3; index++) {
      tab.value = index;
      await tester.pumpAndSettle();
      expect(tester.getSize(bar).height, 60);
      final list = find.byKey(ValueKey('list-$index'));
      await tester.drag(list, const Offset(0, -120));
      await tester.pumpAndSettle();
      expect(tester.getSize(bar).height, 0);
      await tester.drag(list, const Offset(0, 12));
      await tester.pumpAndSettle();
      expect(tester.getSize(bar).height, 60);
    }
  });

  testWidgets('switching tabs restores the bar and horizontal scrolling leaves it visible', (tester) async {
    final tab = ValueNotifier(0);
    addTearDown(tab.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<int>(
          valueListenable: tab,
          builder: (context, index, _) => ScrollAwareNavigation(
            tabIndex: index,
            navigationBar: const SizedBox(height: 60),
            body: ListView(
              children: [
                SizedBox(
                  height: 100,
                  child: ListView(scrollDirection: Axis.horizontal, children: [SizedBox(width: 1600)]),
                ),
                const SizedBox(height: 1600),
              ],
            ),
          ),
        ),
      ),
    );

    final bar = find.byType(AnimatedSize);
    await tester.drag(find.byType(ListView).last, const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(bar).height, 60);
    await tester.drag(find.byType(ListView).first, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(tester.getSize(bar).height, 0);
    tab.value = 1;
    await tester.pumpAndSettle();
    expect(tester.getSize(bar).height, 60);
  });
}
