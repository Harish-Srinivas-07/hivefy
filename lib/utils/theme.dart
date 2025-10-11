import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator_master/palette_generator_master.dart';
import 'package:shared_preferences/shared_preferences.dart';

const Color spotifyBgColor = Color(0xFF121212);
const Color spotifyGreen = Color(0xFF1DDA63);

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

Future<Color> getDominantColorFromImage(String imageUrl) async {
  try {
    final imageProvider = CachedNetworkImageProvider(imageUrl);

    final palette = await PaletteGeneratorMaster.fromImageProvider(
      imageProvider,
      maximumColorCount: 16,
      colorSpace: ColorSpace.lab,
      generateHarmony: false,
    );

    // Filter for colors that are dark but not black
    final darkColors =
        palette.paletteColors.map((e) => e.color).where((c) {
          final hsl = HSLColor.fromColor(c);
          return hsl.lightness < 0.35; // dark
        }).toList();

    if (darkColors.isNotEmpty) {
      // Pick the one with lowest lightness (darkest)
      darkColors.sort(
        (a, b) => HSLColor.fromColor(
          a,
        ).lightness.compareTo(HSLColor.fromColor(b).lightness),
      );
      return darkColors.first;
    }

    // fallback
    return Colors.grey.shade900;
  } catch (e) {
    debugPrint('Error generating dark color: $e');
    return Colors.grey.shade900;
  }
}

// lighter version
Color getDominantLighter(Color? color, {double lightenFactor = 0.3}) {
  final baseColor = color ?? Colors.grey.shade800;
  final hsl = HSLColor.fromColor(baseColor);
  return hsl
      .withLightness((hsl.lightness + lightenFactor).clamp(0.0, 1.0))
      .toColor();
}
