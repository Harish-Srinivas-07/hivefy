import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:page_transition/page_transition.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../components/empty_state.dart';
import '../components/staggered_appearance.dart';
import '../models/database.dart';
import '../models/datamodel.dart';
import '../components/shimmers.dart';
import '../services/offlinemanager.dart';
import '../services/youtube.dart';
import '../shared/constants.dart';
import '../utils/format.dart';
import '../utils/library_metadata.dart';
import '../utils/theme.dart';
import 'features/language.dart';
import 'features/profile.dart';
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
  bool isDefined = false;
  List<LibraryCardData> items = [];
  List<Album> albums = [];
  List<Playlist> playlists = [];
  List<ArtistDetails> artists = [];
  final Map<String, Album> _refreshedAlbums = {};
  final Set<String> _requestedAlbums = {};

  LibraryFilter _currentFilter = LibraryFilter.all;

  @override
  void initState() {
    super.initState();
    offlineManager.downloadedSongsRevision.addListener(_downloadsChanged);
    _init();
    ref.read(languageNotifierProvider).addListener(() {
      if (!mounted) return;
      _init();
    });
  }

  void _downloadsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    offlineManager.downloadedSongsRevision.removeListener(_downloadsChanged);
    super.dispose();
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

    isDefined = true;
    if (mounted) setState(() {});
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: LibraryFilter.values.map((filter) {
          final isSelected = _currentFilter == filter;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: ChoiceChip(
              label: Text(
                capitalize(filter.name),
                style: TextStyle(color: isSelected ? spotifyGreen : Colors.white, fontWeight: FontWeight.w500),
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
                side: BorderSide(color: isSelected ? spotifyGreen : Colors.grey.shade800, width: isSelected ? 1 : 0),
              ),
              visualDensity: const VisualDensity(vertical: -2, horizontal: 0),
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
        return items.where((item) => item.type == LibraryItemType.artist).toList();
      case LibraryFilter.albums:
        return items.where((item) => item.type == LibraryItemType.album).toList();
      case LibraryFilter.playlist:
        return items
            .where(
              (item) =>
                  item.type == LibraryItemType.playlist ||
                  item.type == LibraryItemType.likedSongs ||
                  item.type == LibraryItemType.downloadedSongs,
            )
            .toList();
      case LibraryFilter.all:
        return items;
    }
  }

  void _refreshMissingAlbumArtists(List<Album> items) {
    for (final album in items) {
      if (albumArtistName(album).isNotEmpty || !album.id.startsWith('MPREb_') || !_requestedAlbums.add(album.id)) {
        continue;
      }
      youtube.fetchAlbumById(albumId: album.id, refreshMetadata: true).then((updated) {
        if (!mounted || updated == null || albumArtistName(updated).isEmpty) {
          return;
        }
        setState(() => _refreshedAlbums[album.id] = updated);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    albums = (_currentFilter == LibraryFilter.all)
        ? (ref.watch(frequentAlbumsProvider)).take(5).toList()
        : ref.watch(frequentAlbumsProvider);
    _refreshMissingAlbumArtists(albums);

    artists = (_currentFilter == LibraryFilter.all)
        ? (ref.watch(frequentArtistsProvider)).take(5).toList()
        : ref.watch(frequentArtistsProvider);

    playlists = (_currentFilter == LibraryFilter.all)
        ? (ref.watch(frequentPlaylistsProvider)).take(5).toList()
        : ref.watch(frequentPlaylistsProvider);

    // Watch language listener
    ref.watch(languageNotifierProvider);

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
        id: 'h_downloaded',
        title: 'Downloaded Songs',
        count: offlineManager.getAllSongIds().length,
        subtitle: 'Playlist',
        fallbackColor: const Color(0xFF8BCFA4),
        type: LibraryItemType.downloadedSongs,
      ),
      ...albums.map(
        (album) => LibraryCardData(
          id: album.id,
          title: album.title,
          count: album.songs.length,
          subtitle: albumArtistName(_refreshedAlbums[album.id] ?? album).isNotEmpty
              ? albumArtistName(_refreshedAlbums[album.id] ?? album)
              : 'Album',
          imageUrl: album.images.isNotEmpty ? album.images.last.url : null,
          fallbackColor: Colors.grey,
          type: LibraryItemType.album,
        ),
      ),
      ...playlists.map(
        (playlist) => LibraryCardData(
          title: playlist.title,
          count:
              '${playlist.summary} ${playlist.description}'.contains(
                    RegExp(r'\b\d[\d,]*\s+songs?\b', caseSensitive: false),
                  ) ||
                  (playlist.songs.isNotEmpty && playlist.songCount == playlist.songs.length)
              ? null
              : playlist.songCount,
          subtitle: playlistLibrarySubtitle(playlist),
          imageUrl: playlist.images.isNotEmpty ? playlist.images.last.url : null,
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

    final filteredItems = _filteredItems();
    return Scaffold(
      backgroundColor: spotifyBgColor,
      appBar: AppBar(
        title: ValueListenableBuilder(
          valueListenable: profileRefreshNotifier,
          builder: (context, value, child) {
            return Row(
              children: [
                GestureDetector(
                  onTap: () => scaffoldKey.currentState?.openDrawer(),
                  behavior: HitTestBehavior.opaque,
                  child: CircleAvatar(
                    radius: 18,
                    backgroundImage: (profileFile != null && profileFile!.existsSync())
                        ? FileImage(profileFile!)
                        : const AssetImage('assets/icons/logo.png') as ImageProvider,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Your Library',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ],
            );
          },
        ),
        backgroundColor: spotifyBgColor,
        elevation: 0,
      ),
      body: !isDefined
          ? Padding(padding: const EdgeInsets.only(top: 60), child: buildAlbumShimmer())
          : Column(
              children: [
                _buildFilterBar(),

                Expanded(
                  child: filteredItems.isEmpty
                      ? EmptyState(
                          icon: _currentFilter == LibraryFilter.artists ? LucideIcons.users : LucideIcons.disc3,
                          title: _currentFilter == LibraryFilter.artists ? 'No artists yet' : 'No albums yet',
                          subtitle: _currentFilter == LibraryFilter.artists
                              ? 'Artists you listen to will appear here.'
                              : 'Albums you listen to will appear here.',
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 86),
                          itemCount: filteredItems.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = filteredItems[index];

                            return StaggeredAppearance(
                              key: ValueKey(item.id),
                              index: index,
                              child: LibraryCard(
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
                                    case LibraryItemType.downloadedSongs:
                                    case LibraryItemType.allSongs:
                                      Navigator.of(context).push(
                                        PageTransition(
                                          type: PageTransitionType.rightToLeft,
                                          duration: const Duration(milliseconds: 300),
                                          child: SongsViewer(
                                            showLikedSongs: item.type == LibraryItemType.likedSongs,
                                            showDownloadedSongs: item.type == LibraryItemType.downloadedSongs,
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
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}

enum LibraryItemType { likedSongs, downloadedSongs, allSongs, album, artist, playlist }

class LibraryCardData {
  final String id;
  final String title;
  final int? count;
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
  final int? count;
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
            case LibraryItemType.downloadedSongs:
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
                  borderRadius: type == LibraryItemType.artist ? BorderRadius.circular(60) : BorderRadius.circular(6),
                ),
                child: imageUrl == null
                    ? Icon(
                        type == LibraryItemType.likedSongs
                            ? Icons.favorite
                            : type == LibraryItemType.downloadedSongs
                            ? Icons.download_done_rounded
                            : Icons.music_note,
                        color: type == LibraryItemType.downloadedSongs ? downloadedArtworkColor : Colors.black54,
                        size: type == LibraryItemType.downloadedSongs ? 36 : 24,
                      )
                    : CacheNetWorkImg(
                        url: imageUrl!,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        borderRadius: type == LibraryItemType.artist
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
                      style: TextStyle(color: isEnabled ? Colors.white70 : Colors.white38, fontSize: 13),
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

    final songText = count == null
        ? ''
        : count == 0
        ? 'No songs'
        : '$count ${count == 1 ? 'song' : 'songs'}';
    if (subtitle != null && subtitle!.isNotEmpty) {
      return songText.isEmpty ? subtitle! : '$subtitle • $songText';
    }
    return songText;
  }
}
