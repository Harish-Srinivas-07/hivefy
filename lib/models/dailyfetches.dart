// daily_bootstrap.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/jiosaavn.dart';
import 'database.dart';
import 'datamodel.dart';

class Dailyfetches {
  static const _artistsKey = 'daily_cache_artists_v1';
  static const _artistsTsKey = 'daily_cache_artists_ts_v1';
  static const _plKey = 'daily_cache_playlists_v1';
  static const _plTsKey = 'daily_cache_playlists_ts_v1';

  static SharedPreferences? _prefs;
  static bool _initing = false;

  // -------- Public API

  /// Refresh both artists + playlists once per day (unless force=true).
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

  /// Fetch & cache ArtistDetails by id (once per day unless force=true).
  /// Returns the cached map after refresh.
  static Future<Map<String, ArtistDetails>> refreshArtistsDaily({
    bool force = false,
    List<String>? artistIds,
  }) async {
    await _init();
    final stale = force || _isStale(_prefs!.getString(_artistsTsKey));
    if (!stale) return getArtistsFromCache();

    final ids = (artistIds ?? ArtistDB.knownArtists.keys.toList())
        .where((e) => e.isNotEmpty)
        .toList();

    // Fetch in parallel
    final results = await Future.wait(
      ids.map((id) => saavn.fetchArtistDetailsById(artistId: id)),
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

  /// Fetch & cache Playlists by id (once per day unless force=true).
  /// Returns the cached list after refresh.
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
            .toList());

    final results = await Future.wait(
      ids.map(
        (id) => saavn.fetchPlaylistById(
          playlistId: id,
          page: 0,
          limit: playlistLimitPerFetch,
        ),
      ),
    );

    final listJson = <dynamic>[];
    for (final p in results) {
      if (p == null) continue;
      listJson.add(Playlist.playlistToJson(p));
    }

    await _prefs!.setString(_plKey, jsonEncode(listJson));
    await _prefs!.setString(_plTsKey, DateTime.now().toIso8601String());

    return getPlaylistsFromCache();
  }

  // -------- Read from cache

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

  /// Optional helpers if you want different shapes
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

  // -------- Internals

  static Future<void> _init() async {
    if (_prefs != null || _initing) return;
    _initing = true;
    _prefs = await SharedPreferences.getInstance();
    _initing = false;
  }

  static bool _isStale(String? tsIso) {
    if (tsIso == null) return true;
    try {
      final then = DateTime.parse(tsIso).toLocal();
      final now = DateTime.now();
      final differentDay =
          then.year != now.year ||
          then.month != now.month ||
          then.day != now.day;
      final olderThan24h = now.difference(then) > const Duration(hours: 24);
      return differentDay || olderThan24h;
    } catch (_) {
      return true;
    }
  }
}
