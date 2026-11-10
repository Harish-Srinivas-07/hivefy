import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/components/notification_permission_gate.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  testWidgets('asks for notification permission only after OK', (tester) async {
    var requests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationPermissionGate(
          checkStatus: () async => PermissionStatus.denied,
          checkNotificationsEnabled: () async => false,
          requestPermission: () async => requests++,
          child: const Scaffold(body: Text('App')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Enable notifications'), findsOneWidget);
    expect(requests, 0);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(requests, 1);
    expect(find.text('Enable notifications'), findsNothing);
  });

  testWidgets('not now dismisses the explanation without requesting permission', (tester) async {
    var requests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationPermissionGate(
          checkStatus: () async => PermissionStatus.denied,
          checkNotificationsEnabled: () async => false,
          requestPermission: () async => requests++,
          child: const Scaffold(body: Text('App')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(requests, 0);
    expect(find.text('Enable notifications'), findsNothing);
  });

  testWidgets('does not show the sheet when platform notifications are already enabled', (tester) async {
    var requests = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: NotificationPermissionGate(
          checkStatus: () async => PermissionStatus.denied,
          checkNotificationsEnabled: () async => true,
          requestPermission: () async => requests++,
          child: const Scaffold(body: Text('App')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Enable notifications'), findsNothing);
    expect(requests, 0);
  });

  for (final status in [PermissionStatus.granted, PermissionStatus.permanentlyDenied, PermissionStatus.restricted]) {
    testWidgets('does not prompt when notification status is $status', (tester) async {
      var requests = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: NotificationPermissionGate(
            checkStatus: () async => status,
            requestPermission: () async => requests++,
            child: const Scaffold(body: Text('App')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Enable notifications'), findsNothing);
      expect(requests, 0);
    });
  }
}
