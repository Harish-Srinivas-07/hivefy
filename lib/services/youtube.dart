// lib/services/youtube.dart
//
// Pure-Dart InnerTube layer targeting YouTube Music (WEB_REMIX client) for
// browse/search and the VISIONOS client (id 101) for stream URL resolution.
//
// Architecture: global singleton `youtube` (YoutubeAPI) is used throughout the
// app.

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hivefy/utils/logger.dart';

import '../models/database.dart';
import '../models/datamodel.dart';
import 'chunk_downloader.dart';

// ---------------------------------------------------------------------------
// Global singleton
// ---------------------------------------------------------------------------
final youtube = YoutubeAPI();

class ExploreCategory {
  final String title;
  final String browseParams;
  final String imageUrl;

  const ExploreCategory({required this.title, required this.browseParams, this.imageUrl = ''});

  ExploreCategory withImageUrl(String url) => ExploreCategory(title: title, browseParams: browseParams, imageUrl: url);
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
const _ytmHost = 'https://music.youtube.com/youtubei/v1';
const _ytmSuffix = '?prettyPrint=false&alt=json';

const _visionosPlayerUrl = 'https://youtubei.googleapis.com/youtubei/v1/player?prettyPrint=false';

const _visitorDataKey = 'yt_visitor_data';

// WEB_REMIX client constants (plan section 4.3)
const _remixClientName = 'WEB_REMIX';
const _remixClientVersion = '1.20260804.16.00';
const _remixClientId = '67';
const _remixUA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:140.0) Gecko/20100101 Firefox/140.0';

// VISIONOS client constants (plan section 4.3)
const _visionosClientName = 'VISIONOS';
const _visionosClientVersion = '1.04';
const visionosUserAgent =
    'com.google.visionos.youtube/1.04(RealityDevice17,1; U; CPU visionOS 26_6_0 like Mac OS X; US)';

// Search filter params (YouPipe Music, plan 6.1.2)
const _paramSongs = 'EgWKAQIIAWoSEAUQCRADEAQQChAOEBAQFRAR';
const _paramAlbums = 'EgWKAQIYAWoSEAUQCRADEAQQChAOEBAQFRAR';
const _paramArtists = 'EgWKAQIgAWoSEAUQCRADEAQQChAOEBAQFRAR';
const _paramFeaturedPlaylists = 'EgeKAQQoADgBahIQBRAJEAMQBBAKEA4QEBAVEBE%3D';

// CPN character set
const _cpnChars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_';

// ---------------------------------------------------------------------------
// Enum types used by YoutubeAPI and its callers.
// ---------------------------------------------------------------------------

enum ArtistSongsSortBy { popularity, latest, alphabetical }

extension ArtistSongsSortByExt on ArtistSongsSortBy {
  String get value {
    switch (this) {
      case ArtistSongsSortBy.popularity:
        return 'popularity';
      case ArtistSongsSortBy.latest:
        return 'latest';
      case ArtistSongsSortBy.alphabetical:
        return 'alphabetical';
    }
  }
}

enum SortOrder { asc, desc }

extension SortOrderExt on SortOrder {
  String get value => this == SortOrder.asc ? 'asc' : 'desc';
}

// ---------------------------------------------------------------------------
// YoutubeAPI
// ---------------------------------------------------------------------------
class YoutubeAPI {
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      contentType: 'application/json',
    ),
  );

  String? _visitorData;
  Dio get mediaDio => _dio;

  /// Fetches YouTube Music's radio queue for a song, without resolving streams yet.
  Future<List<SongDetail>> fetchRadioSongs(String videoId) async {
    if (videoId.isEmpty) return [];
    try {
      final data = await _ytmPost('next', {
        'videoId': videoId,
        'playlistId': 'RDAMVM$videoId',
        'isAudioOnly': true,
        'enablePersistentPlaylistPanel': true,
        'tunerSettingValue': 'AUTOMIX_SETTING_NORMAL',
        'watchEndpointMusicSupportedConfigs': {
          'watchEndpointMusicConfig': {'hasPersistentPlaylistPanel': true, 'musicVideoType': 'MUSIC_VIDEO_TYPE_ATV'},
        },
      });
      return parseRadioSongsForTesting(data);
    } catch (e) {
      developer.log('fetchRadioSongs error: $e', name: 'YoutubeAPI');
      return [];
    }
  }

  @visibleForTesting
  List<SongDetail> parseRadioSongsForTesting(dynamic data) {
    final songs = <SongDetail>[];
    final seen = <String>{};
    for (final item in _findAll(data, 'playlistPanelVideoRenderer')) {
      if (item is! Map) continue;
      final id = (item['videoId'] ?? _nav(item, ['navigationEndpoint', 'watchEndpoint', 'videoId']) ?? '').toString();
      final title = _textFromRenderer(item['title']);
      if (id.isEmpty || title.isEmpty || !seen.add(id)) continue;
      final byline = item['longBylineText'] ?? item['shortBylineText'];
      final runs = byline is Map && byline['runs'] is List ? byline['runs'] as List : const [];
      final artists = <Artist>[];
      String? albumId;
      String? albumName;
      for (final run in runs) {
        final name = _textOf(run).trim();
        final browseId = _nav(run, ['navigationEndpoint', 'browseEndpoint', 'browseId'])?.toString() ?? '';
        if (name.isEmpty) continue;
        if (browseId.startsWith('UC') && !artists.any((artist) => artist.id == browseId)) {
          artists.add(
            Artist(
              id: browseId,
              title: name,
              type: 'artist',
              url: 'https://music.youtube.com/channel/$browseId',
              images: [],
            ),
          );
        } else if (browseId.startsWith('MPREb_')) {
          albumId = browseId;
          albumName = name;
        }
      }
      final thumbnails = _nav(item, ['thumbnail', 'thumbnails']);
      final imageUrl = thumbnails is List
          ? thumbnails.whereType<Map>().map((thumbnail) => thumbnail['url']).whereType<String>().lastOrNull ?? ''
          : '';
      final duration = _durationToSeconds(_textFromRenderer(item['lengthText']));
      final artist = artists.isNotEmpty
          ? artists.map((artist) => artist.title).join(', ')
          : _textFromRenderer(item['shortBylineText']);
      songs.add(
        SongDetail(
          id: id,
          ytVideoId: id,
          title: title,
          type: 'song',
          url: 'https://music.youtube.com/watch?v=$id',
          images: imageUrl.isEmpty ? [] : [SourceUrl(quality: 'default', url: imageUrl)],
          primaryArtists: artist,
          contributors: Contributors(primary: artists, all: artists),
          album: albumName ?? '',
          albumName: albumName,
          albumId: albumId,
          duration: duration.isEmpty ? null : duration,
        ),
      );
    }
    return songs;
  }

  /// Returns the plain lyrics attached to a video's music watch tab, if any.
  Future<String?> fetchPlainLyrics(String videoId) async {
    try {
      final next = await _ytmPost('next', {'videoId': videoId});
      final id = _findAll(next, 'browseId').whereType<String>().where((id) => id.startsWith('MPLY')).firstOrNull;
      if (id == null) return null;
      final data = await _ytmPost('browse', {'browseId': id});
      for (final shelf in _findAll(data, 'musicDescriptionShelfRenderer')) {
        final text = _textFromRenderer(shelf['description']).trim();
        if (text.isNotEmpty) return text;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Timed transcript cues for the exact video; captions can differ from lyrics.
  Future<String?> fetchTimedTranscript(String videoId) async {
    try {
      final bytes = utf8.encode(videoId);
      if (bytes.length > 127) return null;
      final data = await _ytmPost('get_transcript', {
        'params': base64.encode([0x0a, bytes.length, ...bytes]),
      });
      final lines = <String>[];
      for (final cue in _findAll(data, 'transcriptCueRenderer')) {
        if (cue is! Map) continue;
        final millis = int.tryParse('${cue['startOffsetMs'] ?? ''}');
        final text = _textFromRenderer(cue['cue']).replaceAll('\n', ' ').trim();
        if (millis == null || millis < 0 || text.isEmpty) continue;
        final minutes = millis ~/ 60000;
        final seconds = (millis ~/ 1000) % 60;
        final fraction = millis % 1000;
        lines.add(
          '[${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}.${fraction.toString().padLeft(3, '0')}]$text',
        );
      }
      return lines.isEmpty ? null : lines.join('\n');
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // visitorData
  // -------------------------------------------------------------------------

  /// Returns cached visitorData, fetching and persisting it on first call.
  Future<String> _getVisitorData() async {
    if (_visitorData != null && _visitorData!.isNotEmpty) {
      return _visitorData!;
    }

    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_visitorDataKey);
    if (cached != null && cached.isNotEmpty) {
      _visitorData = cached;
      return _visitorData!;
    }

    // Fetch from YouTube
    try {
      final ctx = _visionosContext('');
      final resp = await _dio.post(
        'https://www.youtube.com/youtubei/v1/visitor_id?prettyPrint=false',
        data: {'context': ctx},
        options: Options(headers: _visionosHeaders()),
      );
      final vd = _nav(resp.data, ['responseContext', 'visitorData']) as String?;
      if (vd != null && vd.isNotEmpty) {
        _visitorData = vd;
        await prefs.setString(_visitorDataKey, vd);
        return vd;
      }
    } catch (e) {
      developer.log('visitorData fetch error: $e', name: 'YoutubeAPI');
    }

    // Fallback: use a placeholder (some calls work without it)
    _visitorData = '';
    return '';
  }

  // -------------------------------------------------------------------------
  // Context builders
  // -------------------------------------------------------------------------

  Map<String, dynamic> _remixContext(String visitorData) => {
    'client': {
      'clientName': _remixClientName,
      'clientVersion': _remixClientVersion,
      'hl': 'en',
      'gl': 'US',
      'utcOffsetMinutes': 0,
      if (visitorData.isNotEmpty) 'visitorData': visitorData,
    },
    'user': {'lockedSafetyMode': false},
    'request': {'useSsl': true, 'internalExperimentFlags': []},
  };

  Map<String, dynamic> _visionosContext(String visitorData) => {
    'client': {
      'clientName': _visionosClientName,
      'clientVersion': _visionosClientVersion,
      'clientScreen': 'WATCH',
      'platform': 'MOBILE',
      'deviceMake': 'Apple',
      'deviceModel': 'RealityDevice17,1',
      'osName': 'visionOS',
      'osVersion': '26.6.0.23O770',
      'hl': 'en',
      'gl': 'US',
      'utcOffsetMinutes': 0,
      if (visitorData.isNotEmpty) 'visitorData': visitorData,
    },
    'user': {'lockedSafetyMode': false},
    'request': {'useSsl': true, 'internalExperimentFlags': []},
  };

  // -------------------------------------------------------------------------
  // Header builders
  // -------------------------------------------------------------------------

  Map<String, String> _remixHeaders(String visitorData) => {
    'User-Agent': _remixUA,
    'X-YouTube-Client-Name': _remixClientId,
    'X-YouTube-Client-Version': _remixClientVersion,
    'Origin': 'https://music.youtube.com',
    'Referer': 'https://music.youtube.com/',
    if (visitorData.isNotEmpty) 'X-Goog-Visitor-Id': visitorData,
    'Cookie': 'SOCS=CAE=',
    'Content-Type': 'application/json',
  };

  Map<String, String> _visionosHeaders() => {
    'User-Agent': visionosUserAgent,
    'X-Goog-Api-Format-Version': '2',
    'Content-Type': 'application/json',
  };

  // -------------------------------------------------------------------------
  // Low-level YTM POST
  // -------------------------------------------------------------------------

  Future<dynamic> _ytmPost(String endpoint, Map<String, dynamic> body) async {
    final vd = await _getVisitorData();
    final url = '$_ytmHost/$endpoint$_ytmSuffix';
    final resp = await _dio.post(
      url,
      data: {'context': _remixContext(vd), ...body},
      options: Options(headers: _remixHeaders(vd)),
    );
    return resp.data;
  }

  /// Loads the mood and genre tiles exposed by YouTube Music Explore (M3).
  Future<List<ExploreCategory>> fetchExploreCategories() async {
    try {
      final data = await _ytmPost('browse', {'browseId': 'FEmusic_moods_and_genres'});
      final categories = <ExploreCategory>[];
      for (final renderer in _findAll(data, 'musicNavigationButtonRenderer')) {
        if (renderer is! Map) continue;
        final title = _textFromRenderer(renderer['buttonText']).isNotEmpty
            ? _textFromRenderer(renderer['buttonText'])
            : _textFromRenderer(renderer['title']);
        final endpoint = _nav(renderer, ['clickCommand', 'browseEndpoint']);
        final params = endpoint is Map ? (endpoint['params']?.toString() ?? '') : '';
        if (title.isEmpty || params.isEmpty || categories.any((item) => item.title == title)) continue;
        final thumb = _findAll(
          renderer,
          'thumbnails',
        ).map(_lastThumbnail).firstWhere((url) => url.isNotEmpty, orElse: () => '');
        categories.add(ExploreCategory(title: title, browseParams: params, imageUrl: thumb));
      }
      return categories;
    } catch (e) {
      developer.log('fetchExploreCategories error: $e', name: 'YoutubeAPI');
      return [];
    }
  }

  /// Loads playlists for a mood or genre tile (M4).
  Future<List<Playlist>> fetchExploreCategoryPlaylists(ExploreCategory category, {int limit = 30}) async {
    try {
      final data = await _ytmPost('browse', {
        'browseId': 'FEmusic_moods_and_genres_category',
        'params': category.browseParams,
      });
      final playlists = <Playlist>[];
      for (final renderer in _findAll(data, 'musicTwoRowItemRenderer')) {
        final playlist = _parseExplorePlaylist(renderer);
        if (playlist != null && !playlists.any((item) => item.id == playlist.id)) playlists.add(playlist);
        if (playlists.length >= limit) break;
      }
      if (playlists.isEmpty) {
        for (final renderer in _findAll(data, 'musicResponsiveListItemRenderer')) {
          final playlist = _parseExplorePlaylist(renderer);
          if (playlist != null && !playlists.any((item) => item.id == playlist.id)) playlists.add(playlist);
          if (playlists.length >= limit) break;
        }
      }
      return playlists;
    } catch (e) {
      developer.log('fetchExploreCategoryPlaylists error: $e', name: 'YoutubeAPI');
      return [];
    }
  }

  Playlist? _parseExplorePlaylist(dynamic renderer) {
    if (renderer is! Map) return null;
    final browseIds = _findAll(renderer, 'browseId').whereType<String>();
    var id = browseIds.where((value) => value.startsWith('VL')).firstOrNull ?? '';
    if (id.isEmpty) {
      final playlistId = _findAll(
        renderer,
        'playlistId',
      ).whereType<String>().where((value) => value.isNotEmpty && !value.startsWith('RD')).firstOrNull;
      if (playlistId != null) id = 'VL$playlistId';
    }
    if (!id.startsWith('VL')) return null;

    final title = _textFromRenderer(renderer['title']).isNotEmpty
        ? _textFromRenderer(renderer['title'])
        : _textFromRenderer(_nav(renderer, ['flexColumns', 0, 'musicResponsiveListItemFlexColumnRenderer', 'text']));
    if (title.isEmpty) return null;
    final thumbnails = _findAll(renderer, 'thumbnails');
    final image = thumbnails.map(_lastThumbnail).firstWhere((url) => url.isNotEmpty, orElse: () => '');
    final subtitle = _textFromRenderer(_nav(renderer, ['subtitle']));
    return Playlist(
      id: id,
      title: title,
      type: 'playlist',
      url: 'https://music.youtube.com/playlist?list=${id.replaceFirst('VL', '')}',
      images: image.isEmpty ? [] : [SourceUrl(quality: 'default', url: image)],
      description: subtitle,
      summary: subtitle,
    );
  }

  // -------------------------------------------------------------------------
  // CPN generator
  // -------------------------------------------------------------------------

  String _generateCpn() {
    final rng = Random.secure();
    return List.generate(16, (_) => _cpnChars[rng.nextInt(_cpnChars.length)]).join();
  }

  // -------------------------------------------------------------------------
  // Safe navigation helpers
  // -------------------------------------------------------------------------

  /// Safe deep-navigation: walk [path] through [j].
  /// Returns null on any miss or type mismatch.
  dynamic _nav(dynamic j, List<dynamic> path) {
    dynamic cur = j;
    for (final key in path) {
      if (cur == null) return null;
      if (key is String && cur is Map) {
        cur = cur[key];
      } else if (key is int && cur is List && key < cur.length) {
        cur = cur[key];
      } else {
        return null;
      }
    }
    return cur;
  }

  /// Recursively collect every value whose key equals [key].
  /// Used for defensive parsing of deeply nested YouTube responses.
  // ignore: unused_element
  Iterable<dynamic> _findAll(dynamic j, String key) sync* {
    if (j is Map) {
      for (final k in j.keys) {
        if (k == key) yield j[k];
        yield* _findAll(j[k], key);
      }
    } else if (j is List) {
      for (final v in j) {
        yield* _findAll(v, key);
      }
    }
  }

  /// Extract text from a run object (supports `text` and `simpleText`).
  String _textOf(dynamic run) {
    if (run is Map) {
      return (run['text'] ?? run['simpleText'] ?? '').toString();
    }
    return '';
  }

  String _textFromRenderer(dynamic value) {
    if (value is! Map) return '';
    final runs = value['runs'];
    if (runs is List) return runs.map(_textOf).join().trim();
    return (value['simpleText'] ?? '').toString().trim();
  }

  @visibleForTesting
  ({String subtitle, int? songCount}) parsePlaylistMetadataForTesting(dynamic item) => _parsePlaylistMetadata(item);

  ({String subtitle, int? songCount}) _parsePlaylistMetadata(dynamic item) {
    final subtitle = _textFromRenderer(
      _nav(item, ['flexColumns', 1, 'musicResponsiveListItemFlexColumnRenderer', 'text']),
    );
    return (subtitle: subtitle, songCount: _songCountFromText(subtitle));
  }

  int? _songCountFromText(String text) {
    final match = RegExp(r'\b([\d,]+)\s+songs?\b', caseSensitive: false).firstMatch(text);
    return match == null ? null : int.tryParse(match.group(1)!.replaceAll(',', ''));
  }

  @visibleForTesting
  ({String subtitle, int? songCount, String description}) parsePlaylistHeaderForTesting(dynamic header) =>
      _parsePlaylistHeader(header);

  ({String subtitle, int? songCount, String description}) _parsePlaylistHeader(dynamic header) {
    final parts = [
      _textFromRenderer(_nav(header, ['straplineTextOne'])),
      _textFromRenderer(_nav(header, ['subtitle'])),
      _textFromRenderer(_nav(header, ['secondSubtitle'])),
    ].where((s) => s.isNotEmpty).toList();
    final subtitle = parts.join(' • ');
    final description = _textFromRenderer(
      _nav(header, ['description', 'musicDescriptionShelfRenderer', 'description']) ?? _nav(header, ['description']),
    );
    return (subtitle: subtitle, songCount: _songCountFromText(subtitle), description: description);
  }

  @visibleForTesting
  ({String biography, int? subscribers}) parseArtistProfileForTesting(dynamic data) => _parseArtistProfile(data);

  ({String biography, int? subscribers}) _parseArtistProfile(dynamic data) {
    final header =
        _nav(data, ['header', 'musicImmersiveHeaderRenderer']) ??
        _nav(data, ['header', 'musicVisualHeaderRenderer']) ??
        _findAll(data, 'musicResponsiveHeaderRenderer').firstOrNull;
    final about = _findAll(data, 'musicDescriptionShelfRenderer').firstOrNull;
    var biography = _textFromRenderer(_nav(header, ['description']));
    if (biography.isEmpty) {
      biography = _textFromRenderer(_nav(about, ['description']));
    }
    final subscriberText = _textFromRenderer(
      _nav(header, ['subscriptionButton', 'subscribeButtonRenderer', 'subscriberCountText']),
    );
    final match = RegExp(r'^\s*([\d,.]+)\s*([KMB])?', caseSensitive: false).firstMatch(subscriberText);
    int? subscribers;
    if (match != null) {
      final suffix = (match.group(2) ?? '').toUpperCase();
      final number = double.tryParse(match.group(1)!.replaceAll(',', ''));
      if (number != null) {
        final multiplier = switch (suffix) {
          'K' => 1000,
          'M' => 1000000,
          'B' => 1000000000,
          _ => 1,
        };
        subscribers = (number * multiplier).round();
      }
    }
    return (biography: biography, subscribers: subscribers);
  }

  /// Extract the last (highest-quality) thumbnail URL from a thumbnails array.
  String _lastThumbnail(dynamic thumbnails) {
    if (thumbnails is! List || thumbnails.isEmpty) return '';
    return (thumbnails.last['url'] ?? '').toString();
  }

  /// Convert a duration string like "3:45" to seconds as a String.
  String _durationToSeconds(String text) {
    try {
      final parts = text.trim().split(':');
      if (parts.length == 2) {
        return (int.parse(parts[0]) * 60 + int.parse(parts[1])).toString();
      }
      if (parts.length == 3) {
        return (int.parse(parts[0]) * 3600 + int.parse(parts[1]) * 60 + int.parse(parts[2])).toString();
      }
    } catch (_) {}
    return '';
  }

  // -------------------------------------------------------------------------
  // Parse musicShelfRenderer items
  // -------------------------------------------------------------------------

  /// Walk the search response and return a flat list of
  /// `musicResponsiveListItemRenderer` maps.
  List<dynamic> _extractShelfItems(dynamic data) {
    try {
      final tabs = _nav(data, [
        'contents',
        'tabbedSearchResultsRenderer',
        'tabs',
        0,
        'tabRenderer',
        'content',
        'sectionListRenderer',
        'contents',
      ]);
      if (tabs is! List) return [];

      final items = <dynamic>[];
      for (final section in tabs) {
        final shelf = section['musicShelfRenderer'];
        if (shelf == null) continue;
        final contents = shelf['contents'];
        if (contents is List) items.addAll(contents);
      }
      return items;
    } catch (_) {
      return [];
    }
  }

  /// Parse a `musicResponsiveListItemRenderer` into a partial song map.
  @visibleForTesting
  SongDetail? parseSongItemForTesting(dynamic item) => _parseSongItem(item);

  SongDetail? _parseSongItem(dynamic item) {
    try {
      final r = item['musicResponsiveListItemRenderer'];
      if (r == null) return null;

      // videoId — try overlay first, then flex column 0
      String videoId =
          (_nav(r, [
                    'overlay',
                    'musicItemThumbnailOverlayRenderer',
                    'content',
                    'musicPlayButtonRenderer',
                    'playNavigationEndpoint',
                    'watchEndpoint',
                    'videoId',
                  ]) ??
                  _nav(r, [
                    'flexColumns',
                    0,
                    'musicResponsiveListItemFlexColumnRenderer',
                    'text',
                    'runs',
                    0,
                    'navigationEndpoint',
                    'watchEndpoint',
                    'videoId',
                  ]) ??
                  _nav(r, ['playlistItemData', 'videoId']) ??
                  '')
              .toString();

      if (videoId.isEmpty) return null;

      // title from flex column 0 run 0
      final titleRuns = _nav(r, ['flexColumns', 0, 'musicResponsiveListItemFlexColumnRenderer', 'text', 'runs']);
      final title = (titleRuns is List && titleRuns.isNotEmpty) ? _textOf(titleRuns[0]) : '';

      // flex column 1 runs — artist is usually run 0; duration has ":"
      final columns = _nav(r, ['flexColumns']);

      String artist = '';
      String durationText = '';
      String albumName = '';
      String? albumId;
      final artists = <Artist>[];

      if (columns is List) {
        for (final column in columns.skip(1)) {
          final runs = _nav(column, ['musicResponsiveListItemFlexColumnRenderer', 'text', 'runs']);
          if (runs is! List) continue;
          for (final run in runs) {
            final t = _textOf(run);
            final browseId = _nav(run, ['navigationEndpoint', 'browseEndpoint', 'browseId'])?.toString() ?? '';
            if (browseId.startsWith('UC') && t.isNotEmpty && !artists.any((a) => a.id == browseId)) {
              artists.add(
                Artist(
                  id: browseId,
                  title: t,
                  type: 'artist',
                  url: 'https://music.youtube.com/channel/$browseId',
                  images: [],
                ),
              );
            } else if (browseId.startsWith('MPREb_') && t.isNotEmpty) {
              albumId = browseId;
              albumName = t;
            }
            if (t.contains(':') && t.length <= 7) {
              durationText = t;
            }
            if (artist.isEmpty &&
                browseId.isEmpty &&
                t.trim().isNotEmpty &&
                !t.contains(':') &&
                !{'song', 'video', ' • '}.contains(t.toLowerCase())) {
              artist = t.trim();
            }
          }
        }
      }
      if (artists.isNotEmpty) artist = artists.map((a) => a.title).join(', ');
      final fixedRuns = _nav(r, ['fixedColumns', 0, 'musicResponsiveListItemFixedColumnRenderer', 'text', 'runs']);
      if (durationText.isEmpty && fixedRuns is List) {
        for (final run in fixedRuns) {
          final value = _textOf(run);
          if (RegExp(r'^\d+:\d{2}(:\d{2})?$').hasMatch(value)) {
            durationText = value;
            break;
          }
        }
      }

      // thumbnail
      final thumbs = _nav(r, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']);
      final thumbUrl = _lastThumbnail(thumbs);

      final images = thumbUrl.isNotEmpty ? [SourceUrl(quality: 'default', url: thumbUrl)] : <SourceUrl>[];

      return SongDetail(
        id: videoId,
        title: title,
        type: 'song',
        url: 'https://music.youtube.com/watch?v=$videoId',
        images: images,
        primaryArtists: artist,
        album: albumName,
        albumName: albumName,
        albumId: albumId,
        contributors: Contributors(primary: artists, all: artists),
        duration: durationText.isNotEmpty ? _durationToSeconds(durationText) : null,
        downloadUrls: const [],
        ytVideoId: videoId,
      );
    } catch (_) {
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // searchSongs (M6 songs filter)
  // -------------------------------------------------------------------------

  Future<List<SongDetail>> searchSongs({required String query, int page = 0, int limit = 50}) async {
    if (query.isEmpty) return [];

    try {
      final data = await _ytmPost('search', {'query': query, 'params': _paramSongs});

      final rawItems = _extractShelfItems(data);
      final songs = <SongDetail>[];
      for (final item in rawItems) {
        final s = _parseSongItem(item);
        if (s != null) songs.add(s);
        if (songs.length >= limit) break;
      }
      return songs;
    } catch (e) {
      developer.log('searchSongs error: $e', name: 'YoutubeAPI');
      return [];
    }
  }

  // -------------------------------------------------------------------------
  // searchArtists (M6 artists filter)
  // -------------------------------------------------------------------------

  Future<List<Album>> searchAlbums({required String query, int limit = 10}) async {
    if (query.isEmpty) return [];
    try {
      final data = await _ytmPost('search', {'query': query, 'params': _paramAlbums});
      final albums = <Album>[];
      for (final item in _extractShelfItems(data)) {
        final r = item['musicResponsiveListItemRenderer'];
        if (r == null) continue;
        final browseIds = _findAll(r, 'browseId').whereType<String>();
        final id = browseIds.where((id) => id.startsWith('MPREb_')).firstOrNull;
        if (id == null) continue;
        final titleRuns = _nav(r, ['flexColumns', 0, 'musicResponsiveListItemFlexColumnRenderer', 'text', 'runs']);
        final subtitle = _nav(r, ['flexColumns', 1, 'musicResponsiveListItemFlexColumnRenderer', 'text', 'runs']);
        final thumb = _lastThumbnail(_nav(r, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']));
        albums.add(
          Album(
            id: id,
            title: titleRuns is List && titleRuns.isNotEmpty ? _textOf(titleRuns.first) : '',
            type: 'album',
            url: 'https://music.youtube.com/browse/$id',
            images: thumb.isEmpty ? [] : [SourceUrl(quality: 'default', url: thumb)],
            artist: subtitle is List
                ? subtitle.map(_textOf).where((s) => s.isNotEmpty && s != ' • ' && s != 'Album').join(' ')
                : '',
          ),
        );
        if (albums.length >= limit) break;
      }
      return albums;
    } catch (e) {
      developer.log('searchAlbums error: $e', name: 'YoutubeAPI');
      return [];
    }
  }

  Future<SearchArtistsResponse?> searchArtists({required String query, int page = 0, int limit = 10}) async {
    if (query.isEmpty) return null;

    try {
      final data = await _ytmPost('search', {'query': query, 'params': _paramArtists});

      final rawItems = _extractShelfItems(data);
      final artists = <Artist>[];

      for (final item in rawItems) {
        try {
          final r = item['musicResponsiveListItemRenderer'];
          if (r == null) continue;

          final browseId =
              _findAll(r, 'browseId').whereType<String>().where((id) => id.startsWith('UC')).firstOrNull ?? '';

          if (!browseId.startsWith('UC')) continue;

          final titleRuns = _nav(r, ['flexColumns', 0, 'musicResponsiveListItemFlexColumnRenderer', 'text', 'runs']);
          final name = (titleRuns is List && titleRuns.isNotEmpty) ? _textOf(titleRuns[0]) : '';

          final thumbs = _nav(r, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']);
          final thumbUrl = _lastThumbnail(thumbs);
          final images = thumbUrl.isNotEmpty ? [SourceUrl(quality: 'default', url: thumbUrl)] : <SourceUrl>[];

          artists.add(
            Artist(
              id: browseId,
              title: name,
              type: 'artist',
              url: 'https://music.youtube.com/channel/$browseId',
              images: images,
            ),
          );

          if (artists.length >= limit) break;
        } catch (_) {
          continue;
        }
      }

      return SearchArtistsResponse(total: artists.length, start: 0, results: artists);
    } catch (e) {
      developer.log('searchArtists error: $e', name: 'YoutubeAPI');
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // searchPlaylists (M6 featured playlists filter)
  // -------------------------------------------------------------------------

  Future<SearchPlaylistsResponse?> searchPlaylists({required String query, int page = 0, int limit = 10}) async {
    if (query.isEmpty) return null;

    try {
      final data = await _ytmPost('search', {'query': query, 'params': _paramFeaturedPlaylists});

      final rawItems = _extractShelfItems(data);
      final playlists = <Playlist>[];

      for (final item in rawItems) {
        try {
          final r = item['musicResponsiveListItemRenderer'];
          if (r == null) continue;

          var browseId =
              _findAll(r, 'browseId').whereType<String>().where((id) => id.startsWith('VL')).firstOrNull ?? '';

          if (browseId.isEmpty) {
            final playlistId = _findAll(
              r,
              'playlistId',
            ).whereType<String>().where((id) => !id.startsWith('RD')).firstOrNull;
            if (playlistId != null) browseId = 'VL$playlistId';
          }
          if (!browseId.startsWith('VL')) continue;

          final titleRuns = _nav(r, ['flexColumns', 0, 'musicResponsiveListItemFlexColumnRenderer', 'text', 'runs']);
          final title = (titleRuns is List && titleRuns.isNotEmpty) ? _textOf(titleRuns[0]) : '';

          final metadata = _parsePlaylistMetadata(r);

          final thumbs = _nav(r, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']);
          final thumbUrl = _lastThumbnail(thumbs);
          final images = thumbUrl.isNotEmpty ? [SourceUrl(quality: 'default', url: thumbUrl)] : <SourceUrl>[];

          playlists.add(
            Playlist(
              id: browseId,
              title: title,
              type: 'playlist',
              url: 'https://music.youtube.com/playlist?list=${browseId.replaceFirst("VL", "")}',
              images: images,
              description: metadata.subtitle,
              summary: metadata.subtitle,
              songCount: metadata.songCount,
            ),
          );

          if (playlists.length >= limit) break;
        } catch (_) {
          continue;
        }
      }

      return SearchPlaylistsResponse(total: playlists.length, start: 0, results: playlists);
    } catch (e) {
      developer.log('searchPlaylists error: $e', name: 'YoutubeAPI');
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // getSearchBoxSuggestions (Y3)
  // -------------------------------------------------------------------------

  Future<List<String>> getSearchBoxSuggestions({required String query}) async {
    if (query.isEmpty) return [];

    const base = 'https://suggestqueries.google.com/complete/search?client=firefox&ds=yt&q=';

    try {
      final resp = await _dio.get(
        '$base${Uri.encodeComponent(query)}',
        options: Options(headers: {'User-Agent': _remixUA}, responseType: ResponseType.plain),
      );
      final decoded = jsonDecode(resp.data.toString()) as List;
      final suggestions = decoded[1] as List;
      return suggestions.map((e) => e.toString()).toList();
    } catch (e) {
      developer.log('getSearchBoxSuggestions error: $e', name: 'YoutubeAPI');
      return [];
    }
  }

  // -------------------------------------------------------------------------
  // globalSearch (M6 unfiltered)
  // -------------------------------------------------------------------------

  // TODO: implement full global search parsing for all categories
  Future<GlobalSearch?> globalSearch(String query) async {
    if (query.isEmpty) return null;

    try {
      final data = await _ytmPost('search', {'query': query});

      // Parse songs shelf from unfiltered results
      final rawItems = _extractShelfItems(data);
      final songs = <Song>[];
      for (final item in rawItems) {
        final s = _parseSongItem(item);
        if (s != null) {
          songs.add(s);
        }
        if (songs.length >= 10) break;
      }

      final albums = await searchAlbums(query: query);
      return GlobalSearch(
        songs: SearchResult<Song>(total: songs.length, results: songs),
        albums: SearchResult<Album>(total: albums.length, results: albums),
        artists: SearchResult<Artist>(total: 0, results: []),
        playlists: SearchResult<Playlist>(total: 0, results: []),
      );
    } catch (e) {
      developer.log('globalSearch error: $e', name: 'YoutubeAPI');
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // resolveStreamUrl (Y15 — VISIONOS player)
  // -------------------------------------------------------------------------

  Future<String?> resolveStreamUrl(String ytVideoId) async => (await resolveDownloadSource(ytVideoId))?.url;

  Future<AudioDownloadSource?> resolveDownloadSource(String ytVideoId, {int? preferredItag}) async {
    if (ytVideoId.isEmpty) return null;

    try {
      final vd = await _getVisitorData();
      final cpn = _generateCpn();

      // Random 12-char t parameter
      final rng = Random.secure();
      final t = List.generate(12, (_) => _cpnChars[rng.nextInt(_cpnChars.length)]).join();

      final url = '$_visionosPlayerUrl&t=$t&id=$ytVideoId';

      final resp = await _dio.post(
        url,
        data: {
          'context': _visionosContext(vd),
          'videoId': ytVideoId,
          'cpn': cpn,
          'contentCheckOk': true,
          'racyCheckOk': true,
        },
        options: Options(headers: _visionosHeaders()),
      );

      final data = resp.data;
      final status = _nav(data, ['playabilityStatus', 'status']);
      if (status != 'OK') {
        developer.log('resolveStreamUrl: status=$status for $ytVideoId', name: 'YoutubeAPI');
        return null;
      }

      final adaptiveFormats = _nav(data, ['streamingData', 'adaptiveFormats']) as List?;
      if (adaptiveFormats == null || adaptiveFormats.isEmpty) return null;

      // Filter audio-only formats (audioQuality present, url present)
      final audioFormats = adaptiveFormats.where((f) {
        return f['audioQuality'] != null && f['url'] != null;
      }).toList();

      if (audioFormats.isEmpty) return null;

      // Prefer AAC, then Opus, retaining a known container for offline files.
      const preferredFormats = [140, 251, 139, 250, 249];
      final matching = preferredItag == null
          ? audioFormats.where((f) => preferredFormats.contains(f['itag'])).toList()
          : audioFormats.where((f) => f['itag'] == preferredItag).toList();
      if (matching.isEmpty) return null;
      if (preferredItag == null) {
        matching.sort((a, b) => preferredFormats.indexOf(a['itag']).compareTo(preferredFormats.indexOf(b['itag'])));
      }
      final chosen = matching.first;

      final streamUrl = '${chosen["url"]}&cpn=$cpn';
      final length =
          int.tryParse(chosen['contentLength']?.toString() ?? '') ??
          int.tryParse(Uri.parse(streamUrl).queryParameters['clen'] ?? '');
      return AudioDownloadSource(
        url: streamUrl,
        itag: chosen['itag'] as int,
        length: length,
        extension: chosen['itag'] == 140 || chosen['itag'] == 139 ? 'm4a' : 'webm',
      );
    } catch (e) {
      developer.log('resolveStreamUrl error: $e', name: 'YoutubeAPI');
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // getSongDetails
  // -------------------------------------------------------------------------

  Future<List<SongDetail>> getSongDetails({List<String>? ids, String? link}) async {
    if ((ids == null || ids.isEmpty) && (link == null || link.isEmpty)) {
      Logger.log('YouTube', 'getSongDetails: Either ids or link must be provided');
      return [];
    }

    final resultMap = <String, SongDetail>{};

    // Check local DB first
    if (ids != null && ids.isNotEmpty) {
      final cached = await AppDatabase.getSongs(ids);
      for (final song in cached) {
        if (song.downloadUrls.isEmpty && song.ytVideoId.isEmpty) {
          await AppDatabase.removeSong(song.id);
          continue;
        }
        resultMap[song.id] = song;
      }
    }

    // If all found locally, return
    if (ids != null && resultMap.length == ids.length) {
      return ids.map((id) => resultMap[id]!).toList();
    }

    // Resolve missing ones via stream URL
    Set<String> missingIds;
    if (ids != null) {
      missingIds = ids.toSet()..removeAll(resultMap.keys);
    } else {
      missingIds = <String>{};
    }

    for (final id in missingIds) {
      try {
        final streamUrl = await resolveStreamUrl(id);
        if (streamUrl != null) {
          final song = SongDetail(
            id: id,
            title: id,
            type: 'song',
            url: 'https://music.youtube.com/watch?v=$id',
            images: const [],
            downloadUrls: [SourceUrl(quality: '128kbps', url: streamUrl)],
            ytVideoId: id,
          );
          await AppDatabase.saveSongDetail(song);
          resultMap[id] = song;
        }
      } catch (e) {
        developer.log('getSongDetails resolve error for $id: $e', name: 'YoutubeAPI');
      }
    }

    return ids != null
        ? ids.where((id) => resultMap.containsKey(id)).map((id) => resultMap[id]!).toList()
        : resultMap.values.toList();
  }

  // -------------------------------------------------------------------------
  // fetchAlbumById (M13)
  // -------------------------------------------------------------------------

  Future<Album?> fetchAlbumById({
    String? albumId,
    String? link,
    int page = 0,
    int limit = 10,
    bool refreshMetadata = false,
  }) async {
    if (albumId == null && link == null) {
      Logger.log('YouTube', 'fetchAlbumById: Need either albumId or link');
      return null;
    }

    final cache = AlbumCache();
    final cacheKey = albumId ?? link!;

    final cached = refreshMetadata ? null : await cache.get(cacheKey);
    if (cached != null) return cached;

    try {
      // Determine browseId: MPREb_ ids are used directly;
      // OLAK playlist ids need an extra browse to find the MPREb_ id.
      String browseId = albumId ?? '';

      if (browseId.startsWith('OLAK')) {
        // Fetch VL+OLAK to extract MPREb_ via regex
        try {
          final resp = await _ytmPost('browse', {'browseId': 'VL$browseId'});
          final raw = jsonEncode(resp);
          final match = RegExp(r'"MPRE.+?"').firstMatch(raw);
          if (match != null) {
            browseId = match.group(0)!.replaceAll('"', '');
          }
        } catch (_) {}
      }

      if (!browseId.startsWith('MPREb_')) {
        // Cannot resolve — return empty
        return null;
      }

      final data = await _ytmPost('browse', {'browseId': browseId});

      // Parse header
      final header =
          _nav(data, ['header', 'musicDetailHeaderRenderer']) ??
          _nav(data, [
            'contents',
            'twoColumnBrowseResultsRenderer',
            'tabs',
            0,
            'tabRenderer',
            'content',
            'sectionListRenderer',
            'contents',
            0,
            'musicResponsiveHeaderRenderer',
          ]) ??
          _findAll(data, 'musicResponsiveHeaderRenderer').firstOrNull;

      String title = '';
      String year = '';
      String artist = '';
      List<SourceUrl> images = [];

      if (header != null) {
        final titleRuns = _nav(header, ['title', 'runs']);
        if (titleRuns is List && titleRuns.isNotEmpty) {
          title = _textOf(titleRuns[0]);
        }

        final strapline = _nav(header, ['straplineTextOne', 'runs']);
        if (strapline is List) artist = strapline.map(_textOf).join().trim();
        final subtitleRuns = _nav(header, ['subtitle', 'runs']);
        if (subtitleRuns is List) {
          for (final run in subtitleRuns) {
            final t = _textOf(run);
            if (RegExp(r'^\d{4}$').hasMatch(t)) {
              year = t;
            } else if (artist.isEmpty && t != ' • ' && t.isNotEmpty && t != 'Album' && t != 'Single' && t != 'EP') {
              artist = t;
            }
          }
        }

        final thumbs =
            _nav(header, ['thumbnail', 'croppedSquareThumbnailRenderer', 'thumbnail', 'thumbnails']) ??
            _nav(header, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']);
        final thumbUrl = _lastThumbnail(thumbs);
        if (thumbUrl.isNotEmpty) {
          images = [SourceUrl(quality: 'default', url: thumbUrl)];
        }
      }

      // Parse tracks from secondaryContents
      final trackList =
          _nav(data, [
            'contents',
            'twoColumnBrowseResultsRenderer',
            'secondaryContents',
            'sectionListRenderer',
            'contents',
            0,
            'musicShelfRenderer',
            'contents',
          ]) ??
          _nav(data, [
            'contents',
            'twoColumnBrowseResultsRenderer',
            'secondaryContents',
            'sectionListRenderer',
            'contents',
            0,
            'musicPlaylistShelfRenderer',
            'contents',
          ]) ??
          _findAll(data, 'musicPlaylistShelfRenderer').map((s) => s['contents']).firstOrNull ??
          _findAll(data, 'musicShelfRenderer').map((s) => s['contents']).firstOrNull;

      final songs = <SongDetail>[];
      if (trackList is List) {
        for (final item in trackList) {
          final s = _parseSongItem(item);
          if (s != null) {
            songs.add(
              SongDetail(
                id: s.id,
                title: s.title,
                type: 'song',
                url: s.url,
                images: s.images.isNotEmpty ? s.images : images,
                primaryArtists: s.primaryArtists.isNotEmpty ? s.primaryArtists : artist,
                duration: s.duration,
                year: year.isNotEmpty ? year : s.year,
                downloadUrls: const [],
                ytVideoId: s.ytVideoId,
                album: title,
                albumName: title,
                albumId: browseId,
                contributors: s.contributors,
              ),
            );
          }
        }
      }

      final album = Album(
        id: browseId,
        title: title,
        type: 'album',
        url: 'https://music.youtube.com/browse/$browseId',
        images: images,
        year: year,
        artist: artist,
        songs: songs,
      );

      if (!refreshMetadata) await cache.set(cacheKey, album);
      return album;
    } catch (e) {
      developer.log('fetchAlbumById error: $e', name: 'YoutubeAPI');
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // fetchArtistDetailsById (M14)
  // -------------------------------------------------------------------------

  Future<ArtistDetails?> fetchArtistDetailsById({
    required String artistId,
    int page = 0,
    int songCount = 10,
    int albumCount = 10,
    String sortBy = 'popularity',
    String sortOrder = 'desc',
  }) async {
    final cache = ArtistCache();

    final cached = await cache.get(artistId);
    if (cached != null &&
        cached.bio.isNotEmpty &&
        cached.followerCount != null &&
        cached.images.any((image) => image.url.trim().isNotEmpty)) {
      return cached;
    }

    try {
      final data = await _ytmPost('browse', {'browseId': artistId});
      final profile = _parseArtistProfile(data);

      // Parse header
      final header =
          _nav(data, ['header', 'musicImmersiveHeaderRenderer']) ??
          _nav(data, ['header', 'musicVisualHeaderRenderer']) ??
          _findAll(data, 'musicResponsiveHeaderRenderer').firstOrNull;

      String name = '';
      List<SourceUrl> images = [];

      if (header != null) {
        final titleRuns = _nav(header, ['title', 'runs']);
        if (titleRuns is List && titleRuns.isNotEmpty) {
          name = _textOf(titleRuns[0]);
        }
        final thumbs =
            _nav(header, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']) ??
            _nav(header, ['foregroundThumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']);
        final thumbUrl = _lastThumbnail(thumbs);
        if (thumbUrl.isNotEmpty) {
          images = [SourceUrl(quality: 'default', url: thumbUrl)];
        }
      }
      if (images.isEmpty && cached != null) images = cached.images;
      if (name.isEmpty && cached != null) name = cached.title;

      // Parse top songs from contents
      final contents =
          _nav(data, [
            'contents',
            'singleColumnBrowseResultsRenderer',
            'tabs',
            0,
            'tabRenderer',
            'content',
            'sectionListRenderer',
            'contents',
          ]) ??
          _findAll(data, 'sectionListRenderer').map((s) => s['contents']).firstOrNull;

      final topSongs = <SongDetail>[];

      if (contents is List) {
        for (final section in contents) {
          final shelf = section['musicShelfRenderer'] ?? section['musicCarouselShelfRenderer'];
          if (shelf == null) continue;

          final shelfContents = shelf['contents'];
          if (shelfContents is! List) continue;

          for (final item in shelfContents) {
            final s = _parseSongItem(item);
            if (s != null) {
              topSongs.add(s);
              if (topSongs.length >= songCount) break;
            }
          }
          if (topSongs.isNotEmpty) break;
        }
      }

      final albums = <Album>[];
      for (final item in _findAll(data, 'musicTwoRowItemRenderer')) {
        final id = _findAll(item, 'browseId').whereType<String>().where((id) => id.startsWith('MPREb_')).firstOrNull;
        if (id == null || albums.any((album) => album.id == id)) continue;
        final titleRuns = _nav(item, ['title', 'runs']);
        final thumbnails = _findAll(item, 'thumbnails').firstOrNull;
        final thumb = _lastThumbnail(thumbnails);
        albums.add(
          Album(
            id: id,
            title: titleRuns is List && titleRuns.isNotEmpty ? _textOf(titleRuns.first) : '',
            type: 'album',
            url: 'https://music.youtube.com/browse/$id',
            images: thumb.isEmpty ? [] : [SourceUrl(quality: 'default', url: thumb)],
            artist: name,
          ),
        );
        if (albums.length >= albumCount) break;
      }

      final details = ArtistDetails(
        id: artistId,
        title: name,
        type: 'artist',
        url: 'https://music.youtube.com/channel/$artistId',
        images: images,
        bio: profile.biography.isEmpty ? [] : [profile.biography],
        followerCount: profile.subscribers,
        topSongs: topSongs,
        topAlbums: albums,
      );

      await cache.set(artistId, details);
      return details;
    } catch (e) {
      developer.log('fetchArtistDetailsById error: $e', name: 'YoutubeAPI');
      return cached;
    }
  }

  // -------------------------------------------------------------------------
  // fetchPlaylistById (M16)
  // -------------------------------------------------------------------------

  Future<Playlist?> fetchPlaylistById({
    String? playlistId,
    String? link,
    int page = 0,
    int limit = 10,
    bool refreshMetadata = false,
    ArtistSongsSortBy sortBy = ArtistSongsSortBy.popularity,
    SortOrder sortOrder = SortOrder.desc,
  }) async {
    if (playlistId == null && link == null) {
      Logger.log('YouTube', 'fetchPlaylistById: Need at least one of playlistId or link');
      return null;
    }

    final cache = PlaylistCache();

    Playlist? cached;
    if (playlistId != null && !refreshMetadata) {
      cached = await cache.get(playlistId);
      if (cached != null &&
          cached.summary.isNotEmpty &&
          (cached.songs.length >= limit || (cached.songCount != null && cached.songs.length >= cached.songCount!))) {
        return cached;
      }
    }

    try {
      // Ensure VL prefix
      final id = playlistId ?? '';
      final browseId = id.startsWith('VL') ? id : 'VL$id';

      final data = await _ytmPost('browse', {'browseId': browseId});

      // Parse header
      final header =
          _nav(data, ['header', 'musicDetailHeaderRenderer']) ??
          _nav(data, ['header', 'musicEditablePlaylistDetailHeaderRenderer', 'header', 'musicDetailHeaderRenderer']) ??
          _findAll(data, 'musicResponsiveHeaderRenderer').firstOrNull;

      String title = '';
      List<SourceUrl> images = [];
      final metadata = _parsePlaylistHeader(header);

      if (header != null) {
        final titleRuns = _nav(header, ['title', 'runs']);
        if (titleRuns is List && titleRuns.isNotEmpty) {
          title = _textOf(titleRuns[0]);
        }
        final thumbs =
            _nav(header, ['thumbnail', 'croppedSquareThumbnailRenderer', 'thumbnail', 'thumbnails']) ??
            _nav(header, ['thumbnail', 'musicThumbnailRenderer', 'thumbnail', 'thumbnails']);
        final thumbUrl = _lastThumbnail(thumbs);
        if (thumbUrl.isNotEmpty) {
          images = [SourceUrl(quality: 'default', url: thumbUrl)];
        }
      }

      // Parse tracks
      final trackList =
          _nav(data, [
            'contents',
            'twoColumnBrowseResultsRenderer',
            'secondaryContents',
            'sectionListRenderer',
            'contents',
            0,
            'musicPlaylistShelfRenderer',
            'contents',
          ]) ??
          _nav(data, [
            'contents',
            'singleColumnBrowseResultsRenderer',
            'tabs',
            0,
            'tabRenderer',
            'content',
            'sectionListRenderer',
            'contents',
            0,
            'musicPlaylistShelfRenderer',
            'contents',
          ]) ??
          _findAll(data, 'musicPlaylistShelfRenderer').map((s) => s['contents']).firstOrNull;

      final songs = <SongDetail>[];
      if (trackList is List) {
        for (final item in trackList) {
          final s = _parseSongItem(item);
          if (s != null) {
            songs.add(s);
            if (songs.length >= limit) break;
          }
        }
      }

      final playlist = Playlist(
        id: browseId,
        title: title,
        type: 'playlist',
        url: 'https://music.youtube.com/playlist?list=${browseId.replaceFirst("VL", "")}',
        images: images,
        songs: songs,
        description: metadata.description,
        summary: metadata.subtitle,
        songCount: metadata.songCount,
      );

      if (cached != null && (playlist.title.isEmpty || (playlist.songs.isEmpty && cached.songs.isNotEmpty))) {
        return cached;
      }
      if (playlistId != null && !refreshMetadata) {
        await cache.set(playlistId, playlist);
      }

      return playlist;
    } catch (e) {
      developer.log('fetchPlaylistById error: $e', name: 'YoutubeAPI');
      return cached;
    }
  }
}
