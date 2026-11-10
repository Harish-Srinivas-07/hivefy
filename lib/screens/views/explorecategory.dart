import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:page_transition/page_transition.dart';
import 'package:shimmer/shimmer.dart';

import '../../components/empty_state.dart';
import '../../models/datamodel.dart';
import '../../services/youtube.dart';
import '../../utils/theme.dart';
import 'playlistviewer.dart';

class ExploreCategoryView extends StatefulWidget {
  final ExploreCategory category;
  final YoutubeAPI? searchApi;

  const ExploreCategoryView({super.key, required this.category, this.searchApi});

  @override
  State<ExploreCategoryView> createState() => _ExploreCategoryViewState();
}

class _ExploreCategoryViewState extends State<ExploreCategoryView> {
  List<Playlist> _playlists = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    final playlists = await (widget.searchApi ?? YoutubeAPI()).fetchExploreCategoryPlaylists(widget.category);
    if (!mounted) return;
    setState(() {
      _playlists = playlists;
      _loading = false;
    });
  }

  void _openPlaylist(Playlist playlist) {
    Navigator.of(context).push(
      PageTransition(
        type: PageTransitionType.rightToLeft,
        duration: const Duration(milliseconds: 300),
        child: PlaylistViewer(playlistId: playlist.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: spotifyBgColor,
      appBar: AppBar(
        backgroundColor: spotifyBgColor,
        foregroundColor: Colors.white,
        title: Text(widget.category.title, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : _playlists.isEmpty
          ? const EmptyState(
              icon: LucideIcons.music2,
              title: 'No playlists found',
              subtitle: 'YouTube Music did not return playlists for this category.',
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                const columns = 2;
                final cardWidth = (constraints.maxWidth - 32 - (columns - 1) * 14) / columns;
                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 18,
                    mainAxisExtent: cardWidth + 68,
                  ),
                  itemCount: _playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = _playlists[index];
                    final imageUrl = playlist.images.isEmpty ? '' : playlist.images.last.url;
                    return GestureDetector(
                      onTap: () => _openPlaylist(playlist),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AspectRatio(
                            aspectRatio: 1,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: imageUrl.isEmpty
                                  ? Container(
                                      color: Colors.white10,
                                      alignment: Alignment.center,
                                      child: const Icon(LucideIcons.listMusic, size: 42, color: Colors.white54),
                                    )
                                  : CachedNetworkImage(
                                      imageUrl: imageUrl,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Shimmer.fromColors(
                                        baseColor: Colors.grey.shade800,
                                        highlightColor: Colors.grey.shade700,
                                        child: Container(color: Colors.grey.shade800),
                                      ),
                                      errorWidget: (context, url, error) => const Center(
                                        child: Icon(LucideIcons.listMusic, size: 42, color: Colors.white54),
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            playlist.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                          if (playlist.description.isNotEmpty)
                            Text(
                              playlist.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white60, fontSize: 12),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
