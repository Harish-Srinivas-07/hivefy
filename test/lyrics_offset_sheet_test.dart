import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/components/lyrics_offset.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('offset opens as a bottom sheet and saves the typed value', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showLyricsOffsetSheet(context, songId: 'song'),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Lyrics offset'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    for (final tooltip in ['Decrease offset', 'Increase offset']) {
      final button = tester.widget<IconButton>(
        find.byWidgetPredicate((widget) => widget is IconButton && widget.tooltip == tooltip),
      );
      expect(button.style!.shape!.resolve({}), isA<CircleBorder>());
    }

    await tester.tap(find.byTooltip('Increase offset'));
    await tester.pump();
    expect((await SharedPreferences.getInstance()).getInt('lyrics_offset_song'), 500);
    await tester.enterText(find.byType(TextField), '-1.25');
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect((await SharedPreferences.getInstance()).getInt('lyrics_offset_song'), -1250);
    expect(find.byType(BottomSheet), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
