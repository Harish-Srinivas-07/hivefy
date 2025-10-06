import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    if (stored != null) {
      final decoded = jsonDecode(stored);
      if (decoded is Map<String, dynamic>) {
        _cache = decoded;
      } else {
        _cache = {};
      }
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
    notifyChanges();

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

  static final StreamController<void> _changes = StreamController.broadcast();

  static Stream<void> get changes => _changes.stream;

  static void notifyChanges() => _changes.add(null);
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
  static const _usageKey = 'artist_usage';
  static final ArtistCache _instance = ArtistCache._internal();
  factory ArtistCache() => _instance;
  ArtistCache._internal();

  final Map<String, ArtistDetails> _cache = {};
  final Map<String, int> _usageCount = {};
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

    final usageStored = _prefs.getString(_usageKey);
    if (usageStored != null) {
      final Map<String, dynamic> usageDecoded = jsonDecode(usageStored);
      usageDecoded.forEach((key, value) {
        _usageCount[key] = value;
      });
    }

    _initialized = true;
  }

  Future<ArtistDetails?> get(String artistId) async {
    await _init();
    _incrementUsage(artistId);
    return _cache[artistId];
  }

  Future<void> set(String artistId, ArtistDetails details) async {
    await _init();
    _cache[artistId] = details;
    await _saveToPrefs();
    notifyArtistChanges();
  }

  Future<List<ArtistDetails>> getAll({bool sortByUsage = false}) async {
    await _init();
    final list = _cache.values.toList();
    if (sortByUsage) {
      list.sort((a, b) {
        final usageA = _usageCount[a.id] ?? 0;
        final usageB = _usageCount[b.id] ?? 0;
        return usageB.compareTo(usageA);
      });
    }
    return list;
  }

  Future<void> clear() async {
    await _init();
    _cache.clear();
    _usageCount.clear();
    await _prefs.remove(_prefsKey);
    await _prefs.remove(_usageKey);
  }

  Future<void> _saveToPrefs() async {
    final Map<String, dynamic> toStore = {};
    _cache.forEach((key, value) {
      toStore[key] = ArtistDetails.artistDetailsToJson(value);
    });
    await _prefs.setString(_prefsKey, jsonEncode(toStore));
    await _prefs.setString(_usageKey, jsonEncode(_usageCount));
  }

  Timer? _saveTimer;

  void _incrementUsage(String artistId) {
    _usageCount[artistId] = (_usageCount[artistId] ?? 0) + 1;
    debugPrint(
      "Artist usage incremented: $artistId → ${_usageCount[artistId]}",
    );
    _saveTimer?.cancel();
    _saveTimer = Timer(Duration(seconds: 1), _saveToPrefs);
  }

  static final StreamController<void> _artistChanges =
      StreamController.broadcast();
  static Stream<void> get artistChanges => _artistChanges.stream;
  static void notifyArtistChanges() => _artistChanges.add(null);
}

// Album cache with persistence
class AlbumCache {
  static const _prefsKey = 'album_cache';
  static const _usageKey = 'album_usage';
  static final AlbumCache _instance = AlbumCache._internal();
  factory AlbumCache() => _instance;
  AlbumCache._internal();

  final Map<String, Album> _cache = {};
  final Map<String, int> _usageCount = {}; // track usage
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

    final usageStored = _prefs.getString(_usageKey);
    if (usageStored != null) {
      final Map<String, dynamic> usageDecoded = jsonDecode(usageStored);
      usageDecoded.forEach((key, value) {
        _usageCount[key] = value;
      });
    }

    _initialized = true;
  }

  Future<Album?> get(String albumId) async {
    await _init();
    _incrementUsage(albumId);
    return _cache[albumId];
  }

  Future<void> set(String albumId, Album album) async {
    await _init();
    _cache[albumId] = album;
    await _saveToPrefs();
    notifyAlbumChanges();
  }

  Future<List<Album>> getAll({bool sortByUsage = false}) async {
    await _init();
    final list = _cache.values.toList();
    if (sortByUsage) {
      list.sort((a, b) {
        final usageA = _usageCount[a.id] ?? 0;
        final usageB = _usageCount[b.id] ?? 0;
        return usageB.compareTo(usageA); // most used first
      });
    }
    return list;
  }

  Future<void> clear() async {
    await _init();
    _cache.clear();
    _usageCount.clear();
    await _prefs.remove(_prefsKey);
    await _prefs.remove(_usageKey);
  }

  Future<void> _saveToPrefs() async {
    final Map<String, dynamic> toStore = {};
    _cache.forEach((key, value) {
      toStore[key] = Album.albumToJson(value);
    });
    await _prefs.setString(_prefsKey, jsonEncode(toStore));
    await _prefs.setString(_usageKey, jsonEncode(_usageCount));
  }

  Timer? _saveTimer;

  void _incrementUsage(String albumId) {
    _usageCount[albumId] = (_usageCount[albumId] ?? 0) + 1;
    debugPrint("Album usage incremented: $albumId → ${_usageCount[albumId]}");
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 1), () async {
      await _saveToPrefs();
    });
  }

  static final StreamController<void> _albumChanges =
      StreamController.broadcast();
  static Stream<void> get albumChanges => _albumChanges.stream;
  static void notifyAlbumChanges() => _albumChanges.add(null);
}

// ---------------- SEARCH HISTORY ----------------
List<String> searchHistory = [];

Future<void> loadSearchHistory() async {
  final prefs = await SharedPreferences.getInstance();
  searchHistory = prefs.getStringList('search_history') ?? [];
}

Future<void> saveSearchTerm(String term) async {
  term = term.trim();
  if (term.isEmpty) return;

  // remove duplicate if already exists
  searchHistory.remove(term);
  searchHistory.insert(0, term); // put latest at front

  // keep max 5
  if (searchHistory.length > 5) {
    searchHistory = searchHistory.sublist(0, 5);
  }

  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList('search_history', searchHistory);
}

// ---------------- LAST SONGS ----------------
Future<List<SongDetail>> loadLastSongs() async {
  final prefs = await SharedPreferences.getInstance();
  final songsJson = prefs.getStringList('last_songs') ?? [];
  return songsJson.map((s) => SongDetail.fromJson(jsonDecode(s))).toList();
}

Future<void> storeLastSongs(List<SongDetail> newSongs) async {
  final prefs = await SharedPreferences.getInstance();
  final existing = await loadLastSongs();

  final updated =
      [
        ...newSongs,
        ...existing.where((e) => !newSongs.any((n) => n.id == e.id)),
      ].take(5).toList(); // keep only 5

  final songsJson =
      updated.map((s) => jsonEncode(SongDetail.songDetailToJson(s))).toList();
  await prefs.setStringList('last_songs', songsJson);
}

// ---------------- LAST ALBUMS ----------------
Future<List<Album>> loadLastAlbums() async {
  final prefs = await SharedPreferences.getInstance();
  final albumsJson = prefs.getStringList('last_albums') ?? [];
  return albumsJson.map((a) => Album.fromJson(jsonDecode(a))).toList();
}

Future<void> storeLastAlbums(List<Album> newAlbums) async {
  final prefs = await SharedPreferences.getInstance();
  final existing = await loadLastAlbums();

  final updated =
      [
        ...newAlbums,
        ...existing.where((e) => !newAlbums.any((n) => n.id == e.id)),
      ].take(5).toList();

  final albumsJson =
      updated.map((a) => jsonEncode(Album.albumToJson(a))).toList();
  await prefs.setStringList('last_albums', albumsJson);
}

// ---------------- REMOVE LAST SONG ----------------
Future<void> removeLastSong(String songId) async {
  final prefs = await SharedPreferences.getInstance();
  final existing = await loadLastSongs();

  final updated = existing.where((s) => s.id != songId).toList();

  final songsJson =
      updated.map((s) => jsonEncode(SongDetail.songDetailToJson(s))).toList();
  await prefs.setStringList('last_songs', songsJson);
}

// ---------------- REMOVE LAST ALBUM ----------------
Future<void> removeLastAlbum(String albumId) async {
  final prefs = await SharedPreferences.getInstance();
  final existing = await loadLastAlbums();

  final updated = existing.where((a) => a.id != albumId).toList();

  final albumsJson =
      updated.map((a) => jsonEncode(Album.albumToJson(a))).toList();
  await prefs.setStringList('last_albums', albumsJson);
}

// ---------------- ALL SONGS PROVIDER -------------------
final allSongsProvider =
    StateNotifierProvider<AllSongsNotifier, List<SongDetail>>((ref) {
      final notifier = AllSongsNotifier();
      final sub = AppDatabase.changes.listen((_) {
        notifier.refresh();
      });
      ref.onDispose(sub.cancel);
      return notifier;
    });

class AllSongsNotifier extends StateNotifier<List<SongDetail>> {
  AllSongsNotifier() : super([]) {
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    state = await AppDatabase.getAllSongs();
  }

  Future<void> refresh() async {
    await _loadSongs();
  }
}

// ---------------- ARTIST CACHE PROVIDER ------------------
final allArtistsProvider =
    StateNotifierProvider<ArtistsNotifier, List<ArtistDetails>>((ref) {
      final notifier = ArtistsNotifier();
      final sub = ArtistCache.artistChanges.listen((_) {
        notifier.refresh();
      });
      ref.onDispose(sub.cancel);
      return notifier;
    });

class ArtistsNotifier extends StateNotifier<List<ArtistDetails>> {
  ArtistsNotifier() : super([]) {
    _loadArtists();
  }
  Future<void> _loadArtists() async {
    state = await ArtistCache().getAll();
  }

  Future<void> refresh() async {
    await _loadArtists();
  }
}

// ----------------- ALBUM CACHE PROVIDER -------------------

final allAlbumsProvider = StateNotifierProvider<AlbumsNotifier, List<Album>>((
  ref,
) {
  final notifier = AlbumsNotifier();
  final sub = AlbumCache.albumChanges.listen((_) {
    notifier.refresh();
  });
  ref.onDispose(sub.cancel);
  return notifier;
});

class AlbumsNotifier extends StateNotifier<List<Album>> {
  AlbumsNotifier() : super([]) {
    _loadAlbums();
  }
  Future<void> _loadAlbums() async {
    state = await AlbumCache().getAll();
  }

  Future<void> refresh() async {
    await _loadAlbums();
  }
}

// ---------------- FREQUENT ARTISTS PROVIDER ------------------
final frequentArtistsProvider =
    StateNotifierProvider<FrequentArtistsNotifier, List<ArtistDetails>>((ref) {
      final notifier = FrequentArtistsNotifier();
      final sub = ArtistCache.artistChanges.listen((_) {
        notifier.refresh();
      });
      ref.onDispose(sub.cancel);
      return notifier;
    });

class FrequentArtistsNotifier extends StateNotifier<List<ArtistDetails>> {
  FrequentArtistsNotifier() : super([]) {
    _loadFrequentArtists();
  }

  Future<void> _loadFrequentArtists() async {
    state = await ArtistCache().getAll(sortByUsage: true);
  }

  Future<void> refresh() async {
    await _loadFrequentArtists();
  }
}

// ---------------- FREQUENT ALBUMS PROVIDER ------------------
final frequentAlbumsProvider =
    StateNotifierProvider<FrequentAlbumsNotifier, List<Album>>((ref) {
      final notifier = FrequentAlbumsNotifier();
      final sub = AlbumCache.albumChanges.listen((_) {
        notifier.refresh();
      });
      ref.onDispose(sub.cancel);
      return notifier;
    });

class FrequentAlbumsNotifier extends StateNotifier<List<Album>> {
  FrequentAlbumsNotifier() : super([]) {
    _loadFrequentAlbums();
  }

  Future<void> _loadFrequentAlbums() async {
    state = await AlbumCache().getAll(sortByUsage: true);
  }

  Future<void> refresh() async {
    await _loadFrequentAlbums();
  }
}
