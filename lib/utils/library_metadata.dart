import '../models/datamodel.dart';
import 'playlist_subtitle.dart';

String albumArtistName(Album album) {
  bool usable(String value) =>
      value.trim().isNotEmpty && !{'album', 'single', 'ep', 'unknown artist'}.contains(value.trim().toLowerCase());
  final names = album.artists.map((artist) => artist.title.trim()).where(usable).toSet();
  if (names.isNotEmpty) return names.join(', ');
  if (usable(album.artist)) return album.artist.trim();
  final songArtists = album.songs.map((song) => song.primaryArtists.trim()).where(usable).toSet();
  return songArtists.length == 1 ? songArtists.single : '';
}

String playlistLibrarySubtitle(Playlist playlist) {
  final description = cleanPlaylistSubtitle(playlist.summary.isNotEmpty ? playlist.summary : playlist.description);
  if (description.isNotEmpty) return description;
  final artists = playlist.artists.map((artist) => artist.title.trim()).where((name) => name.isNotEmpty).join(', ');
  final cleaned = cleanPlaylistSubtitle(artists);
  return cleaned.isEmpty ? 'Playlist' : cleaned;
}
