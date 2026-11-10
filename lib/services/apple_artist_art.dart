import 'dart:convert';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

class AppleArtistArt {
  const AppleArtistArt({required this.heroUrl, this.logoUrl});

  final String heroUrl;
  final String? logoUrl;
}

class AppleArtistArtRepository {
  AppleArtistArtRepository({Dio? dio}) : _dio = dio ?? _createDio();

  static final AppleArtistArtRepository instance = AppleArtistArtRepository();
  final Map<String, AppleArtistArt> _sessionCache = {};
  final Map<String, Future<AppleArtistArt?>> _inFlight = {};

  static Dio _createDio() => Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 12),
      headers: const {'Accept': 'application/json,text/html,*/*'},
    ),
  );
  final Dio _dio;

  Future<AppleArtistArt?> artFor({
    required String browseId,
    required String artistName,
    required Iterable<String> catalogueTitles,
  }) async {
    final key = browseId.trim();
    if (key.isEmpty) return null;
    final cached = _sessionCache[key];
    if (cached != null) return cached;
    final pending = _inFlight[key];
    if (pending != null) return pending;

    final request = _fetch(artistName: artistName, catalogueTitles: catalogueTitles.toList());
    _inFlight[key] = request;
    try {
      final result = await request;
      if (result != null) _sessionCache[key] = result;
      return result;
    } finally {
      if (identical(_inFlight[key], request)) _inFlight.remove(key);
    }
  }

  Future<AppleArtistArt?> _fetch({required String artistName, required List<String> catalogueTitles}) async {
    try {
      final expectedArtist = _normalize(artistName);
      final expectedTitles = catalogueTitles.map(_titleForMatch).where((title) => title.isNotEmpty).toSet();
      if (expectedArtist.isEmpty || expectedTitles.isEmpty) return null;

      final search = await _getJson(
        'https://itunes.apple.com/search',
        queryParameters: {'term': artistName, 'entity': 'musicArtist', 'limit': 5},
      );
      final searchResults = search?['results'];
      if (searchResults is! List) return null;

      for (final result in searchResults.whereType<Map>()) {
        if (_normalize('${result['artistName'] ?? ''}') != expectedArtist) continue;
        try {
          final artistId = result['artistId'];
          final artistPageUrl = '${result['artistLinkUrl'] ?? ''}'.trim().isNotEmpty
              ? '${result['artistLinkUrl']}'.trim()
              : '${result['artistViewUrl'] ?? ''}'.trim();
          if (artistId == null || artistPageUrl.isEmpty) continue;

          final lookup = await _getJson(
            'https://itunes.apple.com/lookup',
            queryParameters: {'id': artistId, 'entity': 'song', 'limit': 200},
          );
          if (!_hasCatalogueMatch(lookup?['results'], expectedTitles)) continue;

          final pageUri = Uri.tryParse(artistPageUrl);
          if (pageUri == null ||
              pageUri.scheme != 'https' ||
              pageUri.host != 'music.apple.com' ||
              pageUri.pathSegments.where((segment) => segment.isNotEmpty).lastOrNull != artistId.toString()) {
            continue;
          }
          final page = await _dio.get<String>(
            pageUri.toString(),
            options: Options(
              responseType: ResponseType.plain,
              headers: const {
                'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
              },
            ),
          );
          final document = html_parser.parse(page.data ?? '');
          final serialized = document.getElementById('serialized-server-data')?.text;
          ({String? hero, String? logo}) templates = (hero: null, logo: null);
          if (serialized != null && serialized.isNotEmpty) {
            try {
              templates = _artworkTemplates(jsonDecode(serialized), artistId.toString());
            } on FormatException {
              // The public metadata below can still provide the artist image.
            }
          }
          final hero = templates.hero ?? document.querySelector('meta[property="og:image"]')?.attributes['content'];
          if (hero != null && hero.isNotEmpty) {
            final heroUrl = _fillTemplate(hero, dimension: 1200, extension: 'jpg');
            if (!_isAppleArtworkUrl(heroUrl)) continue;
            final logoUrl = templates.logo == null
                ? null
                : _fillTemplate(templates.logo!, dimension: 1000, extension: 'png');
            return AppleArtistArt(
              heroUrl: heroUrl,
              logoUrl: logoUrl != null && _isAppleArtworkUrl(logoUrl) ? logoUrl : null,
            );
          }
        } catch (error, stackTrace) {
          developer.log('Apple artist candidate lookup failed: $error', name: 'AppleArtistArt', stackTrace: stackTrace);
        }
      }
    } catch (error, stackTrace) {
      developer.log('Apple artist artwork lookup failed: $error', name: 'AppleArtistArt', stackTrace: stackTrace);
    }
    return null;
  }

  Future<Map<String, dynamic>?> _getJson(String url, {required Map<String, dynamic> queryParameters}) async {
    // iTunes returns JSON as text/javascript, which Dio does not decode as JSON.
    final response = await _dio.get<String>(
      url,
      queryParameters: queryParameters,
      options: Options(responseType: ResponseType.plain),
    );
    final raw = response.data;
    if (raw == null || raw.trim().isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : null;
  }

  bool _hasCatalogueMatch(dynamic results, Set<String> expectedTitles) {
    if (results is! List) return false;
    for (final result in results.whereType<Map>()) {
      for (final key in const ['trackName', 'collectionName']) {
        final title = _titleForMatch('${result[key] ?? ''}');
        if (title.isNotEmpty && expectedTitles.any((expected) => _titlesMatch(title, expected))) return true;
      }
    }
    return false;
  }

  bool _titlesMatch(String candidate, String expected) {
    if (candidate == expected) return true;
    if (candidate.length < 8 || expected.length < 8) return false;
    return candidate.startsWith(expected) || expected.startsWith(candidate);
  }

  String _normalize(String value) => _titleForMatch(value);

  String _titleForMatch(String value) {
    final withoutVersion = value.trim().replaceFirst(RegExp(r'\s*[\(\[\{].*$'), '');
    return withoutVersion
        .toLowerCase()
        .replaceAll(RegExp(r'''[\s.,:;!?"'‘’“”()\[\]{}…—–_\-]+'''), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  ({String? hero, String? logo}) _artworkTemplates(dynamic payload, String artistId) {
    String? hero;
    String? logo;

    String? artworkUrl(dynamic value) {
      if (value is! Map) return null;
      final dictionary = value['dictionary'];
      final url = dictionary is Map ? dictionary['url'] : value['url'];
      return url is String && url.isNotEmpty ? url : null;
    }

    void visit(dynamic value) {
      if (value is Map) {
        if (value['itemKind'] == 'artistDetailHeader' && value['items'] is List) {
          for (final item in value['items'] as List) {
            if (item is Map && '${item['id'] ?? ''}' == artistId) {
              hero =
                  artworkUrl(item['wideArtwork']) ?? artworkUrl(item['artwork']) ?? artworkUrl(item['circleArtwork']);
              logo = artworkUrl(item['artistLogo']);
              if (hero != null) return;
            }
          }
        }
        for (final child in value.values) {
          if (hero != null) return;
          visit(child);
        }
      } else if (value is List) {
        for (final child in value) {
          if (hero != null) return;
          visit(child);
        }
      }
    }

    visit(payload);
    return (hero: hero, logo: logo);
  }

  bool _isAppleArtworkUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme == 'https' &&
        (uri.host == 'mzstatic.com' || uri.host.endsWith('.mzstatic.com')) &&
        !url.contains('{') &&
        !url.toLowerCase().contains('%7b');
  }

  String _fillTemplate(String template, {required int dimension, required String extension}) {
    var url = template
        .replaceAll('{w}', '$dimension')
        .replaceAll('{h}', '$dimension')
        .replaceAll('{c}', 'bb')
        .replaceAll('{f}', extension)
        .replaceAll('%7Bw%7D', '$dimension')
        .replaceAll('%7Bh%7D', '$dimension')
        .replaceAll('%7Bc%7D', 'bb')
        .replaceAll('%7Bf%7D', extension);
    url = url.replaceAllMapped(
      RegExp(r'\d+x\d+bb\.(?:jpg|jpeg|png|webp)', caseSensitive: false),
      (_) => '${dimension}x${dimension}bb.$extension',
    );
    return url;
  }
}
