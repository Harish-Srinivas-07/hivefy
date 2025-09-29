import 'package:flutter/material.dart';

import '../models/datamodel.dart';

String capitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1);
}

String formatDuration(int totalSeconds) {
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;

  final parts = <String>[];
  if (hours > 0) parts.add("$hours hr${hours > 1 ? 's' : ''}");
  if (minutes > 0) parts.add("$minutes min${minutes > 1 ? 's' : ''}");
  if (seconds > 0 || parts.isEmpty) {
    parts.add("$seconds sec${seconds > 1 ? 's' : ''}");
  }

  return parts.join(" ");
}

// '('- format text
String trimAfterParamText(String text) {
  final index = text.indexOf('(');
  if (index == -1) return text; // no '(' found → return full
  return text.substring(0, index).trim(); // cut after '(' and trim spaces
}

String sanitizeBio(String bio) {
  try {
    final match = RegExp(
      r'\{text\s*:\s*(.*?)(?:,\s*title\s*:\s*.*)?\}$',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(bio);

    if (match != null && match.groupCount >= 1) {
      return unescape.convert(match.group(1)!.trim());
    }

    // fallback: unescape the whole string
    return unescape.convert(bio.trim());
  } catch (e) {
    debugPrint("sanitizeBio error: $e");
    return bio;
  }
}
