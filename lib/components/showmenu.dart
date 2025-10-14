import 'package:flutter/material.dart';
import 'package:hivefy/utils/theme.dart';
import '../models/datamodel.dart';
import 'shimmers.dart';

void showMediaItemMenu(BuildContext context, SongMediaItem item) {
  debugPrint('--> here the press');

  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (ctx) {
      final controller = DraggableScrollableController();

      return StatefulBuilder(
        builder: (context, setState) {
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: DraggableScrollableSheet(
              controller: controller,
              initialChildSize: 0.42,
              minChildSize: 0.42,
              maxChildSize: 0.95,
              expand: false,
              shouldCloseOnMinExtent: false,
              builder: (context, scrollController) {
                return Container(
                  decoration: const BoxDecoration(
                    color: spotifyBgColor,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: EdgeInsets.zero,
                    children: [
                      // Grab handle
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 6),
                        child: Center(
                          child: Container(
                            width: 38,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white30,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),

                      // Header (song + artist)
                      ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: CacheNetWorkImg(
                          url:
                              item.images.isNotEmpty
                                  ? item.images.last.url
                                  : '',
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        title: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        subtitle: Text(
                          _getSubtitle(item),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),

                      const Divider(color: Colors.white12, height: 16),

                      // Menu Items
                      _buildAssetMenuItem(
                        context,
                        icon: 'assets/icons/share.png',
                        text: 'Share',
                        onTap: () => Navigator.pop(context),
                      ),
                      _buildAssetMenuItem(
                        context,
                        icon: 'assets/icons/add_to_queue.png',
                        text: 'Add to Queue',
                        onTap: () => Navigator.pop(context),
                      ),
                      _buildAssetMenuItem(
                        context,
                        icon: 'assets/icons/like.png',
                        text: 'Add to Liked Songs',
                        onTap: () => Navigator.pop(context),
                      ),
                      _buildAssetMenuItem(
                        context,
                        icon: 'assets/icons/add.png',
                        text: 'Add to Library',
                        onTap: () => Navigator.pop(context),
                      ),
                      _buildAssetMenuItem(
                        context,
                        icon: 'assets/icons/download.png',
                        text: 'Download',
                        onTap: () => Navigator.pop(context),
                      ),
                      _buildAssetMenuItem(
                        context,
                        icon: 'assets/icons/artist.png',
                        text: 'Go to Artist',
                        onTap: () => Navigator.pop(context),
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                );
              },
            ),
          );
        },
      );
    },
  );
}

/// Menu tile with asset icon
Widget _buildAssetMenuItem(
  BuildContext context, {
  required String icon,
  required String text,
  required VoidCallback onTap,
}) {
  return InkWell(
    onTap: onTap,
    splashColor: Colors.white10,
    highlightColor: Colors.transparent,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Image.asset(icon, width: 24, height: 24, color: Colors.white70),
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
    return '${item.songCount ?? item.songs.length} songs';
  }
  return '';
}
