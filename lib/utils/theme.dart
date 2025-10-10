import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

Color spotifyBgColor = Color(0xFF121212);

class ThemeController {
  static final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(
    ThemeMode.system,
  );

  TextTheme spotifyTextTheme = const TextTheme(
    displayLarge: TextStyle(
      fontWeight: FontWeight.w900,
      letterSpacing: -1.2,
      height: 1.1,
    ),
    headlineLarge: TextStyle(
      fontWeight: FontWeight.w800,
      letterSpacing: -0.6,
      height: 1.1,
    ),
    titleLarge: TextStyle(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      height: 1.2,
    ),
    titleMedium: TextStyle(
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      height: 1.2,
    ),
    bodyLarge: TextStyle(
      fontWeight: FontWeight.w400,
      height: 1.25,
      letterSpacing: -0.1,
    ),
    bodyMedium: TextStyle(
      fontWeight: FontWeight.w300,
      height: 1.25,
      letterSpacing: -0.05,
    ),
    labelLarge: TextStyle(
      fontWeight: FontWeight.w500,
      letterSpacing: -0.2,
      height: 1.1,
    ),
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
  debugPrint(
    '--> here the colur ${colorScheme.primary} & ${colorScheme.brightness}',
  );
  // The dominant color is usually the 'primary' field
  return colorScheme.primary;
}

// darker
Color darken(Color color, [double amount = .2]) {
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withLightness((hsl.lightness - amount).clamp(0.0, 1.0))
      .withSaturation((hsl.saturation + 0.05).clamp(0.0, 1.0))
      .toColor();
}

// font family
class FontFamilies {
  static const spotifyMix = "SpotifyMix";
  static const spotifyMixUltra = "SpotifyMixUltra";
}
