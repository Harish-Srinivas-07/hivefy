import 'dart:async';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:flutter/material.dart';
import 'package:page_transition/page_transition.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:hivefy/utils/logger.dart';

import '../components/generalcards.dart';
import '../components/home_artwork.dart';
import '../components/staggered_appearance.dart';
import '../components/shimmers.dart';
import '../components/empty_state.dart';
import '../models/database.dart';
import '../models/datamodel.dart';
import '../services/youtube.dart';
import '../services/offlinemanager.dart';

import '../services/systemconfig.dart';
import '../shared/constants.dart';
import '../utils/theme.dart';
import '../utils/playlist_subtitle.dart';
import 'features/language.dart';
import 'features/profile.dart';
import 'views/albumviewer.dart';
import 'views/artistviewer.dart';
import 'views/playlistviewer.dart';
import 'views/songsviewer.dart';

final dashboardApiProvider = Provider<YoutubeAPI>((ref) => youtube);
final dashboardConnectionProvider = Provider<Stream<InternetStatus>>((ref) => InternetConnection().onStatusChange);

enum _HomeSection {
  topLatest,
  biggestHits,
  fresh,
  trending,
  newReleases,
  chill,
  devotional,
  party,
  artists,
  recentAlbums,
  recommended,
  love,
}

class Dashboard extends ConsumerStatefulWidget {
  const Dashboard({super.key});

  @override
  ConsumerState<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends ConsumerState<Dashboard> {
  bool loading = true;
  List<Playlist> playlists = [];
  List<Playlist> freqplaylists = [];
  List<ArtistDetails> artists = [];
  List<Album> albums = [];
  List<Playlist> freqRecentPlaylists = [];

  // cached shuffled lists
  List<Playlist> topLatest = [];
  List<Album> topLatestAlbum = [];
  List<Playlist> fresh = [];
  List<Album> freshAlbum = [];
  List<Playlist> partyShuffled = [];
  List<Playlist> loveShuffled = [];
  List<Playlist> trending = [];
  List<Playlist> newReleases = [];
  List<Playlist> chill = [];
  List<Playlist> devotional = [];
  bool _showWaitingCard = true;
  bool _showUpdateAvailable = true;
  bool _recommendationsUnavailable = false;
  late final ValueNotifier<List<String>> _languageNotifier;
  StreamSubscription<InternetStatus>? _internetSubscription;
  Future<void>? _offlineInitialization;
  bool _languagesReady = false;
  int _loadGeneration = 0;
  List<_HomeSection> _sectionOrder = [];

  @override
  void initState() {
    super.initState();
    _languageNotifier = ref.read(languageNotifierProvider);
    _languageNotifier.addListener(_onLanguagesChanged);
    _initInternetChecker();
    _initialize();
  }

  @override
  void dispose() {
    _languageNotifier.removeListener(_onLanguagesChanged);
    _internetSubscription?.cancel();
    super.dispose();
  }

  void _onLanguagesChanged() {
    if (_languagesReady && mounted) unawaited(_init());
  }

  Future<void> _initialize() async {
    try {
      await initLanguage(ref);
    } catch (e) {
      Logger.error('Dashboard', 'Could not load language preferences: $e');
    }
    if (!mounted) return;
    _languagesReady = true;
    unawaited(_init());
    unawaited(_runStartupTasks());
  }

  Future<void> _runStartupTasks() async {
    try {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      await checkForUpdate();
      if (mounted) setState(() {});
    } catch (e) {
      Logger.error('Dashboard', 'Startup task failed: $e');
    }
  }

  Future<void> _init() async {
    if (!mounted) return;
    final generation = ++_loadGeneration;
    setState(() {
      loading = true;
      _recommendationsUnavailable = false;
      loveShuffled = [];
      partyShuffled = [];
      trending = [];
      newReleases = [];
      chill = [];
      devotional = [];
      _sectionOrder = List.of(_HomeSection.values)..shuffle();
    });

    try {
      final selected = _languageNotifier.value;
      final langs = selected.isEmpty ? ['tamil'] : List<String>.from(selected);
      final api = ref.read(dashboardApiProvider);
      final playlistFuture = Future.wait(
        langs.map((language) => api.searchPlaylists(query: '$language music', limit: 20)),
      );
      final albumFuture = Future.wait(langs.map((language) => api.searchAlbums(query: '$language music', limit: 20)));
      final artistFuture = Future.wait(langs.map((language) => api.searchArtists(query: '$language music', limit: 10)));
      final offlineFuture = _offlineInitialization ??= offlineManager.init();

      final foundPlaylists = (await playlistFuture).expand((result) => result?.results ?? <Playlist>[]).toList();
      final foundAlbums = (await albumFuture).expand((result) => result).toList();
      final foundArtists = (await artistFuture).expand((result) => result?.results ?? <Artist>[]).toList();
      try {
        await offlineFuture;
      } catch (e) {
        Logger.error('Dashboard', 'Could not load offline songs: $e');
      }
      if (!mounted || generation != _loadGeneration) return;

      playlists = foundPlaylists.where(_isUsablePlaylist).toList();
      latestTamilPlayList = playlists;
      latestTamilAlbums = foundAlbums;
      artists = foundArtists
          .map(
            (artist) => ArtistDetails(
              id: artist.id,
              title: artist.title,
              type: artist.type,
              url: artist.url,
              images: artist.images,
            ),
          )
          .toList();
      artists.shuffle();
      _recommendationsUnavailable = playlists.isEmpty && foundAlbums.isEmpty && artists.isEmpty;
      freqplaylists = ref.read(frequentPlaylistsProvider).where(_isUsablePlaylist).take(10).toList();
      albums = ref
          .read(frequentAlbumsProvider)
          .where((album) => album.title.trim().isNotEmpty && album.id.startsWith('MPREb_'))
          .take(10)
          .toList();
      albums.shuffle();
      _buildFreqRecent();

      final mid = (playlists.length / 2).ceil();
      topLatest = List.of(playlists.take(mid))..shuffle();
      fresh = List.of(playlists.skip(mid))..shuffle();
      final albumMid = (foundAlbums.length / 2).ceil();
      topLatestAlbum = List.of(foundAlbums.take(albumMid))..shuffle();
      freshAlbum = List.of(foundAlbums.skip(albumMid))..shuffle();
      setState(() => loading = false);
      if (!_recommendationsUnavailable) unawaited(_refreshGridMetadata(generation));

      final shelves = await Future.wait([
        _searchPlaylistShelf(api, langs, (language) => 'trending $language music'),
        _searchPlaylistShelf(api, langs, (language) => 'new songs $language'),
        _searchPlaylistShelf(api, langs, (language) => 'chill $language music'),
        _searchPlaylistShelf(api, langs, (language) => 'devotional $language music'),
        _searchPlaylistShelf(api, langs, (language) => 'love $language'),
        _searchPlaylistShelf(api, langs, (language) => 'party $language'),
      ]);
      if (!mounted || generation != _loadGeneration) return;
      trending = shelves[0];
      newReleases = shelves[1];
      chill = shelves[2];
      devotional = shelves[3];
      loveShuffled = shelves[4];
      partyShuffled = shelves[5];
      _recommendationsUnavailable =
          playlists.isEmpty && foundAlbums.isEmpty && artists.isEmpty && shelves.every((shelf) => shelf.isEmpty);
      setState(() {});
    } catch (e, st) {
      if (mounted && generation == _loadGeneration) {
        setState(() => _recommendationsUnavailable = true);
      }
      Logger.error('Dashboard', '[_init] Error occurred: $e');
      Logger.error('Dashboard', 'Stack trace', stackTrace: st);
    } finally {
      if (mounted && generation == _loadGeneration && loading) {
        setState(() => loading = false);
      }
    }
  }

  bool _isUsablePlaylist(Playlist playlist) =>
      playlist.title.trim().isNotEmpty &&
      (playlist.id.startsWith('VL') || playlist.id.startsWith('PL') || playlist.id.startsWith('RD'));

  Future<List<Playlist>> _searchPlaylistShelf(
    YoutubeAPI api,
    List<String> languages,
    String Function(String language) queryForLanguage,
  ) async {
    final results = await Future.wait(
      languages.map((language) => api.searchPlaylists(query: queryForLanguage(language), limit: 12)),
    );
    final unique = <String, Playlist>{};
    for (final playlist in results.expand((result) => result?.results ?? <Playlist>[])) {
      if (_isUsablePlaylist(playlist)) unique.putIfAbsent(playlist.id, () => playlist);
    }
    final playlists = unique.values.toList()..shuffle();
    return playlists;
  }

  void _buildFreqRecent() {
    final unique = <String, Playlist>{};
    final freshById = {for (final playlist in latestTamilPlayList) playlist.id: playlist};
    for (final playlist in [...freqplaylists.take(3), ...latestTamilPlayList]) {
      unique.putIfAbsent(playlist.id, () => freshById[playlist.id] ?? playlist);
    }
    freqRecentPlaylists = unique.values.take(7).toList();

    if (freqRecentPlaylists.length.isEven && freqRecentPlaylists.isNotEmpty) {
      freqRecentPlaylists.removeLast();
    }
  }

  Future<void> _refreshGridMetadata(int generation) async {
    final needsDetails = freqRecentPlaylists
        .where((p) => p.summary.trim().isEmpty && p.description.trim().isEmpty)
        .toList();
    final fetched = await Future.wait(
      needsDetails.map(
        (p) => ref.read(dashboardApiProvider).fetchPlaylistById(playlistId: p.id, refreshMetadata: true),
      ),
    );
    if (!mounted || generation != _loadGeneration) return;
    final updated = <String, Playlist>{};
    for (var i = 0; i < needsDetails.length; i++) {
      final original = needsDetails[i];
      final details = fetched[i];
      if (details == null || (details.summary.trim().isEmpty && details.songCount == null)) continue;
      updated[original.id] = Playlist(
        id: original.id,
        title: original.title,
        type: original.type,
        url: original.url,
        images: original.images.isEmpty ? details.images : original.images,
        description: details.description,
        summary: details.summary,
        language: original.language,
        songCount: details.songCount ?? original.songCount,
        explicitContent: original.explicitContent,
        songs: original.songs,
        artists: original.artists,
      );
    }
    if (updated.isNotEmpty) {
      setState(() {
        freqRecentPlaylists = freqRecentPlaylists.map((p) => updated[p.id] ?? p).toList();
      });
    }
  }

  void _initInternetChecker() {
    _internetSubscription = ref.read(dashboardConnectionProvider).listen((status) {
      if (status == InternetStatus.disconnected) {
        hasInternet.value = false;
      } else {
        hasInternet.value = true;
      }
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    // Watch language listener
    ref.watch(languageNotifierProvider);

    return Scaffold(
      backgroundColor: spotifyBgColor,
      appBar: AppBar(backgroundColor: spotifyBgColor, elevation: 0, title: _buildHeader()),
      body: loading
          ? ListView(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
              children: [
                if (_showWaitingCard)
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: GeneralCards(
                        onClose: () {
                          _showWaitingCard = false;
                          setState(() {});
                        },
                      ),
                    ),
                  ),
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
                  if (_recommendationsUnavailable)
                    EmptyState(
                      icon: LucideIcons.music2,
                      title: 'Recommendations unavailable',
                      subtitle: 'We could not load music for you right now.',
                      compact: true,
                      action: TextButton(onPressed: _init, child: const Text('Try again')),
                    ),
                  if (isAppUpdateAvailable && _showUpdateAvailable)
                    if (isAppUpdateAvailable && _showUpdateAvailable)
                      Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 600),
                          child: GeneralCards(
                            iconPath: 'assets/icons/alert.png',
                            title: 'Update Available!',
                            content: 'Please update the app to enjoy the best experience and latest features.',
                            downloadUrl: 'https://github.com/Harish-Srinivas-07/hivefy/releases/latest',
                            onClose: () {
                              _showUpdateAvailable = false;
                              setState(() {});
                            },
                          ),
                        ),
                      ),
                  for (final section in _sectionOrder)
                    KeyedSubtree(key: ValueKey(section), child: _buildHomeSection(section)),
                  const SizedBox(height: 60),
                  makeItHappenCard(),
                  const SizedBox(height: 100),
                ],
              ),
            ),
    );
  }

  Widget _buildHomeSection(_HomeSection section) => switch (section) {
    _HomeSection.topLatest => _sectionList('Top Latest', topLatest),
    _HomeSection.biggestHits => _sectionAlbumList("Today's biggest hits", topLatestAlbum),
    _HomeSection.fresh => _sectionList('Fresh', fresh),
    _HomeSection.trending => _sectionList('Trending now', trending),
    _HomeSection.newReleases => _sectionList('New releases', newReleases),
    _HomeSection.chill => _sectionList('Chill', chill),
    _HomeSection.devotional => _sectionList('Devotional', devotional),
    _HomeSection.party => _sectionList('Party Mode', partyShuffled),
    _HomeSection.artists => _sectionArtistList('Fav Artists', artists),
    _HomeSection.recentAlbums => _sectionAlbumList('Recent Albums', albums),
    _HomeSection.recommended => _sectionAlbumList('Recommended for today', freshAlbum),
    _HomeSection.love => _sectionList('Always Love', loveShuffled),
  };

  Widget _buildHeader() {
    return ValueListenableBuilder(
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
            const SizedBox(width: 15),
            const Text(
              'Hivefy',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
            ),
          ],
        );
      },
    );
  }

  Widget _sectionGrid(List<Playlist> playlists) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final combined = [Playlist(id: 'liked', title: 'Liked Songs', type: 'custom', url: '', images: []), ...playlists];

    // Only take first 10 for the grid
    final displayList = combined.take(12).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: displayList.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: MediaQuery.of(context).size.width > 600 ? 3 : 3.5,
            ),
            itemBuilder: (context, index) {
              final playlist = displayList[index];
              return StaggeredAppearance(index: index, child: _gridCard(playlist));
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _gridCard(Playlist p) {
    final isSpecial = p.id == 'liked' || p.id == 'all';
    final img = p.images.isNotEmpty ? p.images.first.url : '';
    final likedCount = ref.watch(likedSongsProvider).length;
    final subtitle = p.id == 'liked' ? songCountLabel(likedCount) : homePlaylistSubtitle(p);

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
        } else {
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
          borderRadius: BorderRadius.circular(HomeCardTheme.radius),
          boxShadow: [BoxShadow(color: Colors.black.withAlpha(70), blurRadius: 4, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(HomeCardTheme.radius),
                bottomLeft: Radius.circular(HomeCardTheme.radius),
              ),
              child: isSpecial
                  ? Container(
                      height: double.infinity,
                      width: 50,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: p.id == 'liked'
                              ? [Colors.purpleAccent, Colors.deepPurple]
                              : [spotifyGreen, Colors.teal],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Icon(p.id == 'liked' ? Icons.favorite : Icons.library_music, color: Colors.white),
                    )
                  : (img.isNotEmpty
                        ? CacheNetWorkImg(url: img, width: 50, height: double.infinity, fit: BoxFit.cover)
                        : Container(
                            width: 50,
                            height: double.infinity,
                            color: Colors.grey[800],
                            child: const Icon(Icons.album, color: Colors.white),
                          )),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.title, style: HomeCardTheme.title, overflow: TextOverflow.ellipsis, maxLines: 1),
                    if (subtitle.isNotEmpty)
                      Text(subtitle, style: HomeCardTheme.subtitle, overflow: TextOverflow.ellipsis, maxLines: 1),
                  ],
                ),
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
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            height: 220,
            child: PageView.builder(
              controller: PageController(viewportFraction: MediaQuery.of(context).size.width > 600 ? 0.22 : 0.45),
              padEnds: false,
              physics: const BouncingScrollPhysics(),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final playlist = list[index];
                return StaggeredAppearance(
                  index: index,
                  child: Padding(padding: const EdgeInsets.only(left: 16), child: _playlistCard(playlist)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _playlistCard(Playlist playlist) {
    final imageUrl = playlist.images.isNotEmpty ? playlist.images.first.url : '';
    final subtitle = playlist.artists.isNotEmpty
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
          HomeArtwork(imageUrl: imageUrl),
          const SizedBox(height: 6),
          Flexible(
            child: Text(playlist.title, style: HomeCardTheme.title, overflow: TextOverflow.ellipsis, maxLines: 1),
          ),
          if (subtitle.isNotEmpty)
            Flexible(
              child: Text(subtitle, style: HomeCardTheme.subtitle, overflow: TextOverflow.ellipsis, maxLines: 1),
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

    final PageController controller = PageController(
      viewportFraction: MediaQuery.of(context).size.width > 600 ? 0.18 : 0.35,
    );

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
              return StaggeredAppearance(
                index: index,
                child: AnimatedBuilder(
                  animation: controller,
                  builder: (context, child) {
                    double scale = 1.0;
                    if (controller.position.haveDimensions) {
                      double page = controller.page ?? controller.initialPage.toDouble();
                      scale = (1 - ((page - index).abs() * 0.3)).clamp(0.95, 1.0);
                    }
                    return Transform.scale(scale: scale, child: child);
                  },
                  child: _artistCard(artists[index]),
                ),
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
            backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
            backgroundColor: Colors.grey.shade800,
            child: imageUrl.isEmpty ? const Icon(Icons.person, color: Colors.white, size: 30) : null,
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 100,
            child: Column(
              children: [
                Text(
                  artist.title,
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
                Text(
                  artist.dominantLanguage,
                  style: HomeCardTheme.subtitle,
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
              controller: PageController(viewportFraction: MediaQuery.of(context).size.width > 600 ? 0.22 : 0.45),
              padEnds: false,
              physics: const BouncingScrollPhysics(),
              itemCount: albums.length,
              itemBuilder: (context, index) {
                return StaggeredAppearance(
                  index: index,
                  child: Padding(padding: const EdgeInsets.only(left: 16), child: _albumCard(albums[index])),
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
          HomeArtwork(imageUrl: imageUrl),

          const SizedBox(height: 6),
          Text(
            album.title,
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          Text(
            album.artist,
            style: TextStyle(color: Colors.white38, fontWeight: FontWeight.w300, fontSize: 12),
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
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
      ),
    );
  }
}
