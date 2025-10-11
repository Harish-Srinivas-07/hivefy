import 'dart:math';

import 'package:flutter/material.dart';
import 'package:hivefy/components/snackbar.dart';
import 'package:hivefy/shared/constants.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:page_transition/page_transition.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/shimmers.dart';
import '../services/defaultfetcher.dart';
import '../models/database.dart';
import '../models/datamodel.dart';
import '../services/offlinemanager.dart';
import '../services/latestsaavnfetcher.dart';

import '../services/localnotification.dart';
import '../utils/theme.dart';
import 'views/albumviewer.dart';
import 'views/artistviewer.dart';
import 'views/playlistviewer.dart';
import 'views/songsviewer.dart';

class Dashboard extends ConsumerStatefulWidget {
  const Dashboard({super.key});

  @override
  ConsumerState<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends ConsumerState<Dashboard> {
  bool loading = true;
  List<Playlist> playlists = [];
  List<Playlist> freqplaylists = [];
  List<Playlist> latestTamilPlayList = [];
  List<Album> latestTamilAlbums = [];
  List<ArtistDetails> artists = [];
  List<Album> albums = [];
  List<Playlist> freqRecentPlaylists = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    loading = true;
    if (mounted) setState(() {});
    _initInternetChecker();

    await Future.delayed(const Duration(seconds: 2));

    // Refresh daily caches
    await DailyFetches.refreshAllDaily();

    // Load cached data
    playlists = await DailyFetches.getPlaylistsFromCache();
    artists = await DailyFetches.getArtistsAsListFromCache();

    // offline manager init
    await offlineManager.init();

    // Frequent items
    freqplaylists = (ref.read(frequentPlaylistsProvider)).take(5).toList();
    albums = (ref.read(frequentAlbumsProvider)).take(5).toList();

    // Latest Tamil content
    latestTamilPlayList = await LatestSaavnFetcher.getLatestPlaylists('tamil');
    latestTamilAlbums = await LatestSaavnFetcher.getLatestAlbums('tamil');

    debugPrint(
      '--> play ${playlists.length}, artist ${artists.length}, freq ${freqplaylists.length}, albums ${albums.length}, latest play ${latestTamilPlayList.length}, latest album ${latestTamilAlbums.length}',
    );

    // Build freqRecentPlaylists with exactly 7 items
    freqRecentPlaylists = [];

    // Add up to 3 frequent playlists first
    freqRecentPlaylists.addAll(freqplaylists.take(3));

    // Fill next with latest Tamil playlists (shuffle first)
    final shuffledLatest = List.of(latestTamilPlayList)..shuffle(Random());
    freqRecentPlaylists.addAll(
      shuffledLatest.take(7 - freqRecentPlaylists.length),
    );

    // Fill remaining from all playlists (shuffle first)
    if (freqRecentPlaylists.length < 7) {
      final shuffledAll = List.of(playlists)..shuffle(Random());
      freqRecentPlaylists.addAll(
        shuffledAll.take(7 - freqRecentPlaylists.length),
      );
    }

    // Ensure exactly 7 items
    if (freqRecentPlaylists.length > 7) {
      freqRecentPlaylists = freqRecentPlaylists.take(7).toList();
    }

    loading = false;
    if (mounted) setState(() {});
    await Future.delayed(const Duration(seconds: 30));
    await requestNotificationPermission();
  }

  Future<void> _initInternetChecker() async {
    InternetConnection().onStatusChange.listen((status) {
      if (status == InternetStatus.disconnected) {
        hasInternet.value = false;
        info(
          'Network is unstable.\nKindly switch to a better network.',
          Severity.error,
        );
      } else {
        hasInternet.value = true;
      }
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    // Latest fetches
    final mid = (latestTamilPlayList.length / 2).ceil();
    final topLatest = latestTamilPlayList.sublist(0, mid);
    final fresh = latestTamilPlayList.sublist(mid);
    // latest album
    final amid = (latestTamilAlbums.length / 2).ceil();
    final topLatestAlbum = latestTamilAlbums.sublist(0, amid);
    final freshAlbum = latestTamilAlbums.sublist(amid);

    return Scaffold(
      backgroundColor: spotifyBgColor,
      appBar: AppBar(
        backgroundColor: spotifyBgColor,
        elevation: 0,
        title: _buildHeader(),
      ),
      body:
          loading
              ? ListView(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
                children: [
                  heroGridShimmer(),
                  const SizedBox(height: 16),
                  buildPlaylistSectionShimmer(),
                  const SizedBox(height: 16),
                  buildPlaylistSectionShimmer(),
                  const SizedBox(height: 70),
                ],
              )
              : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionGrid(freqRecentPlaylists),
                    _sectionList(
                      "Top Latest",

                      List.of(topLatest)..shuffle(Random()),
                    ),
                    _sectionAlbumList(
                      "Today's biggest hits",
                      List.of(topLatestAlbum)..shuffle(Random()),
                    ),
                    _sectionList("Fresh", List.of(fresh)..shuffle(Random())),
                    _sectionArtistList("Fav Artists", artists),
                    _sectionAlbumList("Recent Albums", albums),
                    _sectionAlbumList(
                      "Recommeneded for today",
                      List.of(freshAlbum)..shuffle(Random()),
                    ),
                    _sectionList(
                      "Century Playlist",
                      List.of(playlists)..shuffle(Random()),
                    ),
                    const SizedBox(height: 60),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Make',
                                style: TextStyle(
                                  fontSize: 40,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white54,
                                  height: .6,
                                ),
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'it Happen ',
                                    style: TextStyle(
                                      fontSize: 40,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white54,
                                      height: 1.1,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Image.asset(
                                    'assets/icons/heart.png',
                                    height: 40,
                                    alignment: Alignment.center,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'CRAFTED WITH CARE',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: const Color.fromARGB(255, 47, 47, 47),
                                  height: 1,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Scaffold.of(context).openDrawer(),
          behavior: HitTestBehavior.opaque,
          child: const CircleAvatar(
            radius: 18,
            backgroundImage: AssetImage('assets/icons/logo.png'),
          ),
        ),
        const SizedBox(width: 15),
        Text(
          'Hivefy',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _sectionGrid(List<Playlist> playlists) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (playlists.isEmpty) return const SizedBox.shrink();

    final combined = [
      Playlist(
        id: 'liked',
        title: 'Liked Songs',
        type: 'custom',
        url: '',
        images: [],
      ),
      // Playlist(
      //   id: 'all',
      //   title: 'All Songs',
      //   type: 'custom',
      //   url: '',
      //   images: [],
      // ),
      ...playlists,
    ];

    // Only take first 10 for the grid
    final displayList = combined.take(10).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: displayList.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 3.5,
            ),
            itemBuilder: (context, index) {
              final playlist = displayList[index];
              return _gridCard(playlist);
            },
          ),
        ],
      ),
    );
  }

  Widget _gridCard(Playlist p) {
    final isSpecial = p.id == 'liked' || p.id == 'all';
    final img = p.images.isNotEmpty ? p.images.first.url : '';
    final subtitle =
        (p.artists.isNotEmpty
            ? p.artists.first.title
            : (p.songCount != null ? '${p.songCount} songs' : ''));

    return GestureDetector(
      onTap: () {
        if (p.id == 'liked') {
          Navigator.of(context).push(
            PageTransition(
              type: PageTransitionType.rightToLeft,
              duration: const Duration(milliseconds: 300),
              child: SongsViewer(showLikedSongs: true),
            ),
          );
        }
        // else if (p.id == 'all') {
        //   Navigator.of(context).push(
        //     PageTransition(
        //       type: PageTransitionType.rightToLeft,
        //       duration: const Duration(milliseconds: 300),
        //       child: SongsViewer(showLikedSongs: false),
        //     ),
        //   );
        // }
        else {
          Navigator.of(context).push(
            PageTransition(
              type: PageTransitionType.rightToLeft,
              duration: const Duration(milliseconds: 300),
              child: PlaylistViewer(playlistId: p.id),
            ),
          );
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(70),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                bottomLeft: Radius.circular(6),
              ),
              child:
                  isSpecial
                      ? Container(
                        height: double.infinity,
                        width: 50,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors:
                                p.id == 'liked'
                                    ? [Colors.purpleAccent, Colors.deepPurple]
                                    : [spotifyGreen, Colors.teal],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Icon(
                          p.id == 'liked'
                              ? Icons.favorite
                              : Icons.library_music,
                          color: Colors.white,
                        ),
                      )
                      : (img.isNotEmpty
                          ? CacheNetWorkImg(
                            url: img,
                            width: 50,
                            height: double.infinity,
                            fit: BoxFit.cover,
                          )
                          : Container(
                            width: 60,
                            color: Colors.grey[800],
                            child: const Icon(Icons.album, color: Colors.white),
                          )),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  if (subtitle.isNotEmpty)
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- LIST SECTION (refined)
  Widget _sectionList(String title, List<Playlist> list) {
    if (loading) return buildPlaylistSectionShimmer();
    if (list.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16),
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            height: 220,
            child: PageView.builder(
              controller: PageController(viewportFraction: 0.45),
              padEnds: false,
              physics: const BouncingScrollPhysics(),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final playlist = list[index];
                return Padding(
                  padding: EdgeInsets.only(left: 16),
                  child: _playlistCard(playlist),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _playlistCard(Playlist playlist) {
    final imageUrl =
        playlist.images.isNotEmpty ? playlist.images.first.url : '';
    final subtitle =
        playlist.artists.isNotEmpty
            ? playlist.artists.first.title
            : (playlist.songCount != null ? '${playlist.songCount} songs' : '');
    final description = playlist.description;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (playlist.id == 'liked') {
          Navigator.of(context).push(
            PageTransition(
              type: PageTransitionType.rightToLeft,
              duration: const Duration(milliseconds: 300),
              child: SongsViewer(showLikedSongs: true),
            ),
          );
        } else if (playlist.id == 'all') {
          Navigator.of(context).push(
            PageTransition(
              type: PageTransitionType.rightToLeft,
              duration: const Duration(milliseconds: 300),
              child: SongsViewer(showLikedSongs: false),
            ),
          );
        } else {
          Navigator.of(context).push(
            PageTransition(
              type: PageTransitionType.rightToLeft,
              duration: const Duration(milliseconds: 300),
              child: PlaylistViewer(playlistId: playlist.id),
            ),
          );
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child:
                  imageUrl.isNotEmpty
                      ? CacheNetWorkImg(url: imageUrl, fit: BoxFit.cover)
                      : Container(
                        color: Colors.grey.shade800,
                        child: const Icon(
                          Icons.album,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
            ),
          ),
          const SizedBox(height: 6),
          Flexible(
            child: Text(
              playlist.title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          if (subtitle.isNotEmpty)
            Flexible(
              child: Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          if (description.isNotEmpty)
            Flexible(
              child: Text(
                description,
                style: TextStyle(color: Colors.white38, fontSize: 10),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionArtistList(String title, List<ArtistDetails> artists) {
    if (artists.isEmpty) return const SizedBox.shrink();

    final PageController controller = PageController(viewportFraction: 0.35);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(title),
        const SizedBox(height: 16),
        SizedBox(
          height: 140,
          child: PageView.builder(
            controller: controller,
            padEnds: false,
            physics: const BouncingScrollPhysics(),
            itemCount: artists.length,
            itemBuilder: (context, index) {
              return AnimatedBuilder(
                animation: controller,
                builder: (context, child) {
                  double scale = 1.0;
                  if (controller.position.haveDimensions) {
                    double page =
                        controller.page ?? controller.initialPage.toDouble();
                    scale = (1 - ((page - index).abs() * 0.3)).clamp(0.95, 1.0);
                  }
                  return Transform.scale(scale: scale, child: child);
                },
                child: _artistCard(artists[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _artistCard(ArtistDetails artist) {
    final imageUrl = artist.images.isNotEmpty ? artist.images.last.url : '';

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          PageTransition(
            type: PageTransitionType.rightToLeft,
            duration: const Duration(milliseconds: 300),
            child: ArtistViewer(artistId: artist.id),
          ),
        );
      },
      child: Column(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundImage:
                imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
            backgroundColor: Colors.grey.shade800,
            child:
                imageUrl.isEmpty
                    ? const Icon(Icons.person, color: Colors.white, size: 30)
                    : null,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 100,
            child: Column(
              children: [
                Text(
                  artist.title,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
                Text(
                  artist.dominantLanguage,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
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

  Widget _sectionAlbumList(String title, List<Album> albums) {
    if (albums.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(title),
          const SizedBox(height: 8),
          SizedBox(
            height: 220,
            child: PageView.builder(
              controller: PageController(viewportFraction: 0.45),
              padEnds: false,
              physics: const BouncingScrollPhysics(),
              itemCount: albums.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: EdgeInsets.only(left: 16),
                  child: _albumCard(albums[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _albumCard(Album album) {
    final imageUrl = album.images.isNotEmpty ? album.images.last.url : '';

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          PageTransition(
            type: PageTransitionType.rightToLeft,
            duration: const Duration(milliseconds: 300),
            child: AlbumViewer(albumId: album.id),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child:
                  imageUrl.isNotEmpty
                      ? CacheNetWorkImg(url: imageUrl, fit: BoxFit.cover)
                      : Container(
                        color: Colors.grey.shade800,
                        child: const Icon(
                          Icons.album,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
            ),
          ),

          const SizedBox(height: 6),
          Text(
            album.title,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          Text(
            album.artist,
            style: TextStyle(
              color: Colors.white38,
              fontWeight: FontWeight.w300,
              fontSize: 12,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}
