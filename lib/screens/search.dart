import 'package:flutter/material.dart';
import 'package:flutter_swipe_action_cell/core/cell.dart';
import 'package:iconly/iconly.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:page_transition/page_transition.dart';

import '../components/snackbar.dart';
import '../models/database.dart';
import '../models/datamodel.dart';
import '../components/shimmers.dart';
import '../services/audiohandler.dart';
import '../services/jiosaavn.dart';
import '../shared/constants.dart';
import '../shared/player.dart';
import '../utils/format.dart';
import '../utils/theme.dart';
import 'features/language.dart';
import 'features/profile.dart';
import 'views/albumviewer.dart';
import 'views/artistviewer.dart';
import 'views/playlistviewer.dart';

enum SearchFilter { songs, albums, artists, playlists }

class Search extends ConsumerStatefulWidget {
  const Search({super.key});
  @override
  SearchState createState() => SearchState();
}

class SearchState extends ConsumerState<Search> {
  final TextEditingController _controller = TextEditingController();
  List<String> _suggestions = [];
  bool _isLoading = false;
  String? _loadingSongId;

  List<Song> _songs = [];
  List<Album> _albums = [];
  List<Artist> _artists = [];
  List<Playlist> _playlists = [];
  List<SongDetail> _lastSongs = [];
  List<Album> _lastAlbums = [];
  SearchFilter? _selectedFilter;

  final SaavnAPI saavn = SaavnAPI();
  bool _showSuggestions = false;

  bool get _hasNoResults =>
      !_isLoading &&
      !_showSuggestions &&
      _songs.isEmpty &&
      _albums.isEmpty &&
      _artists.isEmpty &&
      _playlists.isEmpty &&
      _controller.text.trim().isEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _init();
    ref.read(languageNotifierProvider).addListener(() {
      if (!mounted) return;
      _init();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _init();
  }

  Future<void> _init() async {
    if (!mounted) return;
    await loadSearchHistory();
    _lastSongs = await loadLastSongs();
    _lastAlbums = await loadLastAlbums();
    if (mounted) setState(() {});
  }

  Widget _buildRecentSection() {
    if (_lastSongs.isEmpty && _lastAlbums.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_lastSongs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: _buildSection(
              "Recently Played Songs",
              _lastSongs,
              (song) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _onSongTap(song),
                child: _buildPlaylistRow(
                  Playlist(
                    id: song.id,
                    title: song.title,
                    images: song.images,
                    url: song.url,
                    type: song.type,
                    language: song.language,
                    explicitContent: song.explicitContent,
                    description: song.description,
                  ),
                  onRemove: () async {
                    await removeLastSong(song.id);
                    _lastSongs = await loadLastSongs();
                    if (mounted) setState(() {});
                  },
                ),
              ),
            ),
          ),
        if (_lastAlbums.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),

            child: _buildSection(
              "Recently Played Albums",
              _lastAlbums,
              (album) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _onAlbumTap(album),
                child: _buildPlaylistRow(
                  Playlist(
                    id: album.id,
                    title: album.title,
                    images: album.images,
                    url: album.url,
                    type: album.type,
                    language: album.language,
                    explicitContent: false,
                    description: album.description,
                  ),
                  onRemove: () async {
                    await removeLastAlbum(album.id);
                    _lastAlbums = await loadLastAlbums();
                    if (mounted) setState(() {});
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _onTextChanged(String value) async {
    if (value.isEmpty) {
      _resetSearch();
      return;
    }

    _isLoading = true;
    _showSuggestions = true;
    if (mounted) setState(() {});

    final results = await saavn.getSearchBoxSuggestions(query: value);

    if (!mounted) return;
    _suggestions = results;
    _isLoading = false;
    if (mounted) setState(() {});
  }

  void _onSuggestionTap(String suggestion, {bool onChange = false}) async {
    if (!onChange) _controller.text = suggestion;
    saveSearchTerm(suggestion);
    setState(() {
      _isLoading = !onChange;
      _showSuggestions = onChange;
      _clearResults();
    });

    String langSpecificSearch =
        '$suggestion ${ref.read(languageNotifierProvider).value}';

    final results = await saavn.globalSearch(langSpecificSearch);

    if (!mounted || results == null) return;

    // Assign results first
    List<Song> songs = results.songs.results;
    List<Artist> artists = results.artists.results;
    List<Album> albums = results.albums.results;
    List<Playlist> playlists = results.playlists.results;

    _songs = songs;
    _artists = artists;
    _albums = albums;
    _playlists = playlists;

    _isLoading = false;
    if (mounted) setState(() {});

    // Fetch extras
    final extraSongs = await saavn.searchSongs(
      query: langSpecificSearch,
      limit: 10,
    );
    if (extraSongs.isNotEmpty) {
      final existingIds = songs.map((s) => s.id).toSet();
      songs.addAll(extraSongs.where((s) => !existingIds.contains(s.id)));
      if (mounted) setState(() {});
    }

    final extraArtistsResponse = await saavn.searchArtists(
      query: langSpecificSearch,
      limit: 10,
    );
    if (extraArtistsResponse != null &&
        extraArtistsResponse.results.isNotEmpty) {
      final existingIds = artists.map((a) => a.id).toSet();
      artists.addAll(
        extraArtistsResponse.results.where((a) => !existingIds.contains(a.id)),
      );
      if (mounted) setState(() {});
    }

    final extraPlaylistsResponse = await saavn.searchPlaylists(
      query: langSpecificSearch,
      limit: 10,
    );

    if (extraPlaylistsResponse != null &&
        extraPlaylistsResponse.results.isNotEmpty) {
      final existingIds = playlists.map((p) => p.id).toSet();

      // Only add playlists that are not already in the list
      final newPlaylists =
          extraPlaylistsResponse.results
              .where((p) => !existingIds.contains(p.id))
              .toList();

      if (newPlaylists.isNotEmpty) {
        playlists.addAll(newPlaylists);
      }
      if (mounted) setState(() {});
    }

    _songs = songs;
    _artists = artists;
    _albums = albums;
    _playlists = playlists;

    _isLoading = false;
    if (mounted) setState(() {});
  }

  void _clearText() {
    _controller.clear();
    _selectedFilter = null;
    _resetSearch();
    _init();
  }

  void _resetSearch() {
    _suggestions = [];
    _songs = [];
    _albums = [];
    _artists = [];
    _playlists = [];
    _showSuggestions = true;
    _isLoading = false;
    setState(() {});
  }

  void _clearResults() {
    _songs = [];
    _albums = [];
    _artists = [];
    _playlists = [];
    _suggestions = [];
    if (mounted) setState(() {});
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Text(
        title,
        style: TextStyle(
          fontSize: title.toLowerCase().contains('recently') ? 16 : 18,
          fontWeight: FontWeight.w600,
          color:
              title.toLowerCase().contains('recently')
                  ? Colors.white54
                  : Colors.white,
        ),
      ),
    );
  }

  Widget _buildItemImage(String url, String type) {
    return ClipRRect(
      borderRadius:
          type.toLowerCase().contains('artist')
              ? BorderRadius.circular(50)
              : BorderRadius.circular(4),
      child: CacheNetWorkImg(
        url: url,
        width: 50,
        height: 50,
        fit: BoxFit.cover,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }

  Widget _buildPlaylistRow(Playlist p, {VoidCallback? onRemove}) {
    final imageUrl = p.images.isNotEmpty ? p.images.last.url : '';

    final content = Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildItemImage(imageUrl, p.type),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.title,
                  style: TextStyle(
                    color:
                        ref.watch(currentSongProvider)?.id == p.id
                            ? spotifyGreen
                            : Colors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                _buildSubtitleRow(p),
              ],
            ),
          ),
          if (onRemove != null)
            IconButton(
              icon: const Icon(Icons.close, color: Colors.grey, size: 18),
              onPressed: onRemove,
            ),
        ],
      ),
    );

    // Only wrap with SwipeActionCell if type is "Song"
    if (p.type == "song") {
      return SwipeActionCell(
        backgroundColor: Colors.transparent,
        key: ValueKey(p.id),
        fullSwipeFactor: 0.01,
        editModeOffset: 2,
        leadingActions: [
          SwipeAction(
            color: spotifyGreen,
            icon: Image.asset('assets/icons/add_to_queue.png', height: 20),
            performsFirstActionWithFullSwipe: true,
            onTap: (handler) async {
              final audioHandler = await ref.read(audioHandlerProvider.future);
              final details = await saavn.getSongDetails(ids: [p.id]);
              if (details.isEmpty) return;
              await audioHandler.addSongNext(details.first);
              info('${details.first.title} will play next', Severity.success);
              await handler(false);
            },
          ),
        ],
        child: content,
      );
    } else {
      return content;
    }
  }

  Widget _buildSubtitleRow(Playlist p) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        if (p.description.isNotEmpty)
          Flexible(
            child: Text(
              '${capitalize(p.type.toLowerCase().contains('playlist') ? p.language : p.description)} ',
              style: _subtitleStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (p.type.isNotEmpty && p.description.length < 20)
          Flexible(
            child: Text(
              capitalize(p.type),
              style: _subtitleStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

        if (_loadingSongId == p.id &&
            ref.watch(currentSongProvider)?.id != p.id)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: const SizedBox(
              height: 10,
              width: 10,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: spotifyGreen,
              ),
            ),
          )
        else if (ref.watch(currentSongProvider)?.id == p.id)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Image.asset(
              'assets/icons/player.gif',
              height: 16,
              width: 16,
              fit: BoxFit.contain,
            ),
          ),
      ],
    );
  }

  Widget _buildSearchHistoryRow() {
    if (searchHistory.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Recent Search',
            style: TextStyle(fontSize: 13, color: Colors.white54),
          ),
        ),
        const SizedBox(height: 2),
        SingleChildScrollView(
          padding: EdgeInsets.only(left: 12),
          scrollDirection: Axis.horizontal,
          child: Row(
            children:
                searchHistory.map((term) {
                  return GestureDetector(
                    onTap: () => _onSuggestionTap(term),
                    child: Container(
                      margin: const EdgeInsets.only(right: 3, top: 3),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(term, style: TextStyle(color: Colors.white)),
                    ),
                  );
                }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(left: 16),
      children: [
        if (_selectedFilter != null)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: ChoiceChip(
              label: const Icon(
                Icons.close_rounded,
                size: 20,
                color: Colors.white70,
              ),
              selected: false,
              onSelected: (_) => setState(() => _selectedFilter = null),
              backgroundColor: Colors.white10,
              color: WidgetStateProperty.resolveWith<Color?>((states) {
                return Colors.grey.shade900;
              }),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(color: Colors.grey.shade800, width: 0),
              ),
              visualDensity: const VisualDensity(vertical: -2, horizontal: 0),
              padding: const EdgeInsets.all(3),
            ),
          ),

        for (final type in SearchFilter.values)
          Padding(
            padding: const EdgeInsets.only(right: 3),
            child: ChoiceChip(
              label: Text(type.name[0].toUpperCase() + type.name.substring(1)),
              selected: _selectedFilter == type,
              selectedColor: spotifyGreen.withAlpha(51),
              checkmarkColor: spotifyGreen,
              onSelected:
                  (_) => setState(() {
                    _selectedFilter = _selectedFilter == type ? null : type;
                  }),
              labelStyle: TextStyle(
                color: _selectedFilter == type ? spotifyGreen : Colors.white,
              ),
              backgroundColor: Colors.grey[900],
              showCheckmark: false,
              visualDensity: const VisualDensity(vertical: -2, horizontal: 0),
              color: WidgetStateProperty.resolveWith<Color?>((states) {
                return Colors.grey.shade900;
              }),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color:
                      _selectedFilter == type
                          ? spotifyGreen
                          : Colors.grey.shade800,
                  width: _selectedFilter == type ? 1 : 0,
                ),
              ),
            ),
          ),
      ],
    );
  }

  TextStyle get _subtitleStyle => TextStyle(color: Colors.grey, fontSize: 12);

  @override
  Widget build(BuildContext context) {
    // Watch language listener
    ref.watch(languageNotifierProvider);

    return Scaffold(
      backgroundColor: spotifyBgColor,
      body: SafeArea(child: _buildSearchContent()),
    );
  }

  Widget _buildHeader() {
    return ValueListenableBuilder(
      valueListenable: profileRefreshNotifier,
      builder: (context, value, child) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            GestureDetector(
              onTap: () => scaffoldKey.currentState?.openDrawer(),
              behavior: HitTestBehavior.opaque,
              child: CircleAvatar(
                radius: 18,
                backgroundImage:
                    (profileFile != null && profileFile!.existsSync())
                        ? FileImage(profileFile!)
                        : const AssetImage('assets/icons/logo.png')
                            as ImageProvider,
              ),
            ),
            const Text(
              'Search',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            GestureDetector(
              onTap: () {
                info('Under construction, will update soon!', Severity.info);
              },
              child: const Icon(
                Icons.camera_alt_outlined,
                size: 28,
                color: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearchBox() {
    return Container(
      // padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Icon(IconlyLight.search, color: Colors.grey),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _controller,
              cursorColor: spotifyGreen,
              style: TextStyle(color: Colors.white),
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              onChanged: _onTextChanged,
              onSubmitted: (value) => _onSuggestionTap(value.trim()),
              decoration: InputDecoration(
                hintText: "What do you want to listen to?",
                hintStyle: TextStyle(color: Colors.grey),
                border: InputBorder.none,
              ),
            ),
          ),
          if (_controller.text.isNotEmpty)
            GestureDetector(
              onTap: _clearText,
              child: const Padding(
                padding: EdgeInsets.only(right: 16, left: 8),
                child: Icon(Icons.close, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchContent() {
    final bool isEmpty = _hasNoResults || _controller.text.trim().isEmpty;

    return CustomScrollView(
      slivers: [
        // HEADER → normal scroll
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: _buildHeader(),
          ),
        ),

        // SEARCH BOX → sticky
        SliverPersistentHeader(
          pinned: true,
          delegate: StickyHeaderDelegate(
            height: 65,
            child: Container(
              color: spotifyBgColor,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: _buildSearchBox(),
            ),
          ),
        ),

        // Filter bar
        if (!isEmpty && !_showSuggestions)
          SliverPersistentHeader(
            pinned: true,
            delegate: StickyHeaderDelegate(
              height: 45,
              child: _buildFilterBar(),
            ),
          ),

        // LOADING SHIMMER or RESULTS
        if (_isLoading)
          buildSearchShimmerSliver()
        else
          SliverList(
            delegate: SliverChildListDelegate([
              if (isEmpty) ...[
                _buildSearchHistoryRow(),
                _buildRecentSection(),
                _buildNoResults(),
                const SizedBox(height: 100),
              ] else ...[
                if (_showSuggestions && _controller.text.isNotEmpty)
                  ..._buildSuggestions(),
                if (_songs.isNotEmpty &&
                    (_selectedFilter == null ||
                        _selectedFilter == SearchFilter.songs))
                  _buildSection("Songs", _songs, (s) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _onSongTap(s),
                      child: _buildPlaylistRow(
                        Playlist(
                          id: s.id,
                          title: s.title,
                          images: s.images,
                          url: s.url,
                          type: s.type,
                          language: s.language,
                          explicitContent: false,
                          description: s.album,
                        ),
                      ),
                    );
                  }),

                if (_albums.isNotEmpty &&
                    (_selectedFilter == null ||
                        _selectedFilter == SearchFilter.albums))
                  _buildSection("Albums", _albums, (a) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _onAlbumTap(a),
                      child: _buildPlaylistRow(
                        Playlist(
                          id: a.id,
                          title: a.title,
                          images: a.images,
                          url: a.url,
                          type: a.type,
                          language: a.language,
                          explicitContent: false,
                          description: a.artist,
                        ),
                      ),
                    );
                  }),

                if (_artists.isNotEmpty &&
                    (_selectedFilter == null ||
                        _selectedFilter == SearchFilter.artists))
                  _buildSection("Artists", _artists, (a) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _onArtistTap(a),
                      child: _buildPlaylistRow(
                        Playlist(
                          id: a.id,
                          title: a.title,
                          images: a.images,
                          url: '',
                          type: a.type,
                          language: '',
                          explicitContent: false,
                          description: a.description,
                        ),
                      ),
                    );
                  }),

                if (_playlists.isNotEmpty &&
                    (_selectedFilter == null ||
                        _selectedFilter == SearchFilter.playlists))
                  _buildSection("Playlists", _playlists, (p) {
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _onPlaylistTap(p),
                      child: _buildPlaylistRow(p),
                    );
                  }),
                const SizedBox(height: 100),
              ],
            ]),
          ),
      ],
    );
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 30),
          Text(
            'Play what you love',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Search for artists, songs, and more',
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSuggestions() {
    return _suggestions.take(5).map((s) {
      return GestureDetector(
        onTap: () => _onSuggestionTap(s),
        child: Container(
          height: 50,
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.grey[800],
                ),
                child: const Icon(Icons.search, color: Colors.grey, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  s,
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                  ),
                ),
              ),
              Transform.rotate(
                angle: 45 * 3.1415926535 / 180,
                child: const Icon(
                  Icons.arrow_upward,
                  color: Colors.grey,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _buildSection<T>(
    String title,
    List<T> items,
    Widget Function(T) builder,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [_buildSectionTitle(title), ...items.map(builder)],
    );
  }

  void _onSongTap(Song song) async {
    FocusScope.of(context).unfocus();
    setState(() => _loadingSongId = song.id);

    final details = await saavn.getSongDetails(ids: [song.id]);
    if (details.isEmpty) {
      setState(() => _loadingSongId = null);
      return;
    }
    final loadedSong = details.first;

    String? imageUrl =
        loadedSong.images.isNotEmpty ? loadedSong.images.last.url : null;

    if (imageUrl != null) {
      final dominant = await getDominantColorFromImage(imageUrl);

      if (!mounted) return;

      ref.read(playerColourProvider.notifier).state = getDominantDarker(
        dominant,
      );

      // Save in background
      Future(() async {
        await storeLastSongs([loadedSong]);
        _lastSongs = await loadLastSongs();
        if (mounted) setState(() {});
      });
    }

    final audioHandler = await ref.read(audioHandlerProvider.future);
    final currentSong = ref.read(currentSongProvider);
    final isCurrentSong = currentSong?.id == loadedSong.id;

    if (!isCurrentSong) {
      await audioHandler.playSongNow(loadedSong, insertNext: true);
    } else {
      (await audioHandler.playerStateStream.first).playing
          ? await audioHandler.pause()
          : await audioHandler.play();
    }

    setState(() => _loadingSongId = null);
  }

  void _onAlbumTap(Album album) {
    FocusScope.of(context).unfocus();

    if (!mounted) return;

    Navigator.of(context).push(
      PageTransition(
        type: PageTransitionType.rightToLeft,
        duration: const Duration(milliseconds: 300),
        child: AlbumViewer(albumId: album.id),
      ),
    );

    // Save and reload in background
    Future(() async {
      await storeLastAlbums([album]);
      _lastAlbums = await loadLastAlbums();
      if (mounted) setState(() {});
    });
  }

  void _onPlaylistTap(Playlist p) {
    FocusScope.of(context).unfocus();
    Navigator.of(context).push(
      PageTransition(
        type: PageTransitionType.rightToLeft,
        duration: const Duration(milliseconds: 300),
        child: PlaylistViewer(playlistId: p.id),
      ),
    );
  }

  void _onArtistTap(Artist artist) {
    Navigator.of(context).push(
      PageTransition(
        type: PageTransitionType.rightToLeft,
        duration: const Duration(milliseconds: 300),
        child: ArtistViewer(artistId: artist.id),
      ),
    );
  }
}

// ---------------- STICKY HEADER --------------------
class StickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  StickyHeaderDelegate({required this.child, this.height = 60});

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // SizedBox.expand ensures the returned child fills the header's allocated height
    return SizedBox(
      height: height,
      child: Material(
        // optional: keep background / elevation behavior consistent
        color: spotifyBgColor,
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant StickyHeaderDelegate old) {
    return old.height != height || old.child != child;
  }
}
