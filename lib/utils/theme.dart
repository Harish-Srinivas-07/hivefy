import 'dart:math';

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
      letterSpacing: -0.7,
      height: 1.1,
    ),
    titleLarge: TextStyle(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      height: 1.2,
    ),
    titleMedium: TextStyle(
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
      height: 1.2,
    ),
    bodyLarge: TextStyle(
      fontWeight: FontWeight.w400,
      height: 1.25,
      letterSpacing: -0.3,
    ),
    bodyMedium: TextStyle(
      fontWeight: FontWeight.w300,
      height: 1.25,
      letterSpacing: -0.2,
    ),
    labelLarge: TextStyle(
      fontWeight: FontWeight.w500,
      letterSpacing: -0.4,
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

// colour defins

Future<Color> getDominantColorFromImage(String imageUrl) async {
  try {
    final imageProvider = CachedNetworkImageProvider(imageUrl);

    final palette = await PaletteGeneratorMaster.fromImageProvider(
      imageProvider,
      maximumColorCount: 24,
      colorSpace: ColorSpace.lab,
      generateHarmony: false,
    );

    int pop0(dynamic p) {
      try {
        return (p.population ?? p.count ?? p.pixelCount ?? 0) as int;
      } catch (_) {
        return 0;
      }
    }

    final entries = <Map<String, dynamic>>[];
    int maxPop = 0;
    for (final e in palette.paletteColors) {
      final Color c = (e as dynamic).color as Color;
      final int population = pop0(e);
      maxPop = max(maxPop, population);
      entries.add({'color': c, 'pop': population});
    }

    const double satWeight = 0.45;
    const double lightWeight = 0.35;
    const double popWeight = 0.20;
    const double targetLightness = 0.38;

    double bestScore = -9999;
    Color? bestColor;

    for (final e in entries) {
      final Color col = e['color'] as Color;
      final int pop = e['pop'] as int;
      if (col.a < 230) continue;

      final hsl = HSLColor.fromColor(col);
      final l = hsl.lightness;
      final s = hsl.saturation;
      final h = hsl.hue;

      // reject unusable colors
      if (l >= 0.9 || l <= 0.08) continue;
      if (s < 0.1) continue;
      if ((h >= 45 && h <= 65) && l > 0.6) continue;
      if ((h >= 170 && h <= 210) && l > 0.35) continue; // cyan / sky blue
      if ((h >= 210 && h <= 250) && s > 0.55 && l > 0.4) continue;
      if (h >= 180 && h <= 210 && l > 0.5) continue;

      final lightScore =
          1.0 - ((targetLightness - l).abs() / 0.5).clamp(0.0, 1.0);
      final popNorm = maxPop > 0 ? (pop / maxPop) : 0.0;

      final score =
          s * satWeight + lightScore * lightWeight + popNorm * popWeight;

      if (score > bestScore) {
        bestScore = score;
        bestColor = col;
      }
    }

    bestColor ??=
        palette.vibrantColor?.color ??
        palette.dominantColor?.color ??
        Colors.indigo.shade800;

    HSLColor hsl = HSLColor.fromColor(bestColor);

    // --- 🔥 Post-fix: correct unwanted blue/cyan tones ---
    double h = hsl.hue;
    double s = hsl.saturation;
    double l = hsl.lightness;

    if (h >= 170 && h <= 210) {
      // Sky blue → warm amber-brown
      h = 30;
      s = (s * 0.7).clamp(0.0, 1.0);
      l = (l * 0.55).clamp(0.0, 0.6);
    } else if (h >= 210 && h <= 250) {
      // Pure blue → indigo-violet
      h = 265;
      s = (s * 0.6).clamp(0.0, 1.0);
      l = (l * 0.5).clamp(0.0, 0.55);
    } else if ((h >= 40 && h <= 65 && l > 0.45) ||
        (h >= 70 && h <= 150 && l > 0.55)) {
      // Bright yellow or light green → brownish tone
      h = 30;
      s = (s * 0.7).clamp(0.0, 1.0);
      l = (l * 0.55).clamp(0.0, 0.6);
    }

    // --- Saturation & lightness tweaks for readability ---
    if (s < 0.25) s = (s + 0.25).clamp(0.0, 1.0);
    l = l.clamp(0.18, 0.65);

    hsl = HSLColor.fromAHSL(hsl.alpha, h, s, l);

    final result = hsl.toColor();
    debugPrint('--> corrected dominant colour: $result');

    return result;
  } catch (e, st) {
    debugPrint('Error generating dominant color: $e\n$st');
    return Colors.indigo.shade800;
  }
}

// lighter but safe
Color getDominantLighter(Color? color, {double lightenFactor = 0.22}) {
  final baseColor = color ?? Colors.indigo.shade800;
  final hsl = HSLColor.fromColor(baseColor);

  final newLight = (hsl.lightness + lightenFactor).clamp(0.0, 0.75);
  final newSat = max(hsl.saturation, 0.25);

  return hsl.withLightness(newLight).withSaturation(newSat).toColor();
}

// darker but not dead black
Color getDominantDarker(Color? color, {double darkenFactor = 0.18}) {
  final baseColor = color ?? Colors.indigo.shade800;
  final hsl = HSLColor.fromColor(baseColor);

  final newLight = (hsl.lightness - darkenFactor).clamp(0.12, 1.0);
  final newSat = (hsl.saturation + 0.1).clamp(0.0, 1.0);

  return hsl.withLightness(newLight).withSaturation(newSat).toColor();
}
