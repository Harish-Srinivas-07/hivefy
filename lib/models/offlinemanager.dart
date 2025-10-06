import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/datamodel.dart';
import '../models/database.dart';
import '../services/localnotification.dart';

// instance
final offlineManager = OfflineStorageManager();

enum DownloadStatus { idle, downloading, completed, failed }

class OfflineStorageManager {
  static const _offlineKey = "offlineSongs";
  static final OfflineStorageManager _instance =
      OfflineStorageManager._internal();
  factory OfflineStorageManager() => _instance;
  OfflineStorageManager._internal();

  Map<String, String> _offlineSongs = {};
  Map<String, DownloadStatus> downloadStatus = {};
  Map<String, double> downloadProgress = {};

  /// Initialize
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_offlineKey);
    if (stored != null) {
      _offlineSongs = Map<String, String>.from(jsonDecode(stored));
    }

    // invalid songs clean up
    await cleanupInvalidDownloads();

    // Remove missing files
    final removed = <String>[];
    _offlineSongs.forEach((id, path) {
      if (!File(path).existsSync()) removed.add(id);
    });
    for (var id in removed) {
      _offlineSongs.remove(id);
    }
    if (removed.isNotEmpty) await _save();
  }

  Future<Directory> getOfflineDirectory() async {
    final dir = await getApplicationSupportDirectory();
    final offlineDir = Directory("${dir.path}/OfflineSongs");
    if (!offlineDir.existsSync()) {
      await offlineDir.create(recursive: true);
    }
    return offlineDir;
  }

  /// Download status getters
  DownloadStatus getDownloadStatus(String songId) =>
      downloadStatus[songId] ?? DownloadStatus.idle;

  double getDownloadProgress(String songId) => downloadProgress[songId] ?? 0.0;

  bool isDownloaded(String songId) => _offlineSongs.containsKey(songId);

  String? getLocalPath(String songId) => _offlineSongs[songId];

  /// Download song with progress
  Future<void> downloadSong(
    String songId, {
    Function(double)? onProgress,
  }) async {
    final song = await AppDatabase.getSong(songId);
    if (song == null || song.downloadUrls.isEmpty) return;

    final offlineDir = await getOfflineDirectory();
    final filePath = "${offlineDir.path}/$songId.mp3";

    if (File(filePath).existsSync()) {
      _offlineSongs[songId] = filePath;
      downloadStatus[songId] = DownloadStatus.completed;
      await _save();
      return;
    }

    try {
      downloadStatus[songId] = DownloadStatus.downloading;
      downloadProgress[songId] = 0.0;

      // 🔔 Show initial notification
      await showDownloadNotification(song.title, 0);

      await Dio().download(
        song.downloadUrls.last.url,
        filePath,
        onReceiveProgress: (received, total) async {
          if (total != -1) {
            double progress = (received / total) * 100;
            downloadProgress[songId] = progress;
            if (onProgress != null) onProgress(progress);

            // Update notification with progress
            await showDownloadNotification(song.title, progress);
          }
        },
      );

      _offlineSongs[songId] = filePath;
      downloadStatus[songId] = DownloadStatus.completed;
      downloadProgress[songId] = 100.0;

      // Song Complete notify
      await showDownloadNotification(song.title, 100);
      Future.delayed(const Duration(seconds: 2), cancelDownloadNotification);

      await _save();
    } catch (e) {
      downloadStatus[songId] = DownloadStatus.failed;
      downloadProgress[songId] = 0.0;
      debugPrint("Download failed for $songId: $e");
      await cancelDownloadNotification();
    }
  }

  /// Delete a song
  Future<void> deleteSong(String songId) async {
    final path = _offlineSongs[songId];
    if (path != null && File(path).existsSync()) {
      await File(path).delete();
    }
    _offlineSongs.remove(songId);
    downloadStatus.remove(songId);
    downloadProgress.remove(songId);
    await _save();
  }

  /// Get all downloaded songs
  Future<List<SongDetail>> getDownloadedSongs() async {
    return AppDatabase.getSongs(_offlineSongs.keys.toList());
  }

  /// Get all downloaded song IDs
  List<String> getAllSongIds() => _offlineSongs.keys.toList();

  /// STore more then 1 song
  Future<void> downloadSongsSet(
    Set<String> songIds, {
    Function(String songId, double progress)? onProgress,
  }) async {
    for (final songId in songIds) {
      await downloadSong(
        songId,
        onProgress: (progress) {
          if (onProgress != null) onProgress(songId, progress);
        },
      );
    }
  }

  /// Delete all offline songs
  Future<void> deleteAllSongs() async {
    final offlineDir = await getOfflineDirectory();
    if (offlineDir.existsSync()) {
      await offlineDir.delete(recursive: true);
    }
    _offlineSongs.clear();
    downloadStatus.clear();
    downloadProgress.clear();
    await _save();
  }

  /// Save offline data
  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(_offlineKey, jsonEncode(_offlineSongs));
  }

  // ---------------- HELPERS --------------------
  /// Get the full download info for a single song
  Map<String, dynamic> getSongDownloadInfo(String songId) {
    return {
      'id': songId,
      'isDownloaded': isDownloaded(songId),
      'status': getDownloadStatus(songId),
      'progress': getDownloadProgress(songId),
      'localPath': getLocalPath(songId),
    };
  }

  /// Check if a song is downloading, completed, etc.
  DownloadStatus getSongDownloadStatus(String songId) {
    return getDownloadStatus(songId);
  }

  /// Trigger download with automatic progress update
  Future<void> requestSongDownload(
    String songId, {
    Function(double)? onProgress,
  }) async {
    await downloadSong(songId, onProgress: onProgress);
  }

  /// Get all downloaded SongDetails from DB (for UI listing)
  Future<List<SongDetail>> getDownloadedSongsDetailed() async {
    return getDownloadedSongs();
  }

  /// Get all songs with their current download states (for list views)
  List<Map<String, dynamic>> getAllDownloadStates() {
    return _offlineSongs.keys.map((id) => getSongDownloadInfo(id)).toList();
  }

  // ------------------ INVALID CLEANUP -----------------------
  /// Clean invalid or missing offline files
  Future<void> cleanupInvalidDownloads() async {
    final removed = <String>[];

    _offlineSongs.forEach((id, path) {
      final file = File(path);
      if (!file.existsSync() || file.lengthSync() == 0) {
        removed.add(id);
      }
    });

    for (final id in removed) {
      _offlineSongs.remove(id);
      downloadStatus.remove(id);
      downloadProgress.remove(id);
    }

    if (removed.isNotEmpty) {
      await _save();
      debugPrint("🧹 Cleaned ${removed.length} invalid offline songs");
    } else {
      debugPrint("🧹 No invalid downloads found");
    }
  }
}
