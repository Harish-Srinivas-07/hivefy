// lib\components\showmenu.dart
import 'dart:async';
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:share_plus/share_plus.dart';

import '../models/database.dart';
import '../models/datamodel.dart';
import '../services/audiohandler.dart';
import '../services/jiosaavn.dart';
import '../services/offlinemanager.dart';
import '../shared/constants.dart';
import '../utils/theme.dart';
import 'shimmers.dart';
import 'snackbar.dart';
import 'timersheet.dart';

enum MediaType { song, album, playlist, artist }

// Usage:
void showMediaItemMenu(BuildContext context, SongMediaItem item) {
  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: spotifyBgColor,
    builder: (ctx) => MediaItemMenu(item: item),
  );
}

class MediaItemMenu extends ConsumerStatefulWidget {
  final SongMediaItem item;

  const MediaItemMenu({super.key, required this.item});

  @override
  ConsumerState<MediaItemMenu> createState() => _MediaItemMenuState();
}

class _MediaItemMenuState extends ConsumerState<MediaItemMenu> {
  late final MediaType type;

  @override
  void initState() {
    super.initState();
    type = _resolveMediaType(widget.item);
  }

  @override
  Widget build(BuildContext context) {
    final controller = DraggableScrollableController();

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: DraggableScrollableSheet(
        controller: controller,
        initialChildSize: 0.55,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        snap: true,
        snapSizes: [.5, .95],
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: spotifyBgColor,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: ListView(
              controller: scrollController,
              padding: EdgeInsets.zero,
              children: [
                // Handle
                const Padding(
                  padding: EdgeInsets.only(top: 10, bottom: 6),
                  child: Center(
                    child: SizedBox(
                      width: 38,
                      height: 4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white30,
                          borderRadius: BorderRadius.all(Radius.circular(2)),
                        ),
                      ),
                    ),
                  ),
                ),

                // Header
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  leading: CacheNetWorkImg(
                    url:
                        widget.item.images.isNotEmpty
                            ? widget.item.images.last.url
                            : '',
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  title: Text(
                    widget.item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  subtitle: Text(
                    _getSubtitle(widget.item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),

                const Divider(color: Colors.white12, height: 16),

                // Menu actions
                _buildMenuItems(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMenuItems() {
    final bool alreadyAdded =
        (() {
          if (widget.item is Album) {
            final frequentAlbums = ref.watch(frequentAlbumsProvider);
            return frequentAlbums.any((a) => a.id == (widget.item as Album).id);
          } else if (widget.item is Playlist) {
            final frequentPlaylists = ref.watch(frequentPlaylistsProvider);
            return frequentPlaylists.any(
              (p) => p.id == (widget.item as Playlist).id,
            );
          }
          return false;
        })();

    final bool isAlreadyDownloaded = () {
      if (widget.item is Album) {
        return offlineManager.isAlbumDownloaded((widget.item as Album).id);
      } else if (widget.item is SongDetail) {
        return offlineManager.isSongDownloaded((widget.item as SongDetail).id);
      } else {
        return false; // playlists / artists cannot be downloaded
      }
    }();

    final List<Widget> items = [
      _buildAssetMenuItem(
        context,
        icon: 'assets/icons/share.png',
        text: 'Share',
        onTap: () {
          Navigator.pop(context);
          _handleShare(widget.item);
        },
      ),
      if (type == MediaType.song || type == MediaType.album)
        _buildAssetMenuItem(
          context,
          icon: 'assets/icons/add_to_queue.png',
          text: 'Add to Queue',
          onTap: () {
            Navigator.pop(context);
            _handleAddToQueue(ref, widget.item);
          },
        ),
      if (type == MediaType.song)
        _buildAssetMenuItem(
          context,
          icon:
              (widget.item is SongDetail &&
                      ref
                          .watch(likedSongsProvider)
                          .contains((widget.item as SongDetail).id))
                  ? 'assets/icons/tick.png'
                  : 'assets/icons/like.png',

          text: 'Add to Liked Songs',
          onTap: () {
            Navigator.pop(context);
            _handleLike(ref, widget.item);
          },
        ),

      if (type == MediaType.album || type == MediaType.playlist)
        _buildAssetMenuItem(
          context,
          icon: alreadyAdded ? 'assets/icons/tick.png' : 'assets/icons/add.png',
          text: 'Add to Library',
          onTap: () {
            _handleAddToLibrary(ref, widget.item, type);
            Navigator.pop(context);
          },
        ),
      _buildAssetMenuItem(
        context,
        icon: 'assets/icons/timer.png',
        text: 'Sleep Timer',
        onTap: () {
          Navigator.pop(context);
          showSleepTimerSheet(context);
        },
      ),
      if (type == MediaType.song || type == MediaType.album)
        _buildAssetMenuItem(
          context,
          icon:
              isAlreadyDownloaded
                  ? 'assets/icons/tick.png'
                  : 'assets/icons/download.png',
          text: isAlreadyDownloaded ? 'Downloaded' : 'Download',
          onTap: () {
            Navigator.pop(context);
            _handleDownload(widget.item);
          },
        ),

      const SizedBox(height: 24),
    ];

    return Column(children: items);
  }
}

// --------- FUNCTION --------------
Future<void> _handleShare(SongMediaItem item) async {
  debugPrint('--> Share pressed');

  final details = StringBuffer()..writeln("Sharing from Hivefy 🎵\n");

  if (item is SongDetail) {
    details
      ..writeln("🎧 Song: ${item.title}")
      ..writeln(
        "🎤 Artist: ${item.contributors.all.map((a) => a.title).toSet().join(', ')}",
      )
      ..writeln("💿 Album: ${item.albumName ?? item.album}")
      ..writeln("⏱ Duration: ${item.getHumanReadableDuration()}")
      ..writeln("Year: ${item.year ?? 'Unknown'}")
      ..writeln("Link : ${item.url}");
  } else if (item is Album) {
    details
      ..writeln("💿 Album: ${item.title}")
      ..writeln("🎤 Artist : ${item.artist}")
      ..writeln("Year: ${item.year}")
      ..writeln("Link : ${item.url}");
  } else if (item is Playlist) {
    final count =
        item.songCount ?? (item.songs.isNotEmpty ? item.songs.length : 0);
    details
      ..writeln("🎶 Playlist: ${item.title}")
      ..writeln("📀 Songs: $count")
      ..writeln("Link : ${item.url}");
  } else {
    details.writeln(item.title);
  }

  Uint8List? imageBytes;
  try {
    final imageUrl = item.images.isNotEmpty ? item.images.last.url : null;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final provider = CachedNetworkImageProvider(imageUrl);
      final stream = provider.resolve(const ImageConfiguration());
      final completer = Completer<ImageInfo>();

      void listener(ImageInfo info, bool _) => completer.complete(info);
      stream.addListener(ImageStreamListener(listener));

      final info = await completer.future;
      final byteData = await info.image.toByteData(format: ImageByteFormat.png);
      imageBytes = byteData?.buffer.asUint8List();
    }
  } catch (e) {
    debugPrint("⚠️ Failed to get image for share: $e");
  }

  await SharePlus.instance.share(
    ShareParams(
      text: details.toString(),
      files:
          imageBytes != null
              ? [
                XFile.fromData(
                  imageBytes,
                  name: '${item.title}_hivefy.png',
                  mimeType: 'image/png',
                ),
              ]
              : [],
      title: "Sharing from Hivefy 🎵",
    ),
  );
}

Future<void> _handleAddToQueue(WidgetRef ref, SongMediaItem item) async {
  final audioHandler = await ref.read(audioHandlerProvider.future);

  if (item is SongDetail) {
    if (!isInUpcomingQueue(audioHandler, item.id)) {
      await audioHandler.addSongNext(item);
      info('${item.title} will play next', Severity.success);
    } else {
      info('${item.title} is already in the queue', Severity.info);
    }
  } else if (item is Album) {
    final album = await saavn.fetchAlbumById(albumId: item.id);
    if (album != null && album.songs.isNotEmpty) {
      final albumSongs = await saavn.getSongDetails(
        ids: album.songs.map((s) => s.id).toList(),
      );

      for (final song in albumSongs) {
        if (!isInUpcomingQueue(audioHandler, song.id)) {
          await audioHandler.addSongNext(song);
        }
      }
      info(
        'All songs from album ${album.title} added to queue',
        Severity.success,
      );
    }
  }
}

/// Returns true if song is already in the queue
bool isInUpcomingQueue(AudioHandler audioHandler, String songId) {
  final queue = audioHandler.queue.value;
  final currentIndex = audioHandler.playbackState.value.queueIndex ?? 0;

  // Only check songs after the current index
  final upcoming = queue.skip(currentIndex + 1);
  return upcoming.any((item) => item.id == songId);
}

void _handleLike(WidgetRef ref, SongMediaItem item) {
  if (item is SongDetail) {
    final isLiked = ref.watch(likedSongsProvider).contains(item.id);

    ref.read(likedSongsProvider.notifier).toggle(item.id);

    info(
      isLiked ? 'Removed from Liked Songs' : 'Added to Liked Songs',
      Severity.success,
    );
  }
}

void _handleAddToLibrary(
  WidgetRef ref,
  SongMediaItem item,
  MediaType type,
) async {
  // Pre-read the notifiers
  final albumNotifier = ref.read(frequentAlbumsProvider.notifier);
  final playlistNotifier = ref.read(frequentPlaylistsProvider.notifier);
  final frequentPlaylists = ref.read(frequentPlaylistsProvider);
  final frequentAlbums = ref.read(frequentAlbumsProvider);

  if (type == MediaType.album && item is Album) {
    final alreadyAdded = frequentAlbums.any((a) => a.id == item.id);

    if (alreadyAdded) {
      await albumNotifier.removeAlbum(item.id);
      info('${item.title} removed from library', Severity.info);
    } else {
      await AlbumCache().set(item.id, item);
      await albumNotifier.promoteAlbum(item.id);
      info('${item.title} added to library', Severity.success);
    }
  } else if (type == MediaType.playlist && item is Playlist) {
    final alreadyAdded = frequentPlaylists.any((p) => p.id == item.id);

    if (alreadyAdded) {
      await playlistNotifier.removePlaylist(item.id);
      info('${item.title} removed from library', Severity.info);
    } else {
      await PlaylistCache().set(item.id, item);
      await playlistNotifier.promotePlaylist(item.id);
      info('${item.title} added to library', Severity.success);
    }
  }
}

void _handleDownload(SongMediaItem item) async {
  if (item is SongDetail) {
    final isDownloaded = offlineManager.isSongDownloaded(item.id);
    if (isDownloaded) {
      info('Deleting ${item.title}', Severity.info);
      await offlineManager.deleteSong(item.id);
    } else {
      info('Downloading ${item.title}', Severity.info);
      offlineManager.updateStatus(item.id, DownloadStatus.downloading);
      offlineManager.updateProgress(item.id, 0.0);
      offlineManager.requestSongDownload(
        item.id,
        onProgress: (p) => offlineManager.updateProgress(item.id, p),
      );
    }
  } else if (item is Album) {
    final isDownloaded = offlineManager.isAlbumDownloaded(item.id);
    if (isDownloaded) {
      info('Removed album ${item.title}', Severity.info);
      await offlineManager.deleteAlbumById(item.id);
    } else {
      info('Removed album ${item.title}', Severity.info);
      offlineManager.downloadAlbumSongs(item);
    }
  }
}

// Check if album is fully downloaded
bool isAlbumDownloaded(String albumId) =>
    offlineManager.isAlbumDownloaded(albumId);

// ------------ HELPERS -------------
MediaType _resolveMediaType(SongMediaItem item) {
  if (item is SongDetail) return MediaType.song;
  if (item is Album) return MediaType.album;
  if (item is Playlist) return MediaType.playlist;
  return MediaType.artist;
}

/// Menu tile with asset icon
Widget _buildAssetMenuItem(
  BuildContext context, {
  required String icon,
  required String text,
  required VoidCallback onTap,
}) {
  double iconSize =
      (text.toLowerCase().contains('queue') ||
              text.toLowerCase().contains('liked'))
          ? 20
          : 24;

  return InkWell(
    onTap: onTap,
    splashColor: Colors.white10,
    highlightColor: Colors.transparent,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Image.asset(
            icon,
            width: iconSize,
            height: iconSize,
            color:
                icon.toLowerCase().contains('tick')
                    ? spotifyGreen
                    : Colors.white70,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

String _getSubtitle(SongMediaItem item) {
  if (item is SongDetail) {
    return item.contributors.all.map((a) => a.title).toSet().join(', ');
  } else if (item is Album) {
    return item.artist.isNotEmpty ? item.artist : 'Album';
  } else if (item is Playlist) {
    return item.artists.map((a) => a.title).toSet().join(', ');
  }
  return '';
}
