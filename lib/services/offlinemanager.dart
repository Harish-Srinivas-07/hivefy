import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:hivefy/components/snackbar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hivefy/utils/logger.dart';

import '../models/datamodel.dart';
import '../models/database.dart';
import 'youtube.dart';
import 'chunk_downloader.dart';
import 'localnotification.dart';

// instance
final offlineManager = OfflineStorageManager();

enum DownloadStatus { idle, downloading, completed, failed }

class OfflineStorageManager {
  static const _offlineKey = "offlineSongs";
  static const _albumKey = "offlineAlbums";
  static const _cacheKey = "cachedSongs";

  static final OfflineStorageManager _instance = OfflineStorageManager._internal();
  factory OfflineStorageManager() => _instance;
  OfflineStorageManager._internal();

  Map<String, String> _offlineSongs = {};
  final ValueNotifier<int> _downloadedSongsRevision = ValueNotifier(0);
  ValueListenable<int> get downloadedSongsRevision => _downloadedSongsRevision;
  void _notifyDownloadedSongsChanged() => _downloadedSongsRevision.value++;
  Map<String, String> _cachedSongs = {};
  Set<String> _downloadedAlbums = {};

  Map<String, DownloadStatus> downloadStatus = {};
  Map<String, double> downloadProgress = {};
  final Map<String, ValueNotifier<double>> _progressNotifiers = {};
  final Map<String, ValueNotifier<DownloadStatus>> _statusNotifiers = {};
  final Map<String, Future<void>> _activeDownloads = {};
  final Map<String, Future<void>> _activeCaches = {};
  Future<void> _downloadQueue = Future.value();

  // Below your album-related maps
  final Map<String, ValueNotifier<int>> _setDownloadedCounts = {};
  final Map<String, ValueNotifier<DownloadStatus>> _setStatusNotifiers = {};

  ValueNotifier<int> songsSetDownloadedCountNotifier(String setId) {
    if (!_setDownloadedCounts.containsKey(setId)) {
      _setDownloadedCounts[setId] = ValueNotifier<int>(0);
    }
    return _setDownloadedCounts[setId]!;
  }

  ValueNotifier<DownloadStatus> songsSetStatusNotifier(String setId) {
    if (!_setStatusNotifiers.containsKey(setId)) {
      _setStatusNotifiers[setId] = ValueNotifier<DownloadStatus>(DownloadStatus.idle);
    }
    return _setStatusNotifiers[setId]!;
  }

  ValueNotifier<double> progressNotifier(String songId) {
    if (!_progressNotifiers.containsKey(songId)) {
      _progressNotifiers[songId] = ValueNotifier<double>(getDownloadProgress(songId));
    }
    return _progressNotifiers[songId]!;
  }

  ValueNotifier<DownloadStatus> statusNotifier(String songId) {
    if (!_statusNotifiers.containsKey(songId)) {
      _statusNotifiers[songId] = ValueNotifier<DownloadStatus>(getDownloadStatus(songId));
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
    final storedCache = prefs.getString(_cacheKey);

    if (stored != null) {
      _offlineSongs = Map<String, String>.from(jsonDecode(stored));
    }
    if (storedAlbums != null) {
      _downloadedAlbums = storedAlbums.toSet();
    }
    if (storedCache != null) {
      _cachedSongs = Map<String, String>.from(jsonDecode(storedCache));
    }

    await cleanupInvalidDownloads();

    // Cleanup invalid cache entries
    final removedCache = <String>[];
    _cachedSongs.forEach((id, path) {
      if (!File(path).existsSync()) removedCache.add(id);
    });
    for (var id in removedCache) {
      _cachedSongs.remove(id);
    }

    final removed = <String>[];
    _offlineSongs.forEach((id, path) {
      if (!File(path).existsSync()) removed.add(id);
    });
    for (var id in removed) {
      _offlineSongs.remove(id);
    }

    if (removed.isNotEmpty || removedCache.isNotEmpty) await _save();

    // Rebuild in-memory state for all valid downloaded songs
    for (final songId in _offlineSongs.keys) {
      updateStatus(songId, DownloadStatus.completed);
      updateProgress(songId, 100.0);
    }

    // Restore album status based on saved album list
    for (final albumId in _downloadedAlbums) {
      albumStatusNotifier(albumId).value = DownloadStatus.completed;
    }
    _notifyDownloadedSongsChanged();
  }

  Future<Directory> getOfflineDirectory() async {
    final dir = await getApplicationSupportDirectory();
    final offlineDir = Directory("${dir.path}/OfflineSongs");
    if (!offlineDir.existsSync()) {
      await offlineDir.create(recursive: true);
    }
    Logger.log('OfflineManager', "Offline directory path: ${offlineDir.path}");
    return offlineDir;
  }

  Future<Directory> getCacheDirectory() async {
    final dir = await getApplicationSupportDirectory();
    final cacheDir = Directory("${dir.path}/SongCache");
    if (!cacheDir.existsSync()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir;
  }

  /// Getters
  DownloadStatus getDownloadStatus(String songId) => downloadStatus[songId] ?? DownloadStatus.idle;

  double getDownloadProgress(String songId) => downloadProgress[songId] ?? 0.0;

  bool isDownloaded(String songId) => _offlineSongs.containsKey(songId);

  bool isCached(String songId) => _cachedSongs.containsKey(songId);

  String? getLocalPath(String songId) {
    if (_offlineSongs.containsKey(songId)) return _offlineSongs[songId];
    if (_cachedSongs.containsKey(songId)) return _cachedSongs[songId];
    return null;
  }

  /// Cache song silently with the same validated downloader used for offline files.
  Future<void> cacheSong(String songId) {
    if (isDownloaded(songId) || isCached(songId) || _activeDownloads.containsKey(songId)) {
      return Future.value();
    }
    final existing = _activeCaches[songId];
    if (existing != null) return existing;
    final job = _cacheSong(songId);
    _activeCaches[songId] = job;
    job.whenComplete(() => _activeCaches.remove(songId));
    return job;
  }

  Future<void> _cacheSong(String songId) async {
    try {
      final song = await AppDatabase.getSong(songId);
      if (song == null) return;
      final path = await _downloadAudio(song, await getCacheDirectory());
      _cachedSongs[songId] = path;
      if (_cachedSongs.length > 50) {
        final oldest = _cachedSongs.keys.first;
        final oldPath = _cachedSongs.remove(oldest);
        if (oldPath != null && await File(oldPath).exists()) {
          await File(oldPath).delete();
        }
      }
      await _save();
    } catch (e) {
      Logger.error('OfflineManager', 'Cache failed for $songId: $e');
    }
  }

  /// Queue downloads one at a time and coalesce requests for the same song.
  Future<void> downloadSong(String songId, {SongDetail? song, Function(double)? onProgress}) {
    if (isDownloaded(songId)) {
      updateStatus(songId, DownloadStatus.completed);
      updateProgress(songId, 100);
      return Future.value();
    }
    final existing = _activeDownloads[songId];
    if (existing != null) return existing;
    updateStatus(songId, DownloadStatus.downloading);
    updateProgress(songId, 0);
    final job = _downloadQueue.then((_) => _downloadSong(songId, song: song, onProgress: onProgress));
    _activeDownloads[songId] = job;
    _downloadQueue = job;
    job.whenComplete(() => _activeDownloads.remove(songId));
    return job;
  }

  Future<void> _downloadSong(String songId, {SongDetail? song, Function(double)? onProgress}) async {
    try {
      final details = song ?? await AppDatabase.getSong(songId);
      if (details == null) throw StateError('Song metadata is unavailable');
      if (song != null) await AppDatabase.saveSongDetail(song);
      await _activeCaches[songId];
      final offlineDir = await getOfflineDirectory();
      final cachedPath = _cachedSongs[songId];
      // Older YouTube caches used unvalidated HTTP responses with an .mp3 suffix.
      final canUseCache = cachedPath != null && (details.ytVideoId.isEmpty || !cachedPath.endsWith('.mp3'));
      String filePath;
      if (canUseCache && await File(cachedPath).exists() && await File(cachedPath).length() > 0) {
        final extension = cachedPath.split('.').last;
        filePath = '${offlineDir.path}/$songId.$extension';
        await File(cachedPath).copy(filePath);
      } else {
        var lastNotification = -10;
        filePath = await _downloadAudio(
          details,
          offlineDir,
          onProgress: (received, total) {
            final progress = received * 100.0 / total;
            updateProgress(songId, progress);
            onProgress?.call(progress);
            if (progress - lastNotification >= 10 || progress >= 100) {
              lastNotification = progress.toInt();
              showDownloadNotification(details.title, progress).catchError((Object e) {
                Logger.error('OfflineManager', 'Download notification failed: $e');
              });
            }
          },
        );
      }
      _offlineSongs[songId] = filePath;
      await _save();
      _notifyDownloadedSongsChanged();
      updateProgress(songId, 100);
      onProgress?.call(100);
      updateStatus(songId, DownloadStatus.completed);
      cancelDownloadNotification().catchError((Object e) {
        Logger.error('OfflineManager', 'Download notification failed: $e');
      });
    } catch (e) {
      _offlineSongs.remove(songId);
      updateStatus(songId, DownloadStatus.failed);
      updateProgress(songId, 0);
      Logger.error('OfflineManager', 'Download failed for $songId: $e');
      cancelDownloadNotification().catchError((Object error) {
        Logger.error('OfflineManager', 'Download notification failed: $error');
      });
    }
  }

  Future<String> _downloadAudio(SongDetail song, Directory directory, {void Function(int, int)? onProgress}) async {
    final videoId = song.ytVideoId;
    final AudioDownloadSource? source;
    if (videoId.isNotEmpty) {
      source = await youtube.resolveDownloadSource(videoId);
      if (source == null) throw StateError('Unable to resolve audio');
    } else {
      source = null;
      if (song.downloadUrls.isEmpty) {
        throw StateError('No audio source available');
      }
    }
    final extension = source?.extension ?? 'mp3';
    final filePath = '${directory.path}/${song.id}.$extension';
    final part = File('$filePath.part');
    try {
      if (source != null) {
        await ChunkDownloader(dio: youtube.mediaDio, userAgent: visionosUserAgent).download(
          source: source,
          destination: part,
          refresh: (itag) => youtube.resolveDownloadSource(videoId, preferredItag: itag),
          onProgress: onProgress,
        );
      } else {
        final dio = Dio(
          BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 45)),
        );
        try {
          await dio.download(
            song.downloadUrls.last.url,
            part.path,
            onReceiveProgress: (received, total) {
              if (total > 0) onProgress?.call(received, total);
            },
          );
        } finally {
          dio.close();
        }
      }
      if (!await part.exists() || await part.length() == 0) {
        throw StateError('Downloaded file is empty');
      }
      await part.rename(filePath);
      return filePath;
    } catch (_) {
      if (await part.exists()) await part.delete();
      rethrow;
    }
  }

  /// Delete song
  Future<void> deleteSong(String songId) async {
    final path = _offlineSongs[songId];
    if (path != null && File(path).existsSync()) {
      await File(path).delete();
    }
    final wasDownloaded = _offlineSongs.remove(songId) != null;
    if (wasDownloaded) _notifyDownloadedSongsChanged();

    // Update notifiers to reflect deletion
    updateStatus(songId, DownloadStatus.idle);
    updateProgress(songId, 0.0);

    // Update all sets containing this song
    _setDownloadedCounts.forEach((setId, countNotifier) {
      final count = countNotifier.value;
      if (count > 0) {
        countNotifier.value = (count - 1).clamp(0, count);
      }
    });

    _setStatusNotifiers.forEach((setId, statusNotifier) {
      statusNotifier.value = DownloadStatus.idle;
    });

    await _save();
  }

  /// Quick check if a song or album is downloaded
  bool isAvailableOffline({String? songId, String? albumId}) {
    if (songId != null) {
      return _offlineSongs.containsKey(songId) || _cachedSongs.containsKey(songId);
    }
    if (albumId != null) return _downloadedAlbums.contains(albumId);
    return false;
  }

  /// Quick getter for download status
  DownloadStatus getDownloadStatusQuick({String? songId, String? albumId}) {
    if (songId != null) return getDownloadStatus(songId);
    if (albumId != null) {
      return _downloadedAlbums.contains(albumId) ? DownloadStatus.completed : DownloadStatus.idle;
    }
    return DownloadStatus.idle;
  }

  Future<List<SongDetail>> getDownloadedSongs() async {
    return AppDatabase.getSongs(_offlineSongs.keys.toList());
  }

  List<String> getAllSongIds() => _offlineSongs.keys.toList();

  Future<void> downloadSongsSet(Set<String> songIds, {Function(String songId, double progress)? onProgress}) async {
    for (final songId in songIds) {
      await downloadSong(
        songId,
        onProgress: (progress) {
          if (onProgress != null) onProgress(songId, progress);
        },
      );
    }
  }

  Future<void> downloadSongsSetWithStatus(
    String setId,
    Set<String> songIds, {
    List<SongDetail> songs = const [],
    Function(String songId, double progress)? onProgress,
  }) async {
    final statusNotifier = songsSetStatusNotifier(setId);
    final countNotifier = songsSetDownloadedCountNotifier(setId);

    statusNotifier.value = DownloadStatus.downloading;
    countNotifier.value = 0;

    int completedCount = 0;
    final songsById = {for (final song in songs) song.id: song};

    for (final songId in songIds) {
      await downloadSong(
        songId,
        song: songsById[songId],
        onProgress: (progress) {
          if (onProgress != null) onProgress(songId, progress);
        },
      );
      if (getDownloadStatus(songId) == DownloadStatus.completed) {
        completedCount++;
      }
      countNotifier.value = completedCount;
    }

    final allDownloaded =
        songIds.isNotEmpty && songIds.every((id) => getDownloadStatus(id) == DownloadStatus.completed);

    statusNotifier.value = allDownloaded ? DownloadStatus.completed : DownloadStatus.idle;

    if (allDownloaded) {
      await showSimpleNotification("Playlist Downloaded", "All ${songIds.length} songs are available offline 🎶");
    }
  }

  Future<void> deleteSongsSet(String setId, Set<String> songIds) async {
    info('Clearing Offline songs caches under progress', Severity.success);
    for (final songId in songIds) {
      await deleteSong(songId);
    }
    songsSetStatusNotifier(setId).value = DownloadStatus.idle;
    songsSetDownloadedCountNotifier(setId).value = 0;
  }

  Future<void> deleteAllSongs() async {
    final offlineDir = await getOfflineDirectory();
    if (offlineDir.existsSync()) {
      await offlineDir.delete(recursive: true);
    }
    _offlineSongs.clear();
    _notifyDownloadedSongsChanged();
    _cachedSongs.clear();
    downloadStatus.clear();
    downloadProgress.clear();
    _progressNotifiers.clear();
    _statusNotifiers.clear();
    await _save();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString(_offlineKey, jsonEncode(_offlineSongs));
    prefs.setString(_cacheKey, jsonEncode(_cachedSongs));
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

  DownloadStatus getSongDownloadStatus(String songId) => getDownloadStatus(songId);

  Future<void> requestSongDownload(String songId, {SongDetail? song, Function(double)? onProgress}) async {
    await downloadSong(songId, song: song, onProgress: onProgress);
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
      _notifyDownloadedSongsChanged();
      Logger.log('OfflineManager', "🧹 Cleaned ${removed.length} invalid offline songs");
    } else {
      Logger.log('OfflineManager', "🧹 No invalid downloads found");
    }
  }

  // 🔹 Album Download Status Handling
  bool isAlbumDownloaded(String albumId) => _downloadedAlbums.contains(albumId);

  void markAlbumAsDownloaded(String albumId) {
    _downloadedAlbums.add(albumId);
    albumStatusNotifier(albumId).value = DownloadStatus.completed;
    _save();
    Logger.success('OfflineManager', "✅ Album $albumId marked as fully downloaded");
  }

  void unmarkAlbum(String albumId) {
    _downloadedAlbums.remove(albumId);
    albumStatusNotifier(albumId).value = DownloadStatus.idle;
    _save();
    Logger.error('OfflineManager', "❌ Album $albumId unmarked (not fully downloaded)");
  }

  List<String> getAllDownloadedAlbums() => _downloadedAlbums.toList();

  bool isSongDownloaded(String songId) {
    return _offlineSongs.containsKey(songId);
  }

  Future<void> downloadAlbumSongs(Album album, {Function(String songId, double progress)? onProgress}) async {
    final songIds = album.songIds.isNotEmpty ? album.songIds : album.songs.map((s) => s.id).toList();

    albumStatusNotifier(album.id).value = DownloadStatus.downloading;
    albumDownloadedCountNotifier(album.id).value = 0;

    int completedCount = 0;
    final songsById = {for (final song in album.songs) song.id: song};

    for (final songId in songIds) {
      await downloadSong(
        songId,
        song: songsById[songId],
        onProgress: (progress) {
          if (onProgress != null) onProgress(songId, progress);
        },
      );

      if (getDownloadStatus(songId) == DownloadStatus.completed) {
        completedCount++;
      }
      albumDownloadedCountNotifier(album.id).value = completedCount;
    }

    // Check if all songs are downloaded successfully
    final allDownloaded =
        songIds.isNotEmpty && songIds.every((id) => getDownloadStatus(id) == DownloadStatus.completed);

    if (allDownloaded) {
      markAlbumAsDownloaded(album.id);
      await showSimpleNotification("Album Downloaded", "\"${album.title}\" is now available offline 🎶");
    } else {
      unmarkAlbum(album.id);
    }
  }

  int getDownloadedCountForAlbum(Album album) {
    final songIds = album.songIds.isNotEmpty ? album.songIds : album.songs.map((s) => s.id).toList();
    return songIds.where((id) => getDownloadStatus(id) == DownloadStatus.completed).length;
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
      _albumStatusNotifiers[albumId] = ValueNotifier<DownloadStatus>(DownloadStatus.idle);
    }
    return _albumStatusNotifiers[albumId]!;
  }

  Future<void> deleteAlbumById(String albumId) async {
    info('Album songs cache clearing under progress...', Severity.success);
    final album = await youtube.fetchAlbumById(albumId: albumId);
    if (album != null && album.songs.isNotEmpty) {
      // Fetch full song details if needed
      final albumSongs = await youtube.getSongDetails(ids: album.songs.map((s) => s.id).toList());

      // Delete all songs in the album
      for (final song in albumSongs) {
        await deleteSong(song.id);
      }
    }

    // Unmark the album in memory and UI
    unmarkAlbum(albumId);

    // Persist changes
    await _save();
  }

  /// Returns total storage used by offline songs in bytes
  Future<double> getOfflineStorageUsed() async {
    double totalBytes = 0;
    for (final path in _offlineSongs.values) {
      final file = File(path);
      if (file.existsSync()) {
        totalBytes += file.lengthSync();
      }
    }
    for (final path in _cachedSongs.values) {
      final file = File(path);
      if (file.existsSync()) {
        totalBytes += file.lengthSync();
      }
    }
    return totalBytes;
  }

  /// Optional helper: return in human-readable format
  Future<String> getOfflineStorageUsedFormatted() async {
    final bytes = await getOfflineStorageUsed();
    const kb = 1024;
    const mb = 1024 * kb;
    const gb = 1024 * mb;

    if (bytes >= gb) return "${(bytes / gb).toStringAsFixed(2)} GB";
    if (bytes >= mb) return "${(bytes / mb).toStringAsFixed(2)} MB";
    if (bytes >= kb) return "${(bytes / kb).toStringAsFixed(2)} KB";
    return "$bytes B";
  }
}
