import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/datamodel.dart';
import 'youtube.dart';

/// Language-based recommendations from YouTube Music.
class LatestMusicFetcher {
  static const _cacheDuration = Duration(hours: 6);

  static Future<List<Playlist>> getLatestPlaylists(
    String lang, {
    int playlistLimit = 30,
    int perPlaylistSongCount = 50,
    YoutubeAPI? api,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'yt_recommendations_v1_${lang}_playlists';
    final cached = _readCache(
      prefs,
      key,
      Playlist.fromJson,
    ).where((p) => p.id.startsWith('VL') && p.title.isNotEmpty).toList();
    if (_isFresh(prefs, key) && cached.isNotEmpty) {
      return cached.take(playlistLimit).toList();
    }
    SearchPlaylistsResponse? response;
    try {
      response = await (api ?? youtube).searchPlaylists(query: '$lang music', limit: playlistLimit);
    } catch (_) {
      return cached.take(playlistLimit).toList();
    }
    final results = (response?.results ?? <Playlist>[])
        .where((p) => p.id.startsWith('VL') && p.title.isNotEmpty)
        .toList();
    if (results.isNotEmpty) {
      await _writeCache(prefs, key, results.map(Playlist.playlistToJson).toList());
      return results;
    }
    return cached.take(playlistLimit).toList();
  }

  static Future<List<Album>> getLatestAlbums(
    String lang, {
    int albumLimit = 30,
    int perAlbumSongCount = 50,
    YoutubeAPI? api,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'yt_recommendations_v1_${lang}_albums';
    final cached = _readCache(
      prefs,
      key,
      Album.fromJson,
    ).where((a) => a.id.startsWith('MPREb_') && a.title.isNotEmpty).toList();
    if (_isFresh(prefs, key) && cached.isNotEmpty) {
      return cached.take(albumLimit).toList();
    }
    List<Album> results;
    try {
      results = (await (api ?? youtube).searchAlbums(
        query: '$lang music',
        limit: albumLimit,
      )).where((a) => a.id.startsWith('MPREb_') && a.title.isNotEmpty).toList();
    } catch (_) {
      return cached.take(albumLimit).toList();
    }
    if (results.isNotEmpty) {
      await _writeCache(prefs, key, results.map(Album.albumToJson).toList());
      return results;
    }
    return cached.take(albumLimit).toList();
  }

  static bool _isFresh(SharedPreferences prefs, String key) {
    final timestamp = prefs.getInt('${key}_time');
    if (timestamp == null) return false;
    final age = DateTime.now().millisecondsSinceEpoch - timestamp;
    return age >= 0 && age < _cacheDuration.inMilliseconds;
  }

  static List<T> _readCache<T>(SharedPreferences prefs, String key, T Function(Map<String, dynamic>) parse) {
    try {
      final raw = prefs.getString(key);
      if (raw == null) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.whereType<Map>().map((item) => parse(Map<String, dynamic>.from(item))).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _writeCache(SharedPreferences prefs, String key, List<Map<String, dynamic>> values) async {
    await prefs.setString(key, jsonEncode(values));
    await prefs.setInt('${key}_time', DateTime.now().millisecondsSinceEpoch);
  }
}
