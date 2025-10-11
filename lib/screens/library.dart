import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:page_transition/page_transition.dart';

import '../models/database.dart';
import '../models/datamodel.dart';
import '../components/shimmers.dart';
import '../services/offlinemanager.dart';
import '../shared/constants.dart';
import '../utils/format.dart';
import '../utils/theme.dart';
import 'views/albumviewer.dart';
import 'views/artistviewer.dart';
import 'views/playlistviewer.dart';
import 'views/songsviewer.dart';

enum LibraryFilter { all, playlist, artists, albums }

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
  List<Playlist> playlists = [];
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
      if (!mounted) return;
      playlists = (ref.read(frequentPlaylistsProvider)).take(5).toList();
    } else if (_currentFilter == LibraryFilter.albums) {
      if (!mounted) return;
      albums = ref.read(frequentAlbumsProvider);
    } else if (_currentFilter == LibraryFilter.playlist) {
      if (!mounted) return;
      playlists = ref.read(frequentPlaylistsProvider);
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
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children:
            LibraryFilter.values.map((filter) {
              final isSelected = _currentFilter == filter;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: ChoiceChip(
                  label: Text(
                    capitalize(filter.name),
                    style: TextStyle(
                      color: isSelected ? spotifyGreen : Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  selected: isSelected,
                  selectedColor: spotifyGreen.withAlpha(51),
                  backgroundColor: Colors.grey[900],
                  selectedShadowColor: Colors.grey.shade900,
                  color: WidgetStateProperty.resolveWith<Color?>((states) {
                    return Colors.grey.shade900;
                  }),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected ? spotifyGreen : Colors.grey.shade800,
                      width: isSelected ? 1 : 0,
                    ),
                  ),
                  visualDensity: const VisualDensity(
                    vertical: -2,
                    horizontal: 0,
                  ),
                  showCheckmark: false,

                  onSelected: (_) => setState(() => _currentFilter = filter),
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
      case LibraryFilter.playlist:
        return items
            .where((item) => item.type == LibraryItemType.playlist)
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

    playlists =
        (_currentFilter == LibraryFilter.all)
            ? (ref.watch(frequentPlaylistsProvider)).take(5).toList()
            : ref.watch(frequentPlaylistsProvider);

    items = [
      LibraryCardData(
        id: 'h_liked',
        title: 'Liked Songs',
        count: ref.watch(likedSongsProvider).length,
        subtitle: 'Playlist',
        fallbackColor: Colors.redAccent,
        type: LibraryItemType.likedSongs,
      ),
      LibraryCardData(
        id: 'h_all',
        title: 'All Songs',
        count: _allSongsCount,
        subtitle: 'Playlist',
        fallbackColor: Colors.greenAccent,
        type: LibraryItemType.allSongs,
      ),
      ...albums.map(
        (album) => LibraryCardData(
          id: album.id,
          title: album.title,
          count: album.songs.length,
          subtitle:
              album.artists.isNotEmpty
                  ? album.artists.map((a) => a.title).join(', ')
                  : 'Unknown Artist',
          imageUrl: album.images.isNotEmpty ? album.images.last.url : null,
          fallbackColor: Colors.grey,
          type: LibraryItemType.album,
        ),
      ),
      ...playlists.map(
        (playlist) => LibraryCardData(
          title: playlist.title,
          count: playlist.songs.length,
          subtitle:
              playlist.artists.isNotEmpty
                  ? playlist.artists.map((a) => a.title).join(', ')
                  : 'Unknown Artist',
          imageUrl:
              playlist.images.isNotEmpty ? playlist.images.last.url : null,
          fallbackColor: Colors.grey,
          type: LibraryItemType.playlist,
          id: playlist.id,
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
      backgroundColor: spotifyBgColor,
      appBar: AppBar(
        title: Row(
          children: [
            GestureDetector(
              onTap: () => Scaffold.of(context).openDrawer(),
              behavior: HitTestBehavior.opaque,
              child: const CircleAvatar(
                radius: 18,
                backgroundImage: AssetImage('assets/icons/logo.png'),
              ),
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
                          id: item.id,
                          title: item.title,
                          count: item.count,
                          imageUrl: item.imageUrl,
                          fallbackColor: item.fallbackColor,
                          subtitle: item.subtitle,
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
                                    child: AlbumViewer(albumId: item.id),
                                  ),
                                );
                                break;

                              case LibraryItemType.artist:
                                Navigator.of(context).push(
                                  PageTransition(
                                    type: PageTransitionType.rightToLeft,
                                    duration: const Duration(milliseconds: 300),
                                    child: ArtistViewer(artistId: item.id),
                                  ),
                                );
                                break;

                              case LibraryItemType.playlist:
                                Navigator.of(context).push(
                                  PageTransition(
                                    type: PageTransitionType.rightToLeft,
                                    duration: const Duration(milliseconds: 300),
                                    child: PlaylistViewer(playlistId: item.id),
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

enum LibraryItemType { likedSongs, allSongs, album, artist, playlist }

class LibraryCardData {
  final String id;
  final String title;
  final int count;
  final String? imageUrl;
  final String? subtitle;
  final Color fallbackColor;
  final LibraryItemType type;

  LibraryCardData({
    required this.id,
    required this.title,
    required this.count,
    this.imageUrl,
    this.subtitle,
    required this.fallbackColor,
    required this.type,
  });
}

class LibraryCard extends StatelessWidget {
  final String id;
  final String title;
  final int count;
  final String? imageUrl;
  final String? subtitle;
  final Color fallbackColor;
  final VoidCallback? onTap;
  final LibraryItemType? type;

  const LibraryCard({
    super.key,
    required this.id,
    required this.title,
    required this.count,
    this.imageUrl,
    this.subtitle,
    required this.fallbackColor,
    this.onTap,
    this.type,
  });

  @override
  Widget build(BuildContext context) {
    final subtitleText = _buildSubtitle();

    return ValueListenableBuilder(
      valueListenable: hasInternet,
      builder: (context, value, child) {
        // Determine if this item should be clickable
        bool isEnabled = true;

        if (!value) {
          switch (type) {
            case LibraryItemType.album:
              isEnabled = offlineManager.isAvailableOffline(albumId: id);
              break;
            case LibraryItemType.likedSongs:
            case LibraryItemType.allSongs:
              isEnabled = true;
              break;
            default:
              isEnabled = false;
          }
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: isEnabled ? onTap : null,
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: imageUrl == null ? fallbackColor : null,
                  borderRadius:
                      type == LibraryItemType.artist
                          ? BorderRadius.circular(60)
                          : BorderRadius.circular(6),
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
                          width: 60,
                          height: 60,
                          fit: BoxFit.cover,
                          borderRadius:
                              type == LibraryItemType.artist
                                  ? BorderRadius.circular(60)
                                  : BorderRadius.circular(6),
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
                        color: isEnabled ? Colors.white : Colors.white38,
                        fontWeight: FontWeight.w500,
                        fontSize: 17,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitleText,
                      style: TextStyle(
                        color: isEnabled ? Colors.white70 : Colors.white38,
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
      },
    );
  }

  String _buildSubtitle() {
    if (type == LibraryItemType.artist) return 'Artist';

    final songText = '$count ${count == 1 ? 'song' : 'songs'}';
    if (subtitle != null && subtitle!.isNotEmpty) {
      return '$subtitle • $songText';
    }
    return songText;
  }
}
