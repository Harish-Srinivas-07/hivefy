import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hivefy/utils/logger.dart';

final FlutterLocalNotificationsPlugin notifications = FlutterLocalNotificationsPlugin();

/// Returns the platform notification setting, or null when unavailable.
Future<bool?> areNotificationsEnabled() async {
  try {
    final android = notifications.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) return await android.areNotificationsEnabled();

    final ios = notifications.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final settings = await ios.checkPermissions();
      if (settings == null) return null;
      return settings.isEnabled || settings.isProvisionalEnabled;
    }
  } catch (error) {
    Logger.error('LocalNotification', 'Unable to check notification settings: $error');
  }
  return null;
}

Future<void> requestNotificationPermission() async {
  if (!await Permission.notification.isGranted) {
    await Permission.notification.request();
  }
}

Future<void> initNotifications() async {
  const androidSettings = AndroidInitializationSettings('@drawable/ic_launcher_foreground');
  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );
  const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);

  await notifications.initialize(initSettings);

  const androidChannel = AndroidNotificationChannel(
    'downloads_channel',
    'Song Downloads',
    description: 'Shows song download progress',
    importance: Importance.high,
  );

  await notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(androidChannel);

  const generalChannel = AndroidNotificationChannel(
    'general_channel',
    'General Notifications',
    description: 'General app notifications to make engage users',
    importance: Importance.high,
  );

  await notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(generalChannel);

  Logger.success('LocalNotification', "✅ Notifications initialized with channel 'downloads_channel'");
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
    silent: true,
    colorized: true,
    progress: progress.toInt(),
    subText: '${progress.toInt()}% completed',
  );

  final details = NotificationDetails(android: androidDetails);

  await notifications.show(0, title, 'Downloading...', details, payload: 'download_progress');
}

Future<void> cancelDownloadNotification() async {
  await notifications.cancel(0);
}

Future<void> showSimpleNotification(String title, String body) async {
  const androidDetails = AndroidNotificationDetails(
    'general_channel',
    'General Notifications',
    channelDescription: 'General app notifications to make engage users',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
    icon: '@drawable/ic_launcher_foreground',
  );

  const details = NotificationDetails(android: androidDetails);

  await notifications.show(DateTime.now().millisecondsSinceEpoch ~/ 1000, title, body, details);
}
