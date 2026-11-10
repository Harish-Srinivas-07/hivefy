import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/screens/features/language.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toastification/toastification.dart';

void main() {
  test('saves multiple selected languages together', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final notifier = ValueNotifier<List<String>>(['tamil']);
    addTearDown(notifier.dispose);
    await savePreferredLanguages(notifier, ['tamil', 'english']);
    expect(notifier.value, ['tamil', 'english']);
    expect((await SharedPreferences.getInstance()).getString('app_language'), 'tamil,english');
  });

  testWidgets('language selection is saved and published without network requests', (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'tamil'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const ToastificationWrapper(child: MaterialApp(home: LanguageSetPage())),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('English'));
    await tester.tap(find.text('Tamil'));
    await tester.ensureVisible(find.text('Update Languages'));
    await tester.tap(find.text('Update Languages'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect((await SharedPreferences.getInstance()).getString('app_language'), 'english');
    expect(container.read(languageNotifierProvider).value, ['english']);
    expect(find.text('Saving languages...'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
