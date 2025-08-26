import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController {
  static final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(
    ThemeMode.system,
  );

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final isDark = prefs.getBool('isDarkTheme');
    if (isDark != null) {
      themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
      prefs.setBool('isDarkTheme', isDark);
    } else {
      themeNotifier.value = ThemeMode.system;
    }
  }

  static Future<void> toggleTheme(bool isDark) async {
    themeNotifier.value = isDark ? ThemeMode.dark : ThemeMode.light;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkTheme', isDark);
  }

  static bool isDarkFromContext(BuildContext context) {
    final mode = themeNotifier.value;
    if (mode == ThemeMode.system) {
      final brightness = MediaQuery.of(context).platformBrightness;
      return brightness == Brightness.dark;
    }
    return mode == ThemeMode.dark;
  }

}


Future<Color?> getDominantColorFromImage(String imageUrl) async {
  final colorScheme = await ColorScheme.fromImageProvider(
    provider: NetworkImage(imageUrl),
  );
  // The dominant color is usually the 'primary' field
  return colorScheme.primary;
}
