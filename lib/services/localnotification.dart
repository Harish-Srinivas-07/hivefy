import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

final FlutterLocalNotificationsPlugin notifications =
    FlutterLocalNotificationsPlugin();

Future<void> requestNotificationPermission() async {
  if (!await Permission.notification.isGranted) {
    await Permission.notification.request();
  }
}

Future<void> initNotifications() async {
  const androidSettings = AndroidInitializationSettings(
    '@drawable/ic_launcher_foreground',
  );
  const initSettings = InitializationSettings(android: androidSettings);

  await notifications.initialize(initSettings);

  const androidChannel = AndroidNotificationChannel(
    'downloads_channel',
    'Song Downloads',
    description: 'Shows song download progress',
    importance: Importance.high,
  );

  await notifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(androidChannel);

  debugPrint("✅ Notifications initialized with channel 'downloads_channel'");
}

Future<void> showDownloadNotification(String title, double progress) async {
  final androidDetails = AndroidNotificationDetails(
    'downloads_channel',
    'Song Downloads',
    channelDescription: 'Shows song download progress',
    importance: Importance.max,
    icon: '@drawable/ic_launcher_foreground',
    priority: Priority.high,
    onlyAlertOnce: true,
    showProgress: true,
    maxProgress: 100,
    playSound: false,
    enableVibration: false,
    progress: progress.toInt(),
    subText: '${progress.toInt()}% completed',
  );

  final details = NotificationDetails(android: androidDetails);

  await notifications.show(
    0,
    '$title Downloading',
    'Downloading...',
    details,
    payload: 'download_progress',
  );
}

Future<void> cancelDownloadNotification() async {
  await notifications.cancel(0);
}
