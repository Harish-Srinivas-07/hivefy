import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/screens/search.dart';
import 'package:hivefy/services/youtube.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeSearchApi extends YoutubeAPI {
  @override
  Future<List<String>> getSearchBoxSuggestions({required String query}) async => ['$query result'];
}

void main() {
  testWidgets('search field keeps focus and accepts input as suggestions update', (tester) async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: IndexedStack(
              index: 1,
              children: [
                const SizedBox(),
                Navigator(
                  onGenerateRoute: (_) => MaterialPageRoute<void>(builder: (_) => Search(searchApi: FakeSearchApi())),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byIcon(LucideIcons.search));
    await tester.pump();
    final field = find.byType(TextField);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    expect(tester.testTextInput.hasAnyClients, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    tester.testTextInput.updateEditingValue(
      const TextEditingValue(text: 'Coldplay', selection: TextSelection.collapsed(offset: 8)),
    );
    await tester.pump();
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, 'Coldplay');
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    expect(tester.testTextInput.hasAnyClients, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(text: 'Coldplay yellow', selection: TextSelection.collapsed(offset: 15)),
    );
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, 'Coldplay yellow');
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    expect(tester.testTextInput.hasAnyClients, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
