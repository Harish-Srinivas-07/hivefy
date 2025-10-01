import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'datamodel.dart';

class AppDatabase {
  static const _songKey = 'songsDb';
  static Map<String, dynamic> _cache = {};
  static bool _initialized = false;
  static late SharedPreferences _prefs;

  // -------------------- INIT --------------------
  static Future<void> _init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();

    final stored = _prefs.getString(_songKey);
    try {
      _cache = stored != null ? jsonDecode(stored) : {};
    } catch (_) {
      _cache = {};
    }

    _initialized = true;
  }

  // -------------------- SONG STORAGE --------------------
  static Future<SongDetail> saveSongDetail(SongDetail song) async {
    await _init();

    // Convert the song to JSON
    Map<String, dynamic> newJson = SongDetail.songDetailToJson(song);

    // Check if the song has download URLs
    final newDownloadUrls = (newJson['downloadUrl'] as List?) ?? [];
    if (newDownloadUrls.isEmpty) {
      debugPrint(
        "--- Song '${song.title}' has no download URLs, removing from cache",
      );
      _cache.remove(song.id);
      await _prefs.setString(_songKey, jsonEncode(_cache));
      return song;
    }

    // Merge with existing cache if present
    if (_cache.containsKey(song.id)) {
      final oldJson = Map<String, dynamic>.from(_cache[song.id]);

      for (final key in newJson.keys) {
        final newValue = newJson[key];

        // Skip null or empty values
        if (newValue == null) continue;
        if (newValue is String && newValue.isEmpty) continue;
        if (newValue is List && newValue.isEmpty) continue;
        if (newValue is Map && newValue.isEmpty) continue;

        oldJson[key] = newValue;
      }

      _cache[song.id] = oldJson;
    } else {
      _cache[song.id] = newJson;
    }

    // Save the updated cache to SharedPreferences
    await _prefs.setString(_songKey, jsonEncode(_cache));

    debugPrint("--- Song '${song.title}' saved to cache successfully");

    // Return the stored song
    return SongDetail.fromJson(Map<String, dynamic>.from(_cache[song.id]));
  }

  /// Lightweight save for a Song (wrap into SongDetail)
  static Future<SongDetail> saveSong(Song song) async {
    final detail = SongDetail(
      id: song.id,
      title: song.title,
      type: song.type,
      url: song.url,
      images: song.images,
      description: song.description,
      language: song.language,
      album: song.album,
      primaryArtists: song.primaryArtists,
      singers: song.singers,
    );
    return saveSongDetail(detail);
  }

  static Future<SongDetail?> getSong(String id) async {
    await _init();
    if (!_cache.containsKey(id)) return null;
    return SongDetail.fromJson(Map<String, dynamic>.from(_cache[id]));
  }

  /// ✅ NEW: Batch lookup to reduce multiple DB hits
  static Future<List<SongDetail>> getSongs(List<String> ids) async {
    await _init();
    final List<SongDetail> results = [];

    for (final id in ids) {
      if (_cache.containsKey(id)) {
        results.add(SongDetail.fromJson(Map<String, dynamic>.from(_cache[id])));
      }
    }
    return results;
  }

  static Future<List<SongDetail>> getAllSongs() async {
    await _init();
    return _cache.values
        .map((e) => SongDetail.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  static Future<void> removeSong(String id) async {
    await _init();
    _cache.remove(id);
    await _prefs.setString(_songKey, jsonEncode(_cache));
  }

  static Future<void> clearSongs() async {
    await _init();
    _cache.clear();
    await _prefs.remove(_songKey);
  }
}

// Artists
class ArtistDB {
  // -------------------- ARTIST STORAGE --------------------
  static const Map<String, String> knownArtists = {
    "455663": "Anirudh Ravichander",
    "455662": "Dhanush",
    "773021": "Hiphop Tamizha",
    "455454": "G.V. Prakash Kumar",
    "594484": "Sam C.S.",
    "456269": "A.R. Rahman",
    "455170": "Devi Sri Prasad",
    "476818": "Silambarasan TR",
    "544471": "Thaman S",
    "455240": "Karthik",
    "471083": "Leon James",
    "456164": "Vijay Antony",
    "603814": "Sabrina Carpenter",
    "14477737": "Sai Abhyankkar",
  };

  /// Helper to get artist name from id
  static String? getArtistName(String id) {
    return knownArtists[id];
  }

  /// Helper to get artist id from name (reverse lookup)
  static String? getArtistId(String name) {
    return knownArtists.entries
            .firstWhere(
              (e) => e.value.toLowerCase() == name.toLowerCase(),
              orElse: () => const MapEntry("", ""),
            )
            .key
            .isNotEmpty
        ? knownArtists.entries
            .firstWhere((e) => e.value.toLowerCase() == name.toLowerCase())
            .key
        : null;
  }
}

// Playlists
class PlaylistDB {
  static const List<Map<String, String>> playlists = [
    {"id": "1170578779", "name": "Tamil 1990s"},
    {"id": "1170578783", "name": "Tamil 2000s"},
    {"id": "901538755", "name": "Tamil 1980s"},
    {"id": "1170578788", "name": "Tamil 2010s"},
    {"id": "901538753", "name": "Tamil 1970s"},
    {"id": "901538752", "name": "Tamil 1960s"},
    {"id": "1133105280", "name": "Tamil Hit Songs"},
    {"id": "1134651042", "name": "Tamil: India Superhits Top 50"},
    {"id": "1074590003", "name": "Tamil BGM"},
    {"id": "804092154", "name": "Sad Love - Tamil"},

    // 2025 Featured Playlists
    {"id": "1265148713", "name": "Chartbusters 2025 - Tamil"},
    {"id": "1265148693", "name": "Dance Hits 2025 - Tamil"},
    {"id": "1265148559", "name": "Romantic Hits 2025 - Tamil"},
    {"id": "1265167757", "name": "Movie Theme 2025 - Tamil"},
    {"id": "1265148483", "name": "Pop Hits 2025 - Tamil"},
  ];

  /// Quick lookup by ID
  static String? getPlaylistName(String id) {
    return playlists.firstWhere((p) => p["id"] == id, orElse: () => {})["name"];
  }

  /// Quick lookup by name
  static String? getPlaylistId(String name) {
    return playlists.firstWhere(
      (p) => p["name"]?.toLowerCase() == name.toLowerCase(),
      orElse: () => {},
    )["id"];
  }
}

// Artist cache with persistence
class ArtistCache {
  static const _prefsKey = 'artist_cache';
  static final ArtistCache _instance = ArtistCache._internal();
  factory ArtistCache() => _instance;
  ArtistCache._internal();

  final Map<String, ArtistDetails> _cache = {};
  bool _initialized = false;
  late SharedPreferences _prefs;

  Future<void> _init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    final stored = _prefs.getString(_prefsKey);
    if (stored != null) {
      final Map<String, dynamic> decoded = jsonDecode(stored);
      decoded.forEach((key, value) {
        _cache[key] = ArtistDetails.fromJson(Map<String, dynamic>.from(value));
      });
    }
    _initialized = true;
  }

  Future<ArtistDetails?> get(String artistId) async {
    await _init();
    return _cache[artistId];
  }

  Future<void> set(String artistId, ArtistDetails details) async {
    await _init();
    _cache[artistId] = details;
    await _saveToPrefs();
  }

  Future<List<ArtistDetails>> getAll() async {
    await _init();
    return _cache.values.toList();
  }

  Future<void> clear() async {
    await _init();
    _cache.clear();
    await _prefs.remove(_prefsKey);
  }

  Future<void> _saveToPrefs() async {
    final Map<String, dynamic> toStore = {};
    _cache.forEach((key, value) {
      toStore[key] = ArtistDetails.artistDetailsToJson(value);
    });
    await _prefs.setString(_prefsKey, jsonEncode(toStore));
  }
}

// Album cache with persistence
class AlbumCache {
  static const _prefsKey = 'album_cache';
  static final AlbumCache _instance = AlbumCache._internal();
  factory AlbumCache() => _instance;
  AlbumCache._internal();

  final Map<String, Album> _cache = {};
  bool _initialized = false;
  late SharedPreferences _prefs;

  Future<void> _init() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    final stored = _prefs.getString(_prefsKey);
    if (stored != null) {
      final Map<String, dynamic> decoded = jsonDecode(stored);
      decoded.forEach((key, value) {
        _cache[key] = Album.fromJson(Map<String, dynamic>.from(value));
      });
    }
    _initialized = true;
  }

  Future<Album?> get(String albumId) async {
    await _init();
    return _cache[albumId];
  }

  Future<void> set(String albumId, Album album) async {
    await _init();
    _cache[albumId] = album;
    await _saveToPrefs();
  }

  Future<List<Album>> getAll() async {
    await _init();
    return _cache.values.toList();
  }

  Future<void> clear() async {
    await _init();
    _cache.clear();
    await _prefs.remove(_prefsKey);
  }

  Future<void> _saveToPrefs() async {
    final Map<String, dynamic> toStore = {};
    _cache.forEach((key, value) {
      toStore[key] = Album.albumToJson(value);
    });
    await _prefs.setString(_prefsKey, jsonEncode(toStore));
  }
}
