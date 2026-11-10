import 'package:flutter/material.dart';

import '../models/datamodel.dart';
import '../utils/library_metadata.dart';
import '../utils/song_metadata.dart';
import 'shimmers.dart';

class MediaMenuHeader extends StatelessWidget {
  const MediaMenuHeader({super.key, required this.item});

  final SongMediaItem item;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CacheNetWorkImg(
        url: item.images.isNotEmpty ? item.images.last.url : '',
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        borderRadius: BorderRadius.circular(8),
      ),
      title: Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
      ),
      subtitle: Text(
        _getSubtitle(item),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    );
  }
}

String _getSubtitle(SongMediaItem item) {
  if (item is SongDetail) {
    final subtitle = playerSongSubtitle(item);
    if (subtitle.isNotEmpty) return subtitle;
    return item.singers.trim();
  } else if (item is Album) {
    return item.artist.isNotEmpty ? item.artist : 'Album';
  } else if (item is Playlist) {
    final subtitle = playlistLibrarySubtitle(item);
    if (subtitle != 'Playlist') return subtitle;

    final songArtists = item.songs
        .expand((song) {
          final contributors = song.contributors.all
              .map((artist) => artist.title.trim())
              .where((name) => name.isNotEmpty);
          final fallbackArtists = song.primaryArtists.trim().isNotEmpty ? song.primaryArtists : song.singers;
          return contributors.isNotEmpty ? contributors : fallbackArtists.split(',').map((name) => name.trim());
        })
        .where((name) => name.isNotEmpty)
        .toSet();
    if (songArtists.isNotEmpty) return songArtists.join(', ');

    final songCount = item.songCount ?? (item.songs.isNotEmpty ? item.songs.length : null);
    if (songCount != null) return '$songCount ${songCount == 1 ? 'song' : 'songs'}';
    return item.language.trim().isNotEmpty ? item.language.trim() : 'Playlist';
  }
  return '';
}
