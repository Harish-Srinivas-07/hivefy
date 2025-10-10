// daily_bootstrap.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'jiosaavn.dart';
import '../models/database.dart';
import '../models/datamodel.dart';

class DailyFetches {
  static const _artistsKey = 'daily_cache_artists_v1';
  static const _artistsTsKey = 'daily_cache_artists_ts_v1';
  static const _plKey = 'daily_cache_playlists_v1';
  static const _plTsKey = 'daily_cache_playlists_ts_v1';

  static SharedPreferences? _prefs;
  static bool _initing = false;
  static const _dayDuration = Duration(hours: 24);

  // -------- Public API --------

  /// Refresh both artists + playlists once per day (unless [force] is true).
  static Future<void> refreshAllDaily({
    bool force = false,
    List<String>? artistIds,
    List<String>? playlistIds,
    int playlistLimitPerFetch = 30,
  }) async {
    await Future.wait([
      refreshArtistsDaily(force: force, artistIds: artistIds),
      refreshPlaylistsDaily(
        force: force,
        playlistIds: playlistIds,
        playlistLimitPerFetch: playlistLimitPerFetch,
      ),
    ]);
  }

  /// Fetch & cache ArtistDetails once per day (unless [force] is true).
  /// Returns the updated artist map.
  static Future<Map<String, ArtistDetails>> refreshArtistsDaily({
    bool force = false,
    List<String>? artistIds,
  }) async {
    await _init();
    final stale = force || _isStale(_prefs!.getString(_artistsTsKey));
    if (!stale) return getArtistsFromCache();

    final ids =
        (artistIds ?? ArtistDB.knownArtists.keys.toList())
            .where((e) => e.isNotEmpty)
            .toList();

    final results = await Future.wait(
      ids.map((id) async {
        try {
          return await saavn.fetchArtistDetailsById(artistId: id);
        } catch (e) {
          debugPrint('Artist fetch error for $id: $e');
          return null;
        }
      }),
    );

    final mapJson = <String, dynamic>{};
    for (final a in results) {
      if (a == null) continue;
      mapJson[a.id] = Artist.artistToJson(a);
    }

    await _prefs!.setString(_artistsKey, jsonEncode(mapJson));
    await _prefs!.setString(_artistsTsKey, DateTime.now().toIso8601String());

    return getArtistsFromCache();
  }

  /// Fetch & cache Playlists by id once per day (unless [force] is true).
  /// Returns the updated playlist list.
  static Future<List<Playlist>> refreshPlaylistsDaily({
    bool force = false,
    List<String>? playlistIds,
    int playlistLimitPerFetch = 30,
  }) async {
    await _init();
    final stale = force || _isStale(_prefs!.getString(_plTsKey));
    if (!stale) return getPlaylistsFromCache();

    final ids =
        (playlistIds ??
                PlaylistDB.playlists
                    .map((e) => e['id'] ?? '')
                    .where((e) => e.isNotEmpty)
                    .cast<String>()
                    .toList())
            .where((e) => e.isNotEmpty)
            .toList();

    final results = await Future.wait(
      ids.map((id) async {
        try {
          return await saavn.fetchPlaylistById(
            playlistId: id,
            page: 0,
            limit: playlistLimitPerFetch,
          );
        } catch (e) {
          debugPrint('Playlist fetch error for $id: $e');
          return null;
        }
      }),
    );

    final validPlaylists = results.whereType<Playlist>().toList();
    if (validPlaylists.isEmpty) return [];

    final jsonList =
        validPlaylists.map((p) => Playlist.playlistToJson(p)).toList();

    await _prefs!.setString(_plKey, jsonEncode(jsonList));
    await _prefs!.setString(_plTsKey, DateTime.now().toIso8601String());

    return validPlaylists;
  }

  // -------- Cache Readers --------

  static Future<Map<String, ArtistDetails>> getArtistsFromCache() async {
    await _init();
    final raw = _prefs!.getString(_artistsKey);
    if (raw == null || raw.isEmpty) return {};

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final map = <String, ArtistDetails>{};

    decoded.forEach((id, v) {
      try {
        map[id] = ArtistDetails.fromJson(Map<String, dynamic>.from(v));
      } catch (e) {
        debugPrint('ArtistDetails cache parse error for $id: $e');
      }
    });

    return map;
  }

  static Future<List<Playlist>> getPlaylistsFromCache() async {
    await _init();
    final raw = _prefs!.getString(_plKey);
    if (raw == null || raw.isEmpty) return [];

    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded
        .map((e) => Playlist.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<List<ArtistDetails>> getArtistsAsListFromCache() async {
    final map = await getArtistsFromCache();
    return map.values.toList();
  }

  static Future<void> clearCache() async {
    await _init();
    await _prefs!.remove(_artistsKey);
    await _prefs!.remove(_artistsTsKey);
    await _prefs!.remove(_plKey);
    await _prefs!.remove(_plTsKey);
  }

  // -------- Internals --------

  static Future<void> _init() async {
    if (_prefs != null) return;
    if (_initing) {
      while (_prefs == null) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return;
    }

    _initing = true;
    _prefs = await SharedPreferences.getInstance();
    _initing = false;
  }

  static bool _isStale(String? tsIso) {
    if (tsIso == null) return true;
    try {
      final then = DateTime.parse(tsIso);
      final now = DateTime.now();
      return now.difference(then) > _dayDuration;
    } catch (_) {
      return true;
    }
  }
}

// last played
class LastPlayedSongStorage {
  static const _key = 'last_played_song';

  /// Save song details as JSON
  static Future<void> save(SongDetail song) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = json.encode(SongDetail.songDetailToJson(song));
    await prefs.setString(_key, jsonStr);
  }

  /// Load last song from storage
  /// Returns null if the saved song is invalid or default
  static Future<SongDetail?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_key);
    if (jsonStr == null) return null;

    try {
      final map = json.decode(jsonStr) as Map<String, dynamic>;
      final song = SongDetail.fromJson(map);

      // Check if it's a placeholder/default song
      if (song.id.isEmpty) return null;

      return song;
    } catch (_) {
      return null;
    }
  }
}
