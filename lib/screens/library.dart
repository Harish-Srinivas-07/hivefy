import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:page_transition/page_transition.dart';

import '../models/database.dart';
import '../shared/constants.dart';
import 'albumviewer.dart';
import 'artistviewer.dart';
import 'songsviewer.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  int _allSongsCount = 0;
  bool isDefined = false;
  List<LibraryCardData> items = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _init();
  }

  Future<void> _init() async {
    await _loadAllSongsCount();

    final albumCache = AlbumCache();
    final artistCache = ArtistCache();

    // Ensure caches are initialized if they have async init
    albums = await albumCache.getAll();
    artists = await artistCache.getAll();

    isDefined = true;
    if (mounted) setState(() {});
  }

  Future<void> _loadAllSongsCount() async {
    final allSongs = await AppDatabase.getAllSongs();
    _allSongsCount = allSongs.length;
  }

  @override
  Widget build(BuildContext context) {
    // Now build items
    items = [
      LibraryCardData(
        title: 'Liked Songs',
        count: ref.watch(likedSongsProvider).length,
        fallbackColor: Colors.redAccent,
        type: LibraryItemType.likedSongs,
      ),
      LibraryCardData(
        title: 'All Songs',
        count: _allSongsCount,
        fallbackColor: Colors.greenAccent,
        type: LibraryItemType.allSongs,
      ),
      ...albums.map(
        (album) => LibraryCardData(
          title: album.title,
          count: album.songs.length,
          imageUrl: album.images.isNotEmpty ? album.images.last.url : null,
          fallbackColor: Colors.grey,
          type: LibraryItemType.album,
          id: album.id,
        ),
      ),
      ...artists.map(
        (artist) => LibraryCardData(
          title: artist.title,
          count: artist.topSongs.length,
          imageUrl: artist.images.isNotEmpty ? artist.images.last.url : null,
          fallbackColor: Colors.grey,
          type: LibraryItemType.artist,
          id: artist.id,
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Row(
          children: [
            const CircleAvatar(
              radius: 18,
              backgroundImage: AssetImage('assets/logo.png'),
            ),
            const SizedBox(width: 10),
            Text(
              'Your Library',
              style: GoogleFonts.figtree(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body:
          !isDefined
              ? const Center(child: CircularProgressIndicator())
              : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 86),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return LibraryCard(
                    title: item.title,
                    count: item.count,
                    imageUrl: item.imageUrl,
                    fallbackColor: item.fallbackColor,
                    type: item.type,
                    onTap: () {
                      switch (item.type) {
                        case LibraryItemType.likedSongs:
                        case LibraryItemType.allSongs:
                          Navigator.of(context).push(
                            PageTransition(
                              type: PageTransitionType.rightToLeft,
                              duration: const Duration(milliseconds: 300),
                              child: SongsViewer(
                                showLikedSongs:
                                    item.type == LibraryItemType.likedSongs,
                              ),
                            ),
                          );
                          break;

                        case LibraryItemType.album:
                          Navigator.of(context).push(
                            PageTransition(
                              type: PageTransitionType.rightToLeft,
                              duration: const Duration(milliseconds: 300),
                              child: AlbumViewer(albumId: item.id!),
                            ),
                          );
                          break;

                        case LibraryItemType.artist:
                          Navigator.of(context).push(
                            PageTransition(
                              type: PageTransitionType.rightToLeft,
                              duration: const Duration(milliseconds: 300),
                              child: ArtistViewer(artistId: item.id!),
                            ),
                          );
                          break;
                      }
                    },
                  );
                },
              ),
    );
  }
}

enum LibraryItemType { likedSongs, allSongs, album, artist }

class LibraryCardData {
  final String title;
  final int count;
  final String? imageUrl;
  final Color fallbackColor;
  final LibraryItemType type;
  final String? id;

  LibraryCardData({
    required this.title,
    required this.count,
    this.imageUrl,
    required this.fallbackColor,
    required this.type,
    this.id,
  });
}

class LibraryCard extends StatelessWidget {
  final String title;
  final int count;
  final String? imageUrl;
  final Color fallbackColor;
  final VoidCallback? onTap;
  final LibraryItemType? type;

  const LibraryCard({
    super.key,
    required this.title,
    required this.count,
    this.imageUrl,
    required this.fallbackColor,
    this.onTap,
    this.type,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 65,
            height: 65,
            decoration: BoxDecoration(
              color: imageUrl == null ? fallbackColor : null,
              borderRadius:
                  type == LibraryItemType.artist
                      ? BorderRadius.circular(65)
                      : BorderRadius.circular(8),
              image:
                  imageUrl != null
                      ? DecorationImage(
                        image: NetworkImage(imageUrl!),
                        fit: BoxFit.cover,
                      )
                      : null,
            ),
            child:
                imageUrl == null
                    ? Icon(
                      title.toLowerCase().contains('liked')
                          ? Icons.favorite
                          : Icons.music_note,
                      color: Colors.black54,
                      size: 24,
                    )
                    : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.figtree(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                Text(
                  type == LibraryItemType.artist
                      ? 'Artist'
                      : '$count ${count == 1 ? 'song' : 'songs'}',
                  style: GoogleFonts.figtree(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
