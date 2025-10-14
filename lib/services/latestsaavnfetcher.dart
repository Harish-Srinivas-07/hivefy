import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/datamodel.dart';
import 'jiosaavn.dart';

// AVAILABLE LANG : hindi, tamil, telugu, english, punjabi, marathi, gujarati, bengali, kannada, bhojpuri, malayalam, sanskrit, haryanvi, rajasthani, odia, assamese

class LatestSaavnFetcher {
  static const _baseUrl = 'https://www.jiosaavn.com';

  /// ---------------- PLAYLIST FETCHER ----------------
  static Future<List<Playlist>> getLatestPlaylists(
    String lang, {
    int playlistLimit = 30, // number of playlists to fetch
    int perPlaylistSongCount = 50, // number of songs per playlist
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = "latest_${lang}_playlists";
    final cacheTimeKey = "latest_${lang}_playlists_time";

    // Check cache validity (24h)
    const dayMs = 24 * 60 * 60 * 1000;
    final lastFetch = prefs.getInt(cacheTimeKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Try cache if still valid
    if (now - lastFetch < dayMs) {
      final cached = prefs.getString(cacheKey);
      if (cached != null) {
        final jsonList = json.decode(cached);
        return (jsonList as List).map((e) => Playlist.fromJson(e)).toList();
      }
    }

    // Fetch fresh playlist URLs
    final urls = await _fetchPlaylistUrls(lang);

    // Respect playlistLimit
    final selectedUrls = urls.take(playlistLimit).toList();

    final List<Playlist> playlists = [];

    for (final url in selectedUrls) {
      final playlist = await SaavnAPI().fetchPlaylistById(
        link: url,
        limit: perPlaylistSongCount,
      );
      if (playlist != null && playlist.songs.isNotEmpty) {
        playlists.add(playlist);
      }
    }

    // Cache it
    await prefs.setString(
      cacheKey,
      json.encode(playlists.map(Playlist.playlistToJson).toList()),
    );
    await prefs.setInt(cacheTimeKey, now);

    return playlists;
  }

  static Future<List<String>> _fetchPlaylistUrls(String lang) async {
    final url = Uri.parse('$_baseUrl/featured-playlists/$lang');
    final res = await http.get(
      url,
      headers: {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"},
    );

    if (res.statusCode != 200) {
      debugPrint('Failed to fetch playlists for $lang');
      return [];
    }

    final html = res.body;
    final startIndex = html.indexOf('${lang.capitalize()} Music Playlists');
    if (startIndex == -1) return [];

    final section = html.substring(startIndex);
    final regex = RegExp(r'href="(/featured/[^"]+)"');
    return regex
        .allMatches(section)
        .map((m) => '$_baseUrl${m.group(1)!}')
        .toSet()
        .toList();
  }

  /// ---------------- ALBUM FETCHER ----------------
  static Future<List<Album>> getLatestAlbums(
    String lang, {
    int albumLimit = 30, // number of albums to fetch
    int perAlbumSongCount = 50, // number of songs per album
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = "latest_${lang}_albums";
    final cacheTimeKey = "latest_${lang}_albums_time";

    // Check cache validity (24h)
    const dayMs = 24 * 60 * 60 * 1000;
    final lastFetch = prefs.getInt(cacheTimeKey) ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;

    // Use cache if still valid
    if (now - lastFetch < dayMs) {
      final cached = prefs.getString(cacheKey);
      if (cached != null) {
        final jsonList = json.decode(cached);
        return (jsonList as List).map((e) => Album.fromJson(e)).toList();
      }
    }

    // Fetch album URLs
    final urls = await _fetchAlbumUrls(lang);

    // Respect albumLimit
    final selectedUrls = urls.take(albumLimit).toList();

    final List<Album> albums = [];

    for (final url in selectedUrls) {
      final album = await SaavnAPI().fetchAlbumById(
        link: url,
        limit: perAlbumSongCount,
      );
      if (album != null && album.songs.isNotEmpty) {
        albums.add(album);
      }
    }

    // Cache results
    await prefs.setString(
      cacheKey,
      json.encode(albums.map(Album.albumToJson).toList()),
    );
    await prefs.setInt(cacheTimeKey, now);

    return albums;
  }

  static Future<List<String>> _fetchAlbumUrls(String lang) async {
    final url = Uri.parse('$_baseUrl/new-releases/$lang');
    final res = await http.get(
      url,
      headers: {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)"},
    );

    if (res.statusCode != 200) {
      debugPrint('Failed to fetch albums for $lang');
      return [];
    }

    final html = res.body;
    final startIndex = html.indexOf('New ${lang.capitalize()} Songs');
    if (startIndex == -1) return [];

    final section = html.substring(startIndex);
    final regex = RegExp(r'href="(/album/[^"]+)"');
    return regex
        .allMatches(section)
        .map((m) => '$_baseUrl${m.group(1)!}')
        .toSet()
        .toList();
  }
}

/// Helper
extension Cap on String {
  String capitalize() =>
      isEmpty ? this : '${this[0].toUpperCase()}${substring(1)}';
}
