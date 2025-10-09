import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:page_transition/page_transition.dart';

import '../models/database.dart';
import '../models/datamodel.dart';
import '../components/shimmers.dart';
import '../shared/constants.dart';
import '../utils/format.dart';
import 'albumviewer.dart';
import 'artistviewer.dart';
import 'songsviewer.dart';

enum LibraryFilter { all, artists, albums }

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  int _allSongsCount = 0;
  bool isDefined = false;
  List<LibraryCardData> items = [];
  List<Album> albums = [];
  List<ArtistDetails> artists = [];

  LibraryFilter _currentFilter = LibraryFilter.all;

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
    if (!mounted) return;
    if (_currentFilter == LibraryFilter.all) {
      if (!mounted) return;
      albums = (ref.read(frequentAlbumsProvider)).take(5).toList();
      if (!mounted) return;
      artists = (ref.read(frequentArtistsProvider)).take(5).toList();
    } else if (_currentFilter == LibraryFilter.albums) {
      if (!mounted) return;
      albums = ref.read(frequentAlbumsProvider);
    } else if (_currentFilter == LibraryFilter.artists) {
      if (!mounted) return;
      artists = ref.read(frequentArtistsProvider);
    }

    if (!mounted) return;
    _allSongsCount = ref.read(allSongsProvider).length;

    isDefined = true;
    if (mounted) setState(() {});
  }

  Widget _buildFilterBar() {
    return Container(
      decoration: const BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black54,
            offset: Offset(0, 3),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: Row(
        // mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        children:
            LibraryFilter.values.map((filter) {
              final isSelected = _currentFilter == filter;
              return Padding(
                padding: const EdgeInsets.only(right: 4),
                child: GestureDetector(
                  onTap: () {
                    setState(() => _currentFilter = filter);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color:
                          isSelected
                              ? Colors.green.withAlpha(160)
                              : Colors.white38.withAlpha(100),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      capitalize(filter.name),
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }

  List<LibraryCardData> _filteredItems() {
    switch (_currentFilter) {
      case LibraryFilter.artists:
        return items
            .where((item) => item.type == LibraryItemType.artist)
            .toList();
      case LibraryFilter.albums:
        return items
            .where((item) => item.type == LibraryItemType.album)
            .toList();
      case LibraryFilter.all:
        return items;
    }
  }

  @override
  Widget build(BuildContext context) {
    _allSongsCount = ref.watch(allSongsProvider).length;
    albums =
        (_currentFilter == LibraryFilter.all)
            ? (ref.watch(frequentAlbumsProvider)).take(5).toList()
            : ref.watch(frequentAlbumsProvider);

    artists =
        (_currentFilter == LibraryFilter.all)
            ? (ref.watch(frequentArtistsProvider)).take(5).toList()
            : ref.watch(frequentArtistsProvider);

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
              style: TextStyle(
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
              ? Padding(
                padding: const EdgeInsets.only(top: 60),
                child: buildAlbumShimmer(),
              )
              : Column(
                children: [
                  _buildFilterBar(),

                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 86),
                      itemCount: _filteredItems().length,

                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final item = _filteredItems()[index];

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
                                          item.type ==
                                          LibraryItemType.likedSongs,
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
                  ),
                ],
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
                    : CacheNetWorkImg(
                      url: imageUrl!,
                      width: 65,
                      height: 65,
                      fit: BoxFit.cover,
                      borderRadius:
                          type == LibraryItemType.artist
                              ? BorderRadius.circular(65)
                              : BorderRadius.circular(8),
                    ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
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
                  style: TextStyle(color: Colors.white70, fontSize: 13),
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
