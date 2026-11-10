import '../models/datamodel.dart';

String cleanPlaylistSubtitle(String subtitle) => subtitle
    .split('•')
    .map((part) => part.trim())
    .where((part) => part.isNotEmpty && part.toLowerCase() != 'youtube music')
    .join(' • ');

String songCountLabel(int count) => count == 0 ? 'No songs' : '$count ${count == 1 ? 'song' : 'songs'}';

String homePlaylistSubtitle(Playlist playlist) {
  final count = playlist.songCount;
  final hasCount = count != null && count >= 0;
  final description = cleanPlaylistSubtitle(playlist.summary.isNotEmpty ? playlist.summary : playlist.description);
  final details = description.isNotEmpty
      ? description
      : cleanPlaylistSubtitle(playlist.artists.isNotEmpty ? playlist.artists.first.title : '');
  final parts = details
      .split(' • ')
      .where((part) {
        if (part.isEmpty) return false;
        if (!hasCount) return true;
        return !RegExp(r'^(?:\d[\d,]*(?:\s+songs?)?|no songs)$', caseSensitive: false).hasMatch(part);
      })
      .map((part) => RegExp(r'^0\s+songs?$', caseSensitive: false).hasMatch(part) ? 'No songs' : part);
  final subtitle = [if (hasCount) songCountLabel(count), ...parts].join(' • ');
  return subtitle.isEmpty ? 'Playlist' : subtitle;
}
