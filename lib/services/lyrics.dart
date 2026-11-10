import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xml/xml.dart';

import '../models/datamodel.dart';
import 'youtube.dart';

class LyricLine {
  const LyricLine(this.start, this.text, {this.words = const []});
  final Duration start;
  final String text;
  final List<LyricWord> words;
}

/// A timed text fragment. A word can contain several timed syllables.
class LyricWord {
  const LyricWord(this.text, {this.start, this.end});
  final String text;
  final Duration? start;
  final Duration? end;
}

enum LyricsProvider {
  lrclib('LRCLIB'),
  youtubeMusic('YouTube Music'),
  youtubeTranscript('YouTube transcript'),
  unison('Unison'),
  kugou('KuGou');

  const LyricsProvider(this.label);
  final String label;
}

class Lyrics {
  const Lyrics({required this.lines, required this.isSynced, required this.source, required this.raw});
  final List<LyricLine> lines;
  final bool isSynced;
  final String source;
  final String raw;

  int indexAt(Duration position) {
    if (!isSynced || lines.isEmpty || position < lines.first.start) return -1;
    var low = 0;
    var high = lines.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (lines[mid].start <= position) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low - 1;
  }
}

Lyrics? parseLyrics(String raw, {required String source, required bool synced}) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  if (RegExp(r'^(lyrics?\s+(not found|unavailable)|no lyrics( found)?|error)$', caseSensitive: false).hasMatch(text)) {
    return null;
  }
  if (text.contains('<tt') || text.contains('http://www.w3.org/ns/ttml')) {
    if (RegExp(r'<!DOCTYPE|<!ENTITY', caseSensitive: false).hasMatch(text)) return null;
    try {
      final document = XmlDocument.parse(text);
      final lines = <LyricLine>[];
      for (final element in document.descendants.whereType<XmlElement>().where((e) => e.name.local == 'p')) {
        final role = element.attributes.where((a) => a.name.local == 'role').map((a) => a.value).firstOrNull;
        if (role == 'x-translation' || role == 'x-roman') continue;
        final start = _parseTtmlTime(element.getAttribute('begin'));
        final words = _ttmlWords(element);
        final content = words.map((word) => word.text).join().trim();
        if (start != null && content.isNotEmpty) {
          lines.add(LyricLine(start, content, words: words.any((word) => word.start != null) ? words : const []));
        }
      }
      lines.sort((a, b) => a.start.compareTo(b.start));
      return lines.isEmpty ? null : Lyrics(lines: lines, isSynced: true, source: source, raw: text);
    } catch (_) {
      return null;
    }
  }
  final lines = <LyricLine>[];
  if (synced) {
    final stamp = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?\]');
    final offsetMatch = RegExp(r'\[offset:([+-]?\d+)\]', caseSensitive: false).firstMatch(text);
    final offset = int.tryParse(offsetMatch?.group(1) ?? '') ?? 0;
    for (final row in text.split('\n')) {
      final matches = stamp.allMatches(row).toList();
      final content = row.replaceAll(stamp, '').trim();
      if (content.isEmpty) continue;
      for (final match in matches) {
        final fraction = (match.group(3) ?? '').padRight(3, '0');
        final ms =
            (int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!)) * 1000 +
            (int.tryParse(fraction) ?? 0) +
            offset;
        final words = _enhancedLrcWords(content, offset);
        final plainText = words.isEmpty ? content : words.map((word) => word.text).join().trim();
        if (plainText.isNotEmpty) {
          lines.add(LyricLine(Duration(milliseconds: ms.clamp(0, 999999999)), plainText, words: words));
        }
      }
    }
    lines.sort((a, b) => a.start.compareTo(b.start));
  } else {
    for (final row in text.split('\n')) {
      if (row.trim().isNotEmpty) lines.add(LyricLine(Duration.zero, row.trim()));
    }
  }
  return lines.isEmpty ? null : Lyrics(lines: lines, isSynced: synced, source: source, raw: text);
}

List<LyricWord> _ttmlWords(XmlElement line) {
  final words = <LyricWord>[];
  void visit(XmlNode node, Duration? start, Duration? end) {
    if (node is XmlElement) {
      final role = node.attributes
          .where((attribute) => attribute.name.local == 'role')
          .map((attribute) => attribute.value)
          .firstOrNull;
      if (role == 'x-bg' || role == 'x-translation' || role == 'x-roman') return;
      if (node != line) {
        start = _parseTtmlTime(node.getAttribute('begin')) ?? start;
        end = _parseTtmlTime(node.getAttribute('end')) ?? end;
      }
      for (final child in node.children) {
        visit(child, start, end);
      }
    } else if (node is XmlText || node is XmlCDATA) {
      final text = node.value ?? '';
      if (text.isNotEmpty) words.add(LyricWord(text, start: start, end: end));
    }
  }

  visit(line, null, null);
  return words;
}

List<LyricWord> _enhancedLrcWords(String text, int offset) {
  final stamp = RegExp(r'<(\d{1,3}):(\d{2})(?:[.:](\d{1,3}))?>');
  final matches = stamp.allMatches(text).toList();
  if (matches.isEmpty) return const [];
  final words = <LyricWord>[];
  if (matches.first.start > 0) words.add(LyricWord(text.substring(0, matches.first.start)));
  for (var i = 0; i < matches.length; i++) {
    final match = matches[i];
    final fragment = text.substring(match.end, i + 1 < matches.length ? matches[i + 1].start : text.length);
    if (fragment.isEmpty) continue;
    final ms =
        (int.parse(match.group(1)!) * 60 + int.parse(match.group(2)!)) * 1000 +
        (int.tryParse((match.group(3) ?? '').padRight(3, '0')) ?? 0) +
        offset;
    words.add(LyricWord(fragment, start: Duration(milliseconds: ms.clamp(0, 999999999))));
  }
  return words;
}

Duration? _parseTtmlTime(String? value) {
  if (value == null) return null;
  if (value.endsWith('s')) {
    final seconds = double.tryParse(value.substring(0, value.length - 1));
    return seconds == null || seconds < 0 ? null : Duration(milliseconds: (seconds * 1000).round());
  }
  final parts = value.split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  final seconds = double.tryParse(parts.last);
  final minutes = int.tryParse(parts[parts.length - 2]);
  final hours = parts.length == 3 ? int.tryParse(parts.first) : 0;
  if (seconds == null || minutes == null || hours == null || seconds < 0 || minutes < 0 || hours < 0) return null;
  return Duration(milliseconds: (((hours * 60 + minutes) * 60 + seconds) * 1000).round());
}

final lyricsServiceProvider = Provider<LyricsService>((ref) => LyricsService());
final songLyricsProvider = FutureProvider.autoDispose.family<Lyrics?, SongDetail>(
  (ref, song) => ref.watch(lyricsServiceProvider).fetch(song),
);
final selectedLyricsProvider = StateProvider.autoDispose.family<Lyrics?, String>((ref, songId) => null);

class LyricsService {
  LyricsService({
    Dio? dio,
    Future<String?> Function(String)? youtubeLyrics,
    Future<String?> Function(String)? youtubeTranscript,
  }) : _dio =
           dio ??
           Dio(BaseOptions(connectTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 6))),
       _youtubeLyrics = youtubeLyrics ?? youtube.fetchPlainLyrics,
       _youtubeTranscript = youtubeTranscript ?? youtube.fetchTimedTranscript;

  final Dio _dio;
  final Future<String?> Function(String) _youtubeLyrics;
  final Future<String?> Function(String) _youtubeTranscript;

  Future<Lyrics?> fetch(SongDetail song, {LyricsProvider? provider}) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = 'lyrics_v1_${song.id}';
    final cached = prefs.getString(cacheKey);
    if (cached != null) {
      try {
        final map = jsonDecode(cached) as Map<String, dynamic>;
        final parsed = parseLyrics(
          map['text'] as String,
          source: map['source'] as String,
          synced: map['synced'] == true,
        );
        if (parsed != null && (provider == null || parsed.source == provider.label)) return parsed;
      } catch (_) {
        // Ignore invalid cached data and try the providers again.
      }
    }
    final writeCacheKey = provider == null ? cacheKey : null;

    final artist = song.primaryArtists.trim().isNotEmpty
        ? song.primaryArtists.trim()
        : song.contributors.all.map((artist) => artist.title.trim()).where((name) => name.isNotEmpty).join(', ');
    final duration = int.tryParse(song.duration ?? '');
    final album = song.albumName?.trim().isNotEmpty == true ? song.albumName!.trim() : song.album.trim();
    Map<String, dynamic>? plainCandidate;
    if ((provider == null || provider == LyricsProvider.lrclib) && song.title.trim().isNotEmpty && artist.isNotEmpty) {
      try {
        final response = await _dio.get(
          'https://lrclib.net/api/get',
          queryParameters: {
            'track_name': song.title,
            'artist_name': artist,
            if (album.isNotEmpty) 'album_name': album,
            if (duration != null && duration > 0) 'duration': duration,
          },
          options: Options(headers: {'User-Agent': 'Hivefy/1.0 (music player)'}),
        );
        if (response.data is Map) {
          final candidate = Map<String, dynamic>.from(response.data as Map);
          final result = await _fromLrclib(candidate, prefs, writeCacheKey, syncedOnly: false);
          if (result != null) return result;
          plainCandidate = candidate;
        }
      } catch (_) {}
      try {
        final response = await _dio.get(
          'https://lrclib.net/api/search',
          queryParameters: {'track_name': song.title, 'artist_name': artist},
          options: Options(headers: {'User-Agent': 'Hivefy/1.0 (music player)'}),
        );
        if (response.data is List) {
          final candidates = (response.data as List).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).where((
            item,
          ) {
            final candidateDuration = item['duration'] is num ? (item['duration'] as num).toDouble() : null;
            return duration != null &&
                duration > 0 &&
                candidateDuration != null &&
                (candidateDuration - duration).abs() <= 4;
          }).toList();
          candidates.sort(
            (a, b) => ((a['duration'] as num).toDouble() - duration!).abs().compareTo(
              ((b['duration'] as num).toDouble() - duration).abs(),
            ),
          );
          for (final candidate in candidates) {
            final result = await _fromLrclib(candidate, prefs, writeCacheKey, syncedOnly: true);
            if (result != null) return result;
          }
          if (plainCandidate == null && candidates.isNotEmpty) plainCandidate = candidates.first;
        }
      } catch (_) {}
    }
    if (plainCandidate != null) {
      final result = await _fromLrclib(plainCandidate, prefs, writeCacheKey, syncedOnly: false);
      if (result != null) return result;
    }
    if (song.ytVideoId.isNotEmpty) {
      if (provider == null || provider == LyricsProvider.youtubeMusic) {
        try {
          final text = await _youtubeLyrics(song.ytVideoId);
          if (text != null) {
            final result = await _save(text, 'YouTube Music', false, prefs, writeCacheKey);
            if (result != null) return result;
          }
        } catch (_) {}
      }
      if (provider == null || provider == LyricsProvider.youtubeTranscript) {
        try {
          final transcript = await _youtubeTranscript(song.ytVideoId);
          if (transcript != null) {
            final result = await _save(transcript, 'YouTube transcript', true, prefs, writeCacheKey);
            if (result != null) return result;
          }
        } catch (_) {}
      }
    }
    if (song.title.trim().isNotEmpty && artist.isNotEmpty) {
      if (provider == null || provider == LyricsProvider.unison) {
        final unison = await _fetchUnison(song.title, artist, album, duration, prefs, writeCacheKey);
        if (unison != null) return unison;
      }
      if (provider == null || provider == LyricsProvider.kugou) {
        final kugou = await _fetchKugou(song.title, artist, album, duration, prefs, writeCacheKey);
        if (kugou != null) return kugou;
      }
    }
    return null;
  }

  Future<Lyrics?> _fetchUnison(
    String title,
    String artist,
    String album,
    int? duration,
    SharedPreferences prefs,
    String? key,
  ) async {
    try {
      final response = await _dio.get(
        'https://unison.boidu.dev/lyrics',
        queryParameters: {
          'song': title,
          'artist': artist,
          if (album.isNotEmpty) 'album': album,
          if (duration != null && duration > 0) 'duration': duration,
        },
      );
      final body = response.data;
      if (body is! Map || body['success'] != true || body['data'] is! Map) return null;
      final data = body['data'] as Map;
      final text = data['lyrics'];
      if (text is! String || text.trim().isEmpty) return null;
      final format = '${data['format'] ?? ''}'.toLowerCase();
      final syncType = '${data['syncType'] ?? ''}'.toLowerCase();
      return await _save(
        text,
        'Unison',
        format == 'ttml' || format == 'lrc' || (syncType.isNotEmpty && syncType != 'plain'),
        prefs,
        key,
      );
    } catch (_) {
      return null;
    }
  }

  Future<Lyrics?> _fetchKugou(
    String title,
    String artist,
    String album,
    int? duration,
    SharedPreferences prefs,
    String? key,
  ) async {
    try {
      final search = await _dio.get(
        'https://mobileservice.kugou.com/api/v3/search/song',
        queryParameters: {
          'version': 9108,
          'plat': 0,
          'pagesize': 8,
          'showtype': 0,
          'keyword': '$title - $artist $album',
        },
      );
      final body = search.data;
      if (body is! Map || body['data'] is! Map || body['data']['info'] is! List || duration == null || duration <= 0) {
        return null;
      }
      final tracks = (body['data']['info'] as List).whereType<Map>().where((item) {
        final seconds = num.tryParse('${item['duration'] ?? ''}');
        return seconds != null && (seconds - duration).abs() <= 8 && '${item['hash'] ?? ''}'.isNotEmpty;
      }).toList();
      tracks.sort(
        (a, b) => (num.parse('${a['duration']}') - duration).abs().compareTo(
          (num.parse('${b['duration']}') - duration).abs(),
        ),
      );
      for (final track in tracks) {
        final lookup = await _dio.get(
          'https://lyrics.kugou.com/search',
          queryParameters: {'ver': 1, 'man': 'yes', 'client': 'pc', 'hash': track['hash']},
        );
        final candidates = lookup.data is Map ? (lookup.data as Map)['candidates'] : null;
        if (candidates is! List) continue;
        for (final candidate in candidates.whereType<Map>()) {
          if (candidate['id'] == null || candidate['accesskey'] == null) continue;
          final response = await _dio.get(
            'https://lyrics.kugou.com/download',
            queryParameters: {
              'fmt': 'lrc',
              'charset': 'utf8',
              'client': 'pc',
              'ver': 1,
              'id': candidate['id'],
              'accesskey': candidate['accesskey'],
            },
          );
          final encoded = response.data is Map ? (response.data as Map)['content'] : null;
          if (encoded is! String) continue;
          final text = utf8.decode(base64.decode(encoded));
          final result = await _save(text, 'KuGou', true, prefs, key);
          if (result != null) return result;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<Lyrics?> _fromLrclib(
    Map<String, dynamic> item,
    SharedPreferences prefs,
    String? key, {
    required bool syncedOnly,
  }) async {
    if (item['instrumental'] == true) return _save('♪ Instrumental ♪', 'LRCLIB', false, prefs, key);
    final synced = item['syncedLyrics'];
    if (synced is String) {
      final result = await _save(synced, 'LRCLIB', true, prefs, key);
      if (result != null) return result;
    }
    final plain = item['plainLyrics'];
    return !syncedOnly && plain is String ? _save(plain, 'LRCLIB', false, prefs, key) : null;
  }

  Future<void> saveSelection(SongDetail song, Lyrics lyrics) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'lyrics_v1_${song.id}',
      jsonEncode({'text': lyrics.raw, 'source': lyrics.source, 'synced': lyrics.isSynced}),
    );
  }

  Future<Lyrics?> _save(String text, String source, bool synced, SharedPreferences prefs, String? key) async {
    final lyrics = parseLyrics(text, source: source, synced: synced);
    if (lyrics != null && key != null) {
      await prefs.setString(key, jsonEncode({'text': text, 'source': source, 'synced': synced}));
    }
    return lyrics;
  }
}
