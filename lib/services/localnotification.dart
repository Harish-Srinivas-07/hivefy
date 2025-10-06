import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin _notifications =
    FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  const androidSettings = AndroidInitializationSettings(
    'drawable/ic_launcher_foreground',
  );
  const initSettings = InitializationSettings(android: androidSettings);
  await _notifications.initialize(initSettings);
}

Future<void> showDownloadNotification(String title, double progress) async {
  const androidDetails = AndroidNotificationDetails(
    'downloads_channel',
    'Song Downloads',
    channelDescription: 'Shows song download progress',
    importance: Importance.max,
    priority: Priority.high,
    onlyAlertOnce: true,
    showProgress: true,
    maxProgress: 100,
  );

  await _notifications.show(
    712002,
    '$title Downloading',
    '${progress.toStringAsFixed(1)}% completed, we recommened not to close the app!',
    NotificationDetails(android: androidDetails),
    payload: 'download_progress',
  );
}

Future<void> cancelDownloadNotification() async {
  await _notifications.cancel(0);
}
