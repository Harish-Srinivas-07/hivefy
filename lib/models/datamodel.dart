import 'package:flutter/material.dart';
import 'package:html_unescape/html_unescape.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database.dart';

final unescape = HtmlUnescape();

/// Base class for reusable common fields
abstract class SongMediaItem {
  final String id;
  final String title;
  final String type;
  final String url;
  final List<SourceUrl> images;
  final String description;
  final String language;

  SongMediaItem({
    required this.id,
    required this.title,
    required this.type,
    required this.url,
    required this.images,
    this.description = '',
    this.language = '',
  });
}

/// Image / Source holder
class SourceUrl {
  final String quality;
  final String url;

  SourceUrl({required this.quality, required this.url});

  factory SourceUrl.fromJson(Map<String, dynamic> json) => SourceUrl(
    quality: json['quality']?.toString() ?? '',
    url: json['url'] ?? '',
  );
  // -------- JSON serializers (mirror your fromJson shapes)

  static Map<String, dynamic> srcToJson(SourceUrl s) => {
    'quality': s.quality,
    'url': s.url,
  };
}

/// Playlist model
class Playlist extends SongMediaItem {
  final int? songCount;
  final bool explicitContent;
  final List<SongDetail> songs;
  final List<Artist> artists;

  Playlist({
    required super.id,
    required super.title,
    required super.type,
    required super.url,
    required super.images,
    super.description,
    super.language,
    this.songCount,
    this.explicitContent = false,
    this.songs = const [],
    this.artists = const [],
  });
  @override
  String toString() {
    return 'Playlist(id: $id, title: $title, type: $type, url: $url, images: $images, description: $description, language: $language, songCount: $songCount, explicitContent: $explicitContent, songs: $songs, artists: $artists)';
  }

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id']?.toString() ?? '',
      title: unescape.convert(json['title'] ?? json['name'] ?? ''),
      type: unescape.convert(json['type']?.toString() ?? ''),
      images:
          (json['image'] as List<dynamic>? ?? [])
              .map((e) => SourceUrl.fromJson(e))
              .toList(),
      url: json['url'] ?? '',
      songCount: json['songCount'],
      language: json['language'] ?? '',
      explicitContent: json['explicitContent'] ?? false,
      description: unescape.convert(json['description'] ?? ''),
      songs:
          (json['songs'] as List<dynamic>? ?? [])
              .map((e) => SongDetail.fromJson(e))
              .toList(),
      artists:
          (json['artists'] as List<dynamic>? ?? [])
              .map((e) => Artist.fromJson(e))
              .toList(),
    );
  }

  static Map<String, dynamic> playlistToJson(Playlist p) => {
    'id': p.id,
    'title': p.title,
    'name': p.title,
    'type': p.type,
    'url': p.url,
    'image': p.images.map(SourceUrl.srcToJson).toList(),
    'description': p.description,
    'language': p.language,
    'songCount': p.songCount,
    'explicitContent': p.explicitContent,
    'songs': p.songs.map(SongDetail.songDetailToJson).toList(),
    'artists': p.artists.map(Artist.artistToJson).toList(),
  };
}

/// Song (lightweight for search/listing)
class Song extends SongMediaItem {
  final String album;
  final String primaryArtists;
  final String singers;

  Song({
    required super.id,
    required super.title,
    required super.type,
    required super.url,
    required super.images,
    super.description,
    super.language,
    this.album = '',
    this.primaryArtists = '',
    this.singers = '',
  });

  factory Song.fromJson(Map<String, dynamic> json) => Song(
    id: json['id']?.toString() ?? '',
    // some endpoints use "title", others use "name"
    title: unescape.convert(json['title'] ?? json['name'] ?? ''),
    type: unescape.convert(json['type']?.toString() ?? ''),
    url: json['url'] ?? '',
    images:
        (json['image'] as List<dynamic>? ?? [])
            .map((e) => SourceUrl.fromJson(e))
            .toList(),
    description: unescape.convert(json['description'] ?? ''),
    album: unescape.convert(
      json['album'] is String
          ? (json['album'] ?? '')
          : (json['album']?['name'] ?? ''),
    ),
    primaryArtists: unescape.convert(json['primaryArtists'] ?? ''),
    singers: unescape.convert(json['singers'] ?? ''),
    language: json['language']?.toString() ?? '',
  );

  @override
  String toString() {
    return 'Song(id: $id, title: $title, type: $type, url: $url, album: $album, primaryArtists: $primaryArtists, singers: $singers, language: $language)';
  }
}

/// Contributors group used by SongDetail (added)
class Contributors {
  final List<Artist> primary;
  final List<Artist> featured;
  final List<Artist> all;

  const Contributors({
    this.primary = const [],
    this.featured = const [],
    this.all = const [],
  });

  factory Contributors.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const Contributors();
    List<Artist> parse(String key) =>
        (json[key] as List<dynamic>? ?? [])
            .map((e) => Artist.fromJson(e))
            .toList();
    return Contributors(
      primary: parse('primary'),
      featured: parse('featured'),
      all: parse('all'),
    );
  }
}

/// SongDetail (full detail with metadata & download links)
class SongDetail extends Song {
  final String? year;
  final String? releaseDate;
  final String? duration;
  final String? label;
  final String? albumName;
  final bool explicitContent;
  final List<SourceUrl> downloadUrls;

  // Contributors (primary/featured/all)
  final Contributors contributors;

  SongDetail({
    required super.id,
    required super.title,
    required super.type,
    required super.url,
    required super.images,
    super.description,
    super.language,
    super.album,
    super.primaryArtists,
    super.singers,
    this.year,
    this.releaseDate,
    this.duration,
    this.label,
    this.albumName,
    this.explicitContent = false,
    this.downloadUrls = const [],
    this.contributors = const Contributors(),
  });

  factory SongDetail.fromJson(Map<String, dynamic> json) {
    // Parse images
    List<SourceUrl> images = [];
    if (json['image'] is List) {
      images =
          (json['image'] as List).map((e) => SourceUrl.fromJson(e)).toList();
    }

    // Parse download URLs
    List<SourceUrl> downloads = [];
    if (json['downloadUrl'] is List) {
      downloads =
          (json['downloadUrl'] as List)
              .map((e) => SourceUrl.fromJson(e))
              .toList();
    } else if (json['media_url'] != null) {
      downloads = [SourceUrl(url: json['media_url'], quality: 'default')];
    }

    // Parse album name
    String? albumName;
    if (json['album'] is Map<String, dynamic>) {
      albumName = json['album']['name']?.toString();
    }

    // Parse contributors
    Contributors contributors = const Contributors();
    if (json['artists'] is Map<String, dynamic>) {
      contributors = Contributors.fromJson(json['artists']);
    }

    return SongDetail(
      id: json['id']?.toString() ?? '',
      title: unescape.convert(json['name'] ?? json['title'] ?? ''),
      type: json['type']?.toString() ?? '',
      url: json['url'] ?? '',
      images: images,
      description: unescape.convert(json['description'] ?? ''),
      language: json['language']?.toString() ?? '',
      album: unescape.convert(albumName ?? ''),
      primaryArtists: unescape.convert(json['primaryArtists'] ?? ''),
      singers: unescape.convert(json['singers'] ?? ''),
      year: json['year']?.toString(),
      releaseDate: json['releaseDate']?.toString(),
      duration: json['duration']?.toString(),
      label: unescape.convert(json['label']?.toString() ?? ''),
      albumName: unescape.convert(albumName ?? ''),
      explicitContent: json['explicitContent'] == true,
      downloadUrls: downloads,
      contributors: contributors,
    );
  }

  static Map<String, dynamic> songDetailToJson(SongDetail s) => {
    'id': s.id,
    'title': s.title,
    'name': s.title,
    'type': s.type,
    'url': s.url,
    'description': s.description,
    'language': s.language,
    'album': {'name': s.albumName ?? s.album},
    'primaryArtists': s.primaryArtists,
    'singers': s.singers,
    'year': s.year,
    'releaseDate': s.releaseDate,
    'duration': s.duration,
    'label': s.label,
    'albumName': s.albumName,
    'explicitContent': s.explicitContent,
    'image': s.images.map(SourceUrl.srcToJson).toList(),
    'downloadUrl': s.downloadUrls.map(SourceUrl.srcToJson).toList(),
    'artists': {
      'primary': s.contributors.primary.map(Artist.artistToJson).toList(),
      'featured': s.contributors.featured.map(Artist.artistToJson).toList(),
      'all': s.contributors.all.map(Artist.artistToJson).toList(),
    },
  };

  /// Converts duration in seconds to "MM:SS" format
  String getHumanReadableDuration() {
    if (duration != null) {
      int seconds = int.tryParse(duration ?? '') ?? 0;
      int minutes = seconds ~/ 60;
      seconds %= 60;
      return "$minutes:${seconds.toString().padLeft(2, '0')}";
    }
    return 'Unknown duration';
  }

  @override
  String toString() =>
      'SongDetail(id: $id, title: $title, year: $year, album: $albumName, duration: $duration, explicit: $explicitContent, downloadUrls: ${downloadUrls.length})';
}

/// Album model (extended to cover singles/topAlbums payloads)
class Album extends SongMediaItem {
  final String artist;
  final String year;

  /// Old: just song IDs
  final List<String> songIds;

  /// Use full SongDetail objects
  final List<SongDetail> songs;

  final String label;
  final bool explicitContent;
  final List<Artist> artists; // usually primary artists
  final List<SourceUrl> downloadUrls;

  Album({
    required super.id,
    required super.title,
    required super.type,
    required super.url,
    required super.images,
    super.description,
    super.language,
    this.artist = '',
    this.year = '',
    this.songIds = const [],
    this.songs = const [],
    this.label = '',
    this.explicitContent = false,
    this.artists = const [],
    this.downloadUrls = const [],
  });

  @override
  String toString() {
    return 'Album(id: $id, title: $title, artist: $artist, year: $year, '
        'songIds: $songIds, songs: $songs, label: $label, '
        'explicitContent: $explicitContent, artists: $artists, '
        'downloadUrls: $downloadUrls)';
  }

  factory Album.fromJson(Map<String, dynamic> json) {
    // songIds (legacy support)
    List<String> songIds = [];
    if (json['songIds'] is List) {
      songIds = (json['songIds'] as List).map((e) => e.toString()).toList();
    } else if (json['songIds'] is String) {
      songIds =
          (json['songIds'] as String).split(',').map((e) => e.trim()).toList();
    }

    // full songs (SongDetail)
    final List<SongDetail> parsedSongs =
        (json['songs'] as List<dynamic>? ?? [])
            .map((e) => SongDetail.fromJson(e))
            .toList();

    final List<Artist> primaryArtists =
        (json['artists']?['primary'] as List<dynamic>? ?? [])
            .map((e) => Artist.fromJson(e))
            .toList();

    // fallback artist string for older shapes OR join primary artists when present
    final fallbackArtist = unescape.convert(json['artist']?.toString() ?? '');
    final joinedPrimary =
        primaryArtists.isNotEmpty
            ? primaryArtists.map((a) => a.title).join(', ')
            : '';

    return Album(
      id: json['id']?.toString() ?? '',
      title: unescape.convert(json['title'] ?? json['name'] ?? ''),
      type: unescape.convert(json['type']?.toString() ?? ''),
      url: json['url'] ?? '',
      images:
          (json['image'] as List<dynamic>? ?? [])
              .map((e) => SourceUrl.fromJson(e))
              .toList(),
      description: unescape.convert(json['description'] ?? ''),
      language: json['language']?.toString() ?? '',
      artist: (joinedPrimary.isNotEmpty ? joinedPrimary : fallbackArtist),
      year: json['year']?.toString() ?? '',
      songIds: songIds,
      songs: parsedSongs,
      label: unescape.convert(json['label']?.toString() ?? ''),
      explicitContent: json['explicitContent'] == true,
      artists: primaryArtists,
      downloadUrls:
          (json['downloadUrl'] as List<dynamic>? ?? [])
              .map((e) => SourceUrl.fromJson(e))
              .toList(),
    );
  }

  static Map<String, dynamic> albumToJson(Album a) => {
    'id': a.id,
    'title': a.title,
    'name': a.title,
    'type': a.type,
    'url': a.url,
    'image': a.images.map(SourceUrl.srcToJson).toList(),
    'description': a.description,
    'language': a.language,
    'artist': a.artist,
    'year': a.year,
    'songIds': a.songIds,
    'songs': a.songs.map(SongDetail.songDetailToJson).toList(),
    'label': a.label,
    'explicitContent': a.explicitContent,
    'artists': {'primary': a.artists.map(Artist.artistToJson).toList()},
    'downloadUrl': a.downloadUrls.map(SourceUrl.srcToJson).toList(),
  };
}

/// Artist model (tweak: tolerate "name")
class Artist extends SongMediaItem {
  final int position;

  Artist({
    required super.id,
    required super.title,
    required super.type,
    required super.url,
    required super.images,
    super.description,
    super.language,
    this.position = 0,
  });

  factory Artist.fromJson(Map<String, dynamic> json) => Artist(
    id: json['id']?.toString() ?? '',
    title: unescape.convert(json['title'] ?? json['name'] ?? ''),
    type: unescape.convert(json['type']?.toString() ?? ''),
    url: json['url'] ?? '',
    images:
        (json['image'] as List<dynamic>? ?? [])
            .map((e) => SourceUrl.fromJson(e))
            .toList(),
    description: unescape.convert(json['description'] ?? ''),
    position:
        json['position'] is int
            ? json['position']
            : (int.tryParse('${json['position']}') ?? 0),
  );

  static Map<String, dynamic> artistToJson(Artist a) => {
    'id': a.id,
    'title': a.title,
    'name': a.title, // tolerate both keys
    'type': a.type,
    'url': a.url,
    'image': a.images.map(SourceUrl.srcToJson).toList(),
    'description': a.description,
    'position': a.position,
    'language': a.language,
  };
}

/// Global search response
class GlobalSearch {
  final SearchResult<Song> songs;
  final SearchResult<Album> albums;
  final SearchResult<Artist> artists;
  final SearchResult<Playlist> playlists;

  GlobalSearch({
    required this.songs,
    required this.albums,
    required this.artists,
    required this.playlists,
  });

  factory GlobalSearch.fromJson(Map<String, dynamic> json) {
    return GlobalSearch(
      songs: SearchResult<Song>.fromJson(
        json['songs'],
        (item) => Song.fromJson(item),
      ),
      albums: SearchResult<Album>.fromJson(
        json['albums'],
        (item) => Album.fromJson(item),
      ),
      artists: SearchResult<Artist>.fromJson(
        json['artists'],
        (item) => Artist.fromJson(item),
      ),
      playlists: SearchResult<Playlist>.fromJson(
        json['playlists'],
        (item) => Playlist.fromJson(item),
      ),
    );
  }
  @override
  String toString() {
    return 'GlobalSearch(songs: $songs, albums: $albums, artists: $artists, playlists: $playlists)';
  }
}

class SearchResult<T> {
  final int total;
  final List<T> results;

  SearchResult({required this.total, required this.results});

  factory SearchResult.fromJson(
    Map<String, dynamic>? json,
    T Function(Map<String, dynamic>) fromJsonT,
  ) {
    if (json == null) {
      return SearchResult(total: 0, results: []);
    }

    return SearchResult(
      total: json['total'] ?? 0,
      results:
          (json['results'] as List<dynamic>? ?? [])
              .map((e) => fromJsonT(e as Map<String, dynamic>))
              .toList(),
    );
  }
}

// Artist Models
class ArtistDetails extends Artist {
  final int? followerCount;
  final int? fanCount;
  final bool? isVerified;

  final String dominantLanguage;
  final String dominantType;
  final List<String> bio; // API shows array
  final String dob;

  final String fb;
  final String twitter;
  final String wiki;

  final List<String> availableLanguages;
  final bool isRadioPresent;

  final List<SongDetail> topSongs;
  final List<Album> topAlbums;
  final List<Album> singles;
  final List<Artist> similarArtists;

  ArtistDetails({
    required super.id,
    required super.title,
    required super.type,
    required super.url,
    required super.images,
    super.description,
    super.language,
    super.position,
    this.followerCount,
    this.fanCount,
    this.isVerified,
    this.dominantLanguage = '',
    this.dominantType = '',
    this.bio = const [],
    this.dob = '',
    this.fb = '',
    this.twitter = '',
    this.wiki = '',
    this.availableLanguages = const [],
    this.isRadioPresent = false,
    this.topSongs = const [],
    this.topAlbums = const [],
    this.singles = const [],
    this.similarArtists = const [],
  });

  factory ArtistDetails.fromJson(Map<String, dynamic> json) {
    final List<SongDetail> topSongs =
        (json['topSongs'] as List<dynamic>? ?? [])
            .map((e) => SongDetail.fromJson(e))
            .toList();

    final List<Album> topAlbums =
        (json['topAlbums'] as List<dynamic>? ?? [])
            .map((e) => Album.fromJson(e))
            .toList();

    final List<Album> singles =
        (json['singles'] as List<dynamic>? ?? [])
            .map((e) => Album.fromJson(e))
            .toList();

    final List<Artist> similar =
        (json['similarArtists'] as List<dynamic>? ?? [])
            .map((e) => Artist.fromJson(e))
            .toList();

    int? asInt(dynamic v) => v == null ? null : int.tryParse(v.toString());

    return ArtistDetails(
      id: json['id']?.toString() ?? '',
      title: unescape.convert(json['name'] ?? json['title'] ?? ''),
      type: unescape.convert(json['type']?.toString() ?? 'artist'),
      url: json['url'] ?? '',
      images:
          (json['image'] as List<dynamic>? ?? [])
              .map((e) => SourceUrl.fromJson(e))
              .toList(),
      followerCount: asInt(json['followerCount']),
      fanCount: asInt(json['fanCount']),
      isVerified: json['isVerified'] as bool?,
      dominantLanguage: json['dominantLanguage']?.toString() ?? '',
      dominantType: json['dominantType']?.toString() ?? '',
      bio:
          (json['bio'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
      dob: json['dob']?.toString() ?? '',
      fb: json['fb']?.toString() ?? '',
      twitter: json['twitter']?.toString() ?? '',
      wiki: json['wiki']?.toString() ?? '',
      availableLanguages:
          (json['availableLanguages'] as List<dynamic>? ?? [])
              .map((e) => e.toString())
              .toList(),
      isRadioPresent: json['isRadioPresent'] == true,
      language: json['dominantLanguage']?.toString() ?? '',
      topSongs: topSongs,
      topAlbums: topAlbums,
      singles: singles,
      similarArtists: similar,
    );
  }

  static Map<String, dynamic> artistDetailsToJson(ArtistDetails a) => {
    'id': a.id,
    'title': a.title,
    'name': a.title,
    'type': a.type,
    'url': a.url,
    'image': a.images.map(SourceUrl.srcToJson).toList(),
    'description': a.description,
    'language': a.language,
    'position': a.position,
    'followerCount': a.followerCount,
    'fanCount': a.fanCount,
    'isVerified': a.isVerified,
    'dominantLanguage': a.dominantLanguage,
    'dominantType': a.dominantType,
    'bio': a.bio,
    'dob': a.dob,
    'fb': a.fb,
    'twitter': a.twitter,
    'wiki': a.wiki,
    'availableLanguages': a.availableLanguages,
    'isRadioPresent': a.isRadioPresent,
    'topSongs': a.topSongs.map(SongDetail.songDetailToJson).toList(),
    'topAlbums': a.topAlbums.map(Album.albumToJson).toList(),
    'singles': a.singles.map(Album.albumToJson).toList(),
    'similarArtists': a.similarArtists.map(Artist.artistToJson).toList(),
  };

  @override
  String toString() {
    return 'ArtistDetails('
        'id: $id, '
        'title: $title, '
        'type: $type, '
        'url: $url, '
        'followerCount: $followerCount, '
        'fanCount: $fanCount, '
        'isVerified: $isVerified, '
        'dominantLanguage: $dominantLanguage, '
        'dominantType: $dominantType, '
        'bio: ${bio.join(", ")}, '
        'dob: $dob, '
        'topSongs: ${topSongs.length}, '
        'topAlbums: ${topAlbums.length}, '
        'singles: ${singles.length}, '
        'similarArtists: ${similarArtists.length}'
        ')';
  }
}

class ArtistSongsResponse {
  final int total;
  final List<SongDetail> songs;

  ArtistSongsResponse({required this.total, required this.songs});

  factory ArtistSongsResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? {};
    final songs =
        (data['songs'] as List<dynamic>? ?? [])
            .map((e) => SongDetail.fromJson(e as Map<String, dynamic>))
            .toList();
    final total =
        int.tryParse('${data['total'] ?? songs.length}') ?? songs.length;
    return ArtistSongsResponse(total: total, songs: songs);
  }
}

// SearchPlaylist class
class SearchPlaylistsResponse {
  final int total;
  final int start;
  final List<Playlist> results;

  SearchPlaylistsResponse({
    required this.total,
    required this.start,
    required this.results,
  });

  factory SearchPlaylistsResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? {};
    final results =
        (data['results'] as List<dynamic>? ?? [])
            .map((e) => Playlist.fromJson(e as Map<String, dynamic>))
            .toList();
    return SearchPlaylistsResponse(
      total:
          int.tryParse('${data['total'] ?? results.length}') ?? results.length,
      start: int.tryParse('${data['start'] ?? 0}') ?? 0,
      results: results,
    );
  }
}

class SearchArtistsResponse {
  final int total;
  final int start;
  final List<Artist> results;

  SearchArtistsResponse({
    required this.total,
    required this.start,
    required this.results,
  });

  factory SearchArtistsResponse.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? {};
    final results =
        (data['results'] as List<dynamic>? ?? [])
            .map((e) => Artist.fromJson(e as Map<String, dynamic>))
            .toList();
    return SearchArtistsResponse(
      total:
          int.tryParse('${data['total'] ?? results.length}') ?? results.length,
      start: int.tryParse('${data['start'] ?? 0}') ?? 0,
      results: results,
    );
  }
}

// last queue store
class LastQueueData {
  final List<SongDetail> songs;
  final int currentIndex;

  const LastQueueData({required this.songs, required this.currentIndex});

  bool get isEmpty => songs.isEmpty;
  bool get isNotEmpty => songs.isNotEmpty;

  @override
  String toString() =>
      'LastQueueData(songs: ${songs.length}, currentIndex: $currentIndex)';
}

/// Handles persistence of the last played queue
class LastQueueStorage {
  static const _keySongs = 'last_queue';
  static const _keyIndex = 'last_queue_index';

  /// Save the queue (only song IDs) and current index
  static Future<void> save(
    List<SongDetail> queue, {
    int currentIndex = 0,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final songIds = queue.map((s) => s.id).toList();
    await prefs.setStringList(_keySongs, songIds);
    await prefs.setInt(_keyIndex, currentIndex);

    debugPrint(
      '[LastQueueStorage] Saved ${songIds.length} songs (index: $currentIndex)',
    );
  }

  /// Load the previously saved queue from SharedPreferences
  static Future<LastQueueData?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_keySongs);
    final idx = prefs.getInt(_keyIndex) ?? 0;

    if (ids == null || ids.isEmpty) {
      debugPrint('[LastQueueStorage] No saved queue found');
      return null;
    }

    // Fetch full song details from local DB

    final songs =
        (await Future.wait(
          ids.map(AppDatabase.getSong),
        )).whereType<SongDetail>().toList();

    if (songs.isEmpty) {
      debugPrint('[LastQueueStorage] All saved song IDs missing in DB');
      return null;
    }

    final safeIndex = idx.clamp(0, songs.length - 1);
    final result = LastQueueData(songs: songs, currentIndex: safeIndex);

    debugPrint(
      '[LastQueueStorage] Loaded ${songs.length} songs (index: $safeIndex)',
    );

    return result;
  }

  /// Clear the last queue
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keySongs);
    await prefs.remove(_keyIndex);
    debugPrint('[LastQueueStorage] Cleared stored queue');
  }
}
