import 'dart:convert';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:http/http.dart';

import '../models/database.dart';
import '../models/datamodel.dart';

final saavn = SaavnAPI();

class SaavnAPI {
  final String baseUrl = "https://saavn.dev";

  final Map<String, String> headers = {
    "Accept": "application/json",
    "User-Agent":
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36",
  };

  Future<SearchPlaylistsResponse?> searchPlaylists({
    required String query,
    int page =
        0, // Saavn search commonly supports 0-based; keep consistent with songs
    int limit = 10,
  }) async {
    if (query.isEmpty) return null;

    final url = Uri.parse(
      '$baseUrl/api/search/playlists?query=${Uri.encodeComponent(query)}&page=$page&limit=$limit',
    );

    try {
      final response = await get(url, headers: headers);
      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        if (jsonBody['success'] == true && jsonBody['data'] != null) {
          return SearchPlaylistsResponse.fromJson(jsonBody);
        }
      } else {
        debugPrint('Request failed with status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching playlists: $e');
    }
    return null;
  }

  Future<List<SongDetail>> searchSongs({
    required String query,
    int page = 0,
    int limit = 10,
  }) async {
    if (query.isEmpty) return [];

    final url = Uri.parse(
      '$baseUrl/api/search/songs?query=${Uri.encodeComponent(query)}&page=$page&limit=$limit',
    );

    try {
      final response = await get(url, headers: headers);

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);

        if (jsonBody['success'] == true && jsonBody['data'] != null) {
          final List<dynamic> results =
              (jsonBody['data']['results'] as List<dynamic>? ?? []);
          return results.map((e) => SongDetail.fromJson(e)).toList();
        }
      } else {
        debugPrint('searchSongs failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error in searchSongs: $e');
    }

    return [];
  }

  Future<List<SongDetail>> getSongDetails({
    List<String>? ids,
    String? link,
  }) async {
    if ((ids == null || ids.isEmpty) && (link == null || link.isEmpty)) {
      debugPrint("getSongDetails: Either ids or link must be provided");
      return [];
    }

    final Map<String, SongDetail> resultMap = {};

    // -------- Check local DB first --------
    if (ids != null && ids.isNotEmpty) {
      final cachedSongs = await AppDatabase.getSongs(ids);

      for (final song in cachedSongs) {
        // If song has no download URLs, remove it from cache and skip
        if (song.downloadUrls.isEmpty) {
          debugPrint(
            "--- Cached song '${song.title}' has no download URLs, removing from cache",
          );
          await AppDatabase.removeSong(song.id);
          continue;
        }
        resultMap[song.id] = song;
      }
    }

    // If all found locally, return
    if (ids != null && resultMap.length == ids.length) {
      debugPrint(
        "--- All requested songs found in cache with valid download URLs",
      );
      return ids.map((id) => resultMap[id]!).toList();
    }

    // -------- Build query for missing ones / link fetch --------
    final queryParams = <String, String>{};
    if (ids != null && ids.isNotEmpty) {
      final missingIds = ids.toSet()..removeAll(resultMap.keys);
      if (missingIds.isNotEmpty) queryParams['ids'] = missingIds.join(",");
    }
    if (link != null && link.isNotEmpty) queryParams['link'] = link;

    if (queryParams.isEmpty) {
      debugPrint("--- No API fetch needed, returning cached results");
      return ids != null
          ? ids.map((id) => resultMap[id]!).toList()
          : resultMap.values.toList();
    }

    final uri = Uri.parse(
      "$baseUrl/api/songs",
    ).replace(queryParameters: queryParams);

    try {
      final response = await get(uri, headers: headers);
      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        debugPrint('--> JSON fetched from API: $jsonData');

        if (jsonData['success'] == true && jsonData['data'] != null) {
          final List<dynamic> data = jsonData['data'];
          final fetched = data.map((e) => SongDetail.fromJson(e)).toList();
          debugPrint('--> Fetched ${fetched.length} songs from API: $fetched');

          // Cache locally
          for (final song in fetched) {
            await AppDatabase.saveSongDetail(song);
            resultMap[song.id] = song;
          }
        } else {
          debugPrint("getSongDetails returned no data or failed");
        }
      } else {
        debugPrint("getSongDetails failed with status: ${response.statusCode}");
      }
    } catch (e, st) {
      debugPrint("Error in getSongDetails: $e");
      debugPrint("$st");
    }

    return ids != null
        ? ids
            .where((id) => resultMap.containsKey(id))
            .map((id) => resultMap[id]!)
            .toList()
        : resultMap.values.toList();
  }

  Future<List<String>> getSearchBoxSuggestions({required String query}) async {
    if (query.isEmpty) return [];
    const baseUrl =
        'https://suggestqueries.google.com/complete/search?client=firefox&ds=yt&q=';
    final Uri link = Uri.parse(baseUrl + query);
    try {
      final Response response = await get(link, headers: headers);
      if (response.statusCode != 200) return [];
      final unescape = HtmlUnescape();
      final List res = (jsonDecode(response.body) as List)[1] as List;
      return res.map((e) => unescape.convert(e.toString())).toList();
    } catch (e) {
      log('Error in getSearchSuggestions: $e', name: "YoutubeAPI");
      return [];
    }
  }

  Future<ArtistSongsResponse?> getArtistSongsByIdWithTotal({
    required String artistId,
    int page = 0,
    ArtistSongsSortBy sortBy = ArtistSongsSortBy.popularity,
    SortOrder sortOrder = SortOrder.desc,
  }) async {
    final url = Uri.parse(
      '$baseUrl/api/artists/$artistId/songs?page=$page&sortBy=${sortBy.value}&sortOrder=${sortOrder.value}',
    );

    try {
      final response = await get(url, headers: headers);
      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        if (jsonBody['success'] == true && jsonBody['data'] != null) {
          return ArtistSongsResponse.fromJson(jsonBody);
        }
      } else {
        debugPrint('❌ getArtistSongsWithTotal failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('⚠️ Error in getArtistSongsWithTotal: $e');
    }
    return null;
  }

  Future<ArtistDetails?> fetchArtistDetailsById({
    required String artistId,
    int page = 0,
    int songCount = 10,
    int albumCount = 10,
    String sortBy = "popularity",
    String sortOrder = "desc",
  }) async {
    final cache = ArtistCache();

    // ✅ Check cache first (await async getter)
    final cached = await cache.get(artistId);
    if (cached != null) {
      debugPrint("✅ fetchArtistDetailsById: loaded from cache ($artistId)");
      return cached;
    }

    final url = Uri.parse(
      '$baseUrl/api/artists/$artistId?page=$page&songCount=$songCount&albumCount=$albumCount&sortBy=$sortBy&sortOrder=$sortOrder',
    );

    try {
      final response = await get(url, headers: headers);

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        if (jsonBody['success'] == true && jsonBody['data'] != null) {
          final details = ArtistDetails.fromJson(
            jsonBody['data'] as Map<String, dynamic>,
          );

          // ✅ Save to cache (async)
          await cache.set(artistId, details);

          debugPrint("🎤 fetchArtistDetailsById: fetched from API ($artistId)");
          return details;
        } else {
          debugPrint("fetchArtistDetailsById: success=false or data=null");
        }
      } else {
        debugPrint("fetchArtistDetailsById failed: ${response.statusCode}");
      }
    } catch (e, st) {
      debugPrint("⚠️ Error in fetchArtistDetailsById: $e");
      debugPrint("$st");
    }

    return null;
  }

  Future<Playlist?> fetchPlaylistById({
    String? playlistId,
    String? link,
    int page = 0,
    int limit = 10,
    ArtistSongsSortBy sortBy = ArtistSongsSortBy.popularity,
    SortOrder sortOrder = SortOrder.desc,
  }) async {
    if (playlistId == null && link == null) {
      debugPrint("❌ fetchPlaylist: Need at least one of playlistId or link");
      return null;
    }

    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
      'sortBy': sortBy.value,
      'sortOrder': sortOrder.value,
    };

    if (playlistId != null) queryParams['id'] = playlistId;
    if (link != null) queryParams['link'] = link;

    final url = Uri.parse(
      '$baseUrl/api/playlists',
    ).replace(queryParameters: queryParams);

    try {
      final response = await get(url, headers: headers);

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        if (jsonBody['success'] == true && jsonBody['data'] != null) {
          return Playlist.fromJson(jsonBody['data']);
        }
      } else {
        debugPrint("fetchPlaylist failed: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error in fetchPlaylist: $e");
    }
    return null;
  }

  /// Global search returning all categories: songs, albums, artists, playlists
  Future<GlobalSearch?> globalSearch(String query) async {
    if (query.isEmpty) return null;
    final url = Uri.parse(
      '$baseUrl/api/search?query=${Uri.encodeComponent(query)}',
    );
    try {
      final response = await get(url, headers: headers);
      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        if (jsonBody['success'] == true && jsonBody['data'] != null) {
          return GlobalSearch.fromJson(jsonBody['data']);
        }
      } else {
        debugPrint('Global search failed with status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error in global search: $e');
    }
    return null;
  }

  Future<Album?> fetchAlbumById({
    String? albumId,
    String? link,
    int page = 0,
    int limit = 10,
  }) async {
    if (albumId == null && link == null) {
      debugPrint("❌ fetchAlbumById: Need either albumId or link");
      return null;
    }

    final cache = AlbumCache();

    // Use albumId as cache key if available, else fallback to link
    final cacheKey = albumId ?? link!;

    // Await the async cache getter
    final cached = await cache.get(cacheKey);
    if (cached != null) {
      debugPrint("✅ fetchAlbumById: loaded from cache ($cacheKey)");
      return cached;
    }

    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
    };

    if (albumId != null) queryParams['id'] = albumId;
    if (link != null) queryParams['link'] = link;

    final url = Uri.parse(
      '$baseUrl/api/albums',
    ).replace(queryParameters: queryParams);

    try {
      final response = await get(url, headers: headers);

      if (response.statusCode == 200) {
        final jsonBody = json.decode(response.body);
        if (jsonBody['success'] == true && jsonBody['data'] != null) {
          final album = Album.fromJson(jsonBody['data']);

          // Save to cache (async)
          await cache.set(cacheKey, album);

          debugPrint("📀 fetchAlbumById: fetched from API ($cacheKey)");
          return album;
        } else {
          debugPrint("fetchAlbumById: success=false or data=null");
        }
      } else {
        debugPrint("fetchAlbumById failed: ${response.statusCode}");
      }
    } catch (e, st) {
      debugPrint("⚠️ Error in fetchAlbumById: $e");
      debugPrint("$st");
    }
    return null;
  }
}

// enum types
enum ArtistSongsSortBy { popularity, latest, alphabetical }

extension ArtistSongsSortByExt on ArtistSongsSortBy {
  String get value {
    switch (this) {
      case ArtistSongsSortBy.popularity:
        return "popularity";
      case ArtistSongsSortBy.latest:
        return "latest";
      case ArtistSongsSortBy.alphabetical:
        return "alphabetical";
    }
  }
}

enum SortOrder { asc, desc }

extension SortOrderExt on SortOrder {
  String get value => this == SortOrder.asc ? "asc" : "desc";
}
