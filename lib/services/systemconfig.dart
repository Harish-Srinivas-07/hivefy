import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

class SystemUiConfigurator {
  static Future<void> configure() async {
    // Restrict orientation
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);

    // Set edge-to-edge system UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
  }
}

Future<void> checkForUpdate() async {
  await Future.delayed(const Duration(seconds: 2));
  if (await InternetConnection().hasInternetAccess) {
    try {
      //  TODO: make check app update
    } catch (e) {
      debugPrint('Update check failed: $e');
    }
  } else {
    debugPrint('Update check skipped: no internet connection');
  }
}
