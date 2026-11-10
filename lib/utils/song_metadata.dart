import '../models/datamodel.dart';

/// The artist and album line shared by both player sizes.
String playerSongSubtitle(SongDetail song) {
  final names = song.contributors.all.map((artist) => artist.title.trim()).where((name) => name.isNotEmpty).toSet();
  final primaryArtists = song.primaryArtists.trim();
  final artist = names.isNotEmpty
      ? names.join(', ')
      : primaryArtists.isNotEmpty
      ? primaryArtists
      : song.singers.trim();
  final album = song.albumName?.trim().isNotEmpty == true ? song.albumName!.trim() : song.album.trim();
  return [artist, album].where((part) => part.isNotEmpty).join(' • ');
}
