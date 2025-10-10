import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/datamodel.dart';
import '../models/database.dart';
import 'localnotification.dart';

// instance
final offlineManager = OfflineStorageManager();

enum DownloadStatus { idle, downloading, completed, failed }

class OfflineStorageManager {
  static const _offlineKey = "offlineSongs";
  static const _albumKey = "offlineAlbums";

  static final OfflineStorageManager _instance =
      OfflineStorageManager._internal();
  factory OfflineStorageManager() => _instance;
  OfflineStorageManager._internal();

  Map<String, String> _offlineSongs = {};
  Set<String> _downloadedAlbums = {};

  Map<String, DownloadStatus> downloadStatus = {};
  Map<String, double> downloadProgress = {};
  final Map<String, ValueNotifier<double>> _progressNotifiers = {};
  final Map<String, ValueNotifier<DownloadStatus>> _statusNotifiers = {};

  ValueNotifier<double> progressNotifier(String songId) {
    if (!_progressNotifiers.containsKey(songId)) {
      _progressNotifiers[songId] = ValueNotifier<double>(
        getDownloadProgress(songId),
      );
    }
    return _progressNotifiers[songId]!;
  }

  ValueNotifier<DownloadStatus> statusNotifier(String songId) {
    if (!_statusNotifiers.containsKey(songId)) {
      _statusNotifiers[songId] = ValueNotifier<DownloadStatus>(
        getDownloadStatus(songId),
      );
    }
    return _statusNotifiers[songId]!;
  }

  void updateStatus(String songId, DownloadStatus status) {
    if (!_statusNotifiers.containsKey(songId)) {
      _statusNotifiers[songId] = ValueNotifier(status);
    } else {
      _statusNotifiers[songId]!.value = status;
    }
    downloadStatus[songId] = status;
  }

  void updateProgress(String songId, double progress) {
    if (!_progressNotifiers.containsKey(songId)) {
      _progressNotifiers[songId] = ValueNotifier(progress);
    } else {
      _progressNotifiers[songId]!.value = progress;
    }
    downloadProgress[songId] = progress;
  }

  /// Initialize
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_offlineKey);
    final storedAlbums = prefs.getStringList(_albumKey);
    if (stored != null) {
      _offlineSongs = Map<String, String>.from(jsonDecode(stored));
    }
    if (storedAlbums != null) {
      _downloadedAlbums = storedAlbums.toSet();
    }

    await cleanupInvalidDownloads();
    final removed = <String>[];
    _offlineSongs.forEach((id, path) {
      if (!File(path).existsSync()) removed.add(id);
    });
    for (var id in removed) {
      _offlineSongs.remove(id);
    }
    if (removed.isNotEmpty) await _save();

    // ✅ Rebuild in-memory state for all valid downloaded songs
    for (final songId in _offlineSongs.keys) {
      updateStatus(songId, DownloadStatus.completed);
      updateProgress(songId, 100.0);
    }

    // ✅ Restore album status based on saved album list
    for (final albumId in _downloadedAlbums) {
      albumStatusNotifier(albumId).value = DownloadStatus.completed;
    }
  }

  Future<Directory> getOfflineDirectory() async {
    final dir = await getApplicationSupportDirectory();
    final offlineDir = Directory("${dir.path}/OfflineSongs");
    if (!offlineDir.existsSync()) {
      await offlineDir.create(recursive: true);
    }
    debugPrint("Offline directory path: ${offlineDir.path}");
    return offlineDir;
  }

  /// Getters
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
    debugPrint("📥 Starting download for songId: $songId");

    final song = await AppDatabase.getSong(songId);
    if (song == null || song.downloadUrls.isEmpty) {
      debugPrint("⚠️ Song data missing or no download URLs for $songId");
      return;
    }

    _progressNotifiers[songId] ??= ValueNotifier<double>(0.0);
    _statusNotifiers[songId] ??= ValueNotifier<DownloadStatus>(
      DownloadStatus.idle,
    );

    updateStatus(songId, DownloadStatus.downloading);
    updateProgress(songId, 0.0);

    final offlineDir = await getOfflineDirectory();
    debugPrint("📂 Offline directory path: ${offlineDir.path}");

    final filePath = "${offlineDir.path}/$songId.mp3";
    debugPrint("💾 File will be saved at: $filePath");

    final dio = Dio(
      BaseOptions(
        responseType: ResponseType.bytes,
        followRedirects: true,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 120),
        sendTimeout: const Duration(seconds: 60),
        receiveDataWhenStatusError: true,
        validateStatus: (_) => true,
      ),
    );

    try {
      await showDownloadNotification('${song.title} from ${song.album}', 0);
      debugPrint("🔔 Showing download notification for: ${song.title}");

      int lastTick = 0;
      await dio.download(
        song.downloadUrls.last.url,
        filePath,
        onReceiveProgress: (received, total) async {
          if (total != -1) {
            double progress = (received / total) * 100;

            updateProgress(songId, progress);
            if (onProgress != null) onProgress(progress);

            if (progress - lastTick >= 10 || progress >= 100) {
              debugPrint(
                "📊 Download progress for $songId: ${progress.toStringAsFixed(2)}%",
              );
              lastTick = progress.toInt();
              await showDownloadNotification(
                '${song.title} from ${song.album}',
                progress,
              );
            }
          }
        },
      );

      debugPrint("✅ Download completed for songId: $songId");
      _offlineSongs[songId] = filePath;
      updateProgress(songId, 100.0);
      updateStatus(songId, DownloadStatus.completed);

      await showDownloadNotification('${song.title} from ${song.album}', 100);
      Future.delayed(const Duration(seconds: 5), cancelDownloadNotification);

      await _save();
      debugPrint("💾 Download saved successfully for $songId");
    } catch (e) {
      updateStatus(songId, DownloadStatus.failed);
      updateProgress(songId, 0.0);
      debugPrint("❌ Download failed for $songId: $e");
      await cancelDownloadNotification();
    }
  }

  /// Delete song
  Future<void> deleteSong(String songId) async {
    final path = _offlineSongs[songId];
    if (path != null && File(path).existsSync()) {
      await File(path).delete();
    }
    _offlineSongs.remove(songId);

    // Update notifiers to reflect deletion
    updateStatus(songId, DownloadStatus.idle);
    updateProgress(songId, 0.0);

    await _save();
  }

  /// Quick check if a song or album is downloaded
  bool isAvailableOffline({String? songId, String? albumId}) {
    if (songId != null) return _offlineSongs.containsKey(songId);
    if (albumId != null) return _downloadedAlbums.contains(albumId);
    return false;
  }

  /// Quick getter for download status
  DownloadStatus getDownloadStatusQuick({String? songId, String? albumId}) {
    if (songId != null) return getDownloadStatus(songId);
    if (albumId != null) {
      return _downloadedAlbums.contains(albumId)
          ? DownloadStatus.completed
          : DownloadStatus.idle;
    }
    return DownloadStatus.idle;
  }

  Future<List<SongDetail>> getDownloadedSongs() async {
    return AppDatabase.getSongs(_offlineSongs.keys.toList());
  }

  List<String> getAllSongIds() => _offlineSongs.keys.toList();

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

  Future<void> deleteAllSongs() async {
    final offlineDir = await getOfflineDirectory();
    if (offlineDir.existsSync()) {
      await offlineDir.delete(recursive: true);
    }
    _offlineSongs.clear();
    downloadStatus.clear();
    downloadProgress.clear();
    _progressNotifiers.clear();
    _statusNotifiers.clear();
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(_offlineKey, jsonEncode(_offlineSongs));
    await prefs.setStringList(_albumKey, _downloadedAlbums.toList());
  }

  Map<String, dynamic> getSongDownloadInfo(String songId) {
    return {
      'id': songId,
      'isDownloaded': isDownloaded(songId),
      'status': getDownloadStatus(songId),
      'progress': getDownloadProgress(songId),
      'localPath': getLocalPath(songId),
    };
  }

  DownloadStatus getSongDownloadStatus(String songId) =>
      getDownloadStatus(songId);

  Future<void> requestSongDownload(
    String songId, {
    Function(double)? onProgress,
  }) async {
    await downloadSong(songId, onProgress: onProgress);
  }

  Future<List<SongDetail>> getDownloadedSongsDetailed() async {
    return getDownloadedSongs();
  }

  List<Map<String, dynamic>> getAllDownloadStates() {
    return _offlineSongs.keys.map((id) => getSongDownloadInfo(id)).toList();
  }

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

  // 🔹 Album Download Status Handling
  bool isAlbumDownloaded(String albumId) => _downloadedAlbums.contains(albumId);

  void markAlbumAsDownloaded(String albumId) {
    _downloadedAlbums.add(albumId);
    albumStatusNotifier(albumId).value = DownloadStatus.completed;
    _save();
    debugPrint("✅ Album $albumId marked as fully downloaded");
  }

  void unmarkAlbum(String albumId) {
    _downloadedAlbums.remove(albumId);
    albumStatusNotifier(albumId).value = DownloadStatus.idle;
    _save();
    debugPrint("❌ Album $albumId unmarked (not fully downloaded)");
  }

  List<String> getAllDownloadedAlbums() => _downloadedAlbums.toList();

  Future<void> downloadAlbumSongs(
    Album album, {
    Function(String songId, double progress)? onProgress,
  }) async {
    final songIds =
        album.songIds.isNotEmpty
            ? album.songIds
            : album.songs.map((s) => s.id).toList();

    albumStatusNotifier(album.id).value = DownloadStatus.downloading;
    albumDownloadedCountNotifier(album.id).value = 0;

    int completedCount = 0;

    for (final songId in songIds) {
      await downloadSong(
        songId,
        onProgress: (progress) {
          if (onProgress != null) onProgress(songId, progress);
        },
      );

      completedCount++;
      albumDownloadedCountNotifier(album.id).value = completedCount;
    }

    // Check if all songs are downloaded successfully
    final allDownloaded = songIds.every(
      (id) => getDownloadStatus(id) == DownloadStatus.completed,
    );

    if (allDownloaded) {
      markAlbumAsDownloaded(album.id);
    } else {
      unmarkAlbum(album.id);
    }
  }

  int getDownloadedCountForAlbum(Album album) {
    final songIds =
        album.songIds.isNotEmpty
            ? album.songIds
            : album.songs.map((s) => s.id).toList();
    return songIds
        .where((id) => getDownloadStatus(id) == DownloadStatus.completed)
        .length;
  }

  final Map<String, ValueNotifier<int>> _albumDownloadedCounts = {};
  final Map<String, ValueNotifier<DownloadStatus>> _albumStatusNotifiers = {};

  ValueNotifier<int> albumDownloadedCountNotifier(String albumId) {
    if (!_albumDownloadedCounts.containsKey(albumId)) {
      _albumDownloadedCounts[albumId] = ValueNotifier<int>(0);
    }
    return _albumDownloadedCounts[albumId]!;
  }

  ValueNotifier<DownloadStatus> albumStatusNotifier(String albumId) {
    if (!_albumStatusNotifiers.containsKey(albumId)) {
      _albumStatusNotifiers[albumId] = ValueNotifier<DownloadStatus>(
        DownloadStatus.idle,
      );
    }
    return _albumStatusNotifiers[albumId]!;
  }
}
