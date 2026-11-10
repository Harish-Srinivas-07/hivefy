import '../models/datamodel.dart';
import 'youtube.dart';

String _normalizedName(String value) => value
    .trim()
    .replaceFirst(RegExp(r'\s*-\s*topic\s*$', caseSensitive: false), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .toLowerCase();

String _primaryName(SongDetail song) {
  for (final artist in song.contributors.primary) {
    if (artist.title.trim().isNotEmpty) return artist.title.trim();
  }
  return song.primaryArtists.split(RegExp(r'\s*(?:,| • )\s*')).first.trim();
}

/// Resolves only a known primary contributor or an unambiguous exact name match.
Future<ArtistDetails?> resolveSongArtist(SongDetail song, YoutubeAPI api) async {
  final name = _primaryName(song);
  Artist? selected;
  if (name.isNotEmpty) {
    // Contributor lists can contain featured/secondary artists before the
    // primary artist with a usable channel ID. Pair the channel ID with the
    // name shown for the primary artist so the full-player image cannot come
    // from a different contributor.
    for (final artist in song.contributors.primary) {
      if (artist.id.trim().isNotEmpty && _normalizedName(artist.title) == _normalizedName(name)) {
        selected = artist;
        break;
      }
    }
  }
  if (selected == null && name.isNotEmpty) {
    for (final artist in song.contributors.all) {
      if (artist.id.trim().isNotEmpty && _normalizedName(artist.title) == _normalizedName(name)) {
        selected = artist;
        break;
      }
    }
  }
  if (selected == null && name.isEmpty && song.contributors.all.length == 1) {
    final artist = song.contributors.all.single;
    if (artist.id.trim().isNotEmpty) selected = artist;
  }

  Future<Artist?> findMatch({String? id}) async {
    if (name.isEmpty) return null;
    final search = await api.searchArtists(query: name);
    final matches = (search?.results ?? [])
        .where(
          (artist) =>
              artist.id.isNotEmpty &&
              _normalizedName(artist.title) == _normalizedName(name) &&
              (id == null || artist.id == id),
        )
        .toList();
    return matches.length == 1 ? matches.single : null;
  }

  selected ??= await findMatch();
  if (selected == null) return null;
  final details = await api.fetchArtistDetailsById(artistId: selected.id);
  if (details == null) return null;
  final expected = selected.title.trim().isNotEmpty ? selected.title : name;
  if (expected.isNotEmpty &&
      details.title.trim().isNotEmpty &&
      _normalizedName(details.title) != _normalizedName(expected)) {
    return null;
  }

  if (details.images.any((image) => image.url.trim().isNotEmpty)) return details;
  Artist? matchingImage = selected.images.any((image) => image.url.trim().isNotEmpty) ? selected : null;
  matchingImage ??= await findMatch(id: selected.id);
  if (matchingImage == null || matchingImage.images.every((image) => image.url.trim().isEmpty)) return details;
  final data = ArtistDetails.artistDetailsToJson(details);
  data['image'] = matchingImage.images.map(SourceUrl.srcToJson).toList();
  return ArtistDetails.fromJson(data);
}

String songArtistLookupKey(SongDetail song) {
  String listKey(List<Artist> artists) => artists.map((artist) => '${artist.id}:${artist.title}').join('|');
  return '${song.id}\n${song.primaryArtists}\n${listKey(song.contributors.primary)}\n${listKey(song.contributors.all)}';
}
