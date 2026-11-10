import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/components/notification_permission_gate.dart';
import 'package:hivefy/screens/onboarding.dart';
import 'package:hivefy/screens/features/language.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('notification sheet appears only after onboarding', (tester) async {
    SharedPreferences.setMockInitialValues({});
    var checks = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: TickerMode(
            enabled: false,
            child: StartupGate(
              home: NotificationPermissionGate(
                checkStatus: () async {
                  checks++;
                  return PermissionStatus.denied;
                },
                checkNotificationsEnabled: () async => false,
                child: const Scaffold(body: Text('Home screen')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('What should we call you?'), findsOneWidget);
    expect(find.text('Enable notifications'), findsNothing);
    expect(checks, 0);
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('Home screen'), findsOneWidget);
    expect(find.text('Enable notifications'), findsOneWidget);
    expect(checks, 1);
  });

  testWidgets('first launch saves name and languages before opening home', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: TickerMode(enabled: false, child: StartupGate(home: Text('Home screen'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('What should we call you?'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '  Alex  ');
    await tester.pump();
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('What do you like to listen to?'), findsOneWidget);
    await tester.tap(find.text('English'));
    await tester.tap(find.text('Tamil'));
    await tester.pump();
    await tester.tap(find.text('Start listening'));
    await tester.pumpAndSettle();
    expect(find.text('Home screen'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('username'), 'Alex');
    expect(prefs.getString('app_language'), 'english,tamil');
    expect(prefs.getBool('onboarding_complete'), isTrue);
    expect(container.read(languageNotifierProvider).value, ['english', 'tamil']);
  });

  testWidgets('completed onboarding is skipped on later launches', (tester) async {
    SharedPreferences.setMockInitialValues({
      'onboarding_complete': true,
      'username': 'Alex',
      'app_language': 'english',
    });
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: TickerMode(enabled: false, child: StartupGate(home: Text('Home screen'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Home screen'), findsOneWidget);
    expect(find.text('What should we call you?'), findsNothing);
  });

  testWidgets('skip opens home and preserves existing profile and language preferences', (tester) async {
    SharedPreferences.setMockInitialValues({'username': 'Existing', 'app_language': 'hindi'});
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: TickerMode(enabled: false, child: StartupGate(home: Text('Home screen'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Image &&
            widget.image is AssetImage &&
            (widget.image as AssetImage).assetName == 'assets/icons/logo.png',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('Home screen'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('username'), 'Existing');
    expect(prefs.getString('app_language'), 'hindi');
    expect(prefs.getBool('onboarding_complete'), isTrue);
  });

  testWidgets('tapping outside the name field dismisses the keyboard', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: TickerMode(enabled: false, child: StartupGate(home: Text('Home screen'))),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    await tester.tap(find.text('What should we call you?'));
    await tester.pump();
    expect(tester.testTextInput.isVisible, isFalse);
  });
}
