import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';

// handle update tracker
bool isAppUpdateAvailable = false;

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
  await Future.delayed(const Duration(seconds: 1));

  if (!await InternetConnection().hasInternetAccess) {
    debugPrint('[UPDATERTOOL] Update check skipped: No internet connection.');
    return;
  }

  try {
    debugPrint('[UPDATERTOOL] Checking for update via GitHub...');
    final updateInfo = await githubUpdate();

    if (updateInfo['results'] == true) {
      debugPrint(
        '[UPDATERTOOL] ✅ Update available (GitHub): ${updateInfo['newVer']}',
      );
      isAppUpdateAvailable = true;
      return;
    }

    debugPrint(
      '[UPDATERTOOL] No update found on GitHub, checking SourceForge...',
    );
    final sfUpdate = await sourceforgeUpdate();
    if (sfUpdate['results'] == true) {
      debugPrint(
        '[UPDATERTOOL] ✅ Update available (SourceForge): ${sfUpdate['newVer']}',
      );
      isAppUpdateAvailable = true;
    } else {
      debugPrint('[UPDATERTOOL] No update available on either platform.');
      isAppUpdateAvailable = false;
    }
  } catch (e) {
    debugPrint(
      '[UPDATERTOOL] GitHub check failed: $e — trying SourceForge fallback...',
    );
    try {
      final sfUpdate = await sourceforgeUpdate();
      if (sfUpdate['results'] == true) {
        debugPrint(
          '[UPDATERTOOL] ✅ Update available (SourceForge): ${sfUpdate['newVer']}',
        );
        isAppUpdateAvailable = true;
      } else {
        debugPrint('[UPDATERTOOL] ❌ No update available.');
        isAppUpdateAvailable = false;
      }
    } catch (e2) {
      debugPrint('[UPDATERTOOL] ❌ Both update checks failed: $e2');
    }
  }
}

bool isUpdateAvailable(
  String currentVer,
  String currentBuild,
  String newVer,
  String newBuild, {
  bool checkBuild = true,
}) {
  try {
    final currentParts = currentVer.split('.').map(int.parse).toList();
    final newParts = newVer.split('.').map(int.parse).toList();

    for (int i = 0; i < currentParts.length; i++) {
      if (newParts[i] > currentParts[i]) return true;
      if (newParts[i] < currentParts[i]) return false;
    }

    if (checkBuild) {
      int currBuild = int.tryParse(currentBuild) ?? 0;
      int nextBuild = int.tryParse(newBuild) ?? 0;

      if (currBuild > 1000) currBuild %= 1000;
      return nextBuild > currBuild;
    }
  } catch (e) {
    debugPrint('[UPDATERTOOL] Version comparison failed: $e');
  }
  return false;
}

// -------------------- SOURCEFORGE UPDATE --------------------
Future<Map<String, dynamic>> sourceforgeUpdate() async {
  const url = 'https://sourceforge.net/projects/hivefy/files/json';

  final headers = {
    'User-Agent':
        'Mozilla/5.0 (Linux; Android 13; HivefyApp) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Mobile Safari/537.36',
    'Accept': 'application/json',
    'Referer': 'https://sourceforge.net/projects/hivefy/',
  };

  final response = await get(Uri.parse(url), headers: headers);
  final packageInfo = await PackageInfo.fromPlatform();

  if (response.statusCode == 200) {
    final data = json.decode(response.body);

    // Get the latest entry from the "files" list
    final latest = data['files']?.firstWhere(
      (f) => f['name'].toString().contains('v'),
      orElse: () => null,
    );

    if (latest == null) {
      debugPrint('[UPDATER] No release found in file list.');
      return {'results': false};
    }

    final filename = latest['name'] as String;
    final versionMatch = RegExp(r'v(\d+\.\d+\.\d+)').firstMatch(filename);
    final buildMatch = RegExp(r'\+(\d+)').firstMatch(filename);

    final version = versionMatch?.group(1) ?? '0.0.0';
    final build = buildMatch?.group(1) ?? '0';
    final downloadUrl = latest['download_url'];

    final currBuild =
        int.parse(packageInfo.buildNumber) > 1000
            ? (int.parse(packageInfo.buildNumber) % 1000).toString()
            : packageInfo.buildNumber;

    return {
      'newVer': version,
      'newBuild': build,
      'download_url': downloadUrl,
      'currVer': packageInfo.version,
      'currBuild': currBuild,
      'results': isUpdateAvailable(
        packageInfo.version,
        packageInfo.buildNumber,
        version,
        build,
      ),
    };
  }

  debugPrint('[UPDATER] Failed: ${response.statusCode}');
  return {'results': false};
}

// -------------------- GITHUB UPDATE --------------------
Future<Map<String, dynamic>> githubUpdate() async {
  final packageInfo = await PackageInfo.fromPlatform();
  try {
    final response = await get(
      Uri.parse(
        'https://api.github.com/repos/Harish-Srinivas-07/hivefy/releases/latest',
      ),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final tagName = data['tag_name'] as String? ?? '';

      // Safe parsing for tagName like "v1.0.0+12"
      final tagParts = tagName.split('+');
      final version =
          tagParts.isNotEmpty ? tagParts.first.replaceFirst('v', '') : '0.0.0';
      final newBuildVer = tagParts.length > 1 ? tagParts[1] : '0';

      final currBuild =
          int.parse(packageInfo.buildNumber) > 1000
              ? (int.parse(packageInfo.buildNumber) % 1000).toString()
              : packageInfo.buildNumber;

      return {
        'results': isUpdateAvailable(
          packageInfo.version,
          packageInfo.buildNumber,
          version,
          newBuildVer,
          checkBuild: false,
        ),
        'newBuild': newBuildVer,
        'currBuild': currBuild,
        'currVer': packageInfo.version,
        'newVer': version,
        'download_url':
            "https://sourceforge.net/projects/hivefy/files/latest/download",
      };
    } else {
      debugPrint('[UPDATERTOOL] GitHub API failed: ${response.statusCode}');
      return {'results': false};
    }
  } catch (e) {
    debugPrint('[UPDATERTOOL] GitHub check error: $e');
    return {'results': false};
  }
}
