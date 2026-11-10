import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../components/sticky_header_delegate.dart';
import '../components/staggered_appearance.dart';
import 'package:flutter_swipe_action_cell/core/cell.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:page_transition/page_transition.dart';
import 'package:shimmer/shimmer.dart';

import '../components/snackbar.dart';
import '../components/empty_state.dart';
import '../models/database.dart';
import '../models/datamodel.dart';
import '../components/shimmers.dart';
import '../services/audiohandler.dart';
import '../services/youtube.dart';
import '../shared/constants.dart';
import '../shared/player.dart';
import '../utils/format.dart';
import '../utils/library_metadata.dart';
import '../utils/theme.dart';
import 'features/language.dart';
import 'features/profile.dart';
import 'views/albumviewer.dart';
import 'views/artistviewer.dart';
import 'views/explorecategory.dart';
import 'views/playlistviewer.dart';

enum SearchFilter { songs, albums, artists, playlists }

class Search extends ConsumerStatefulWidget {
  final YoutubeAPI? searchApi;
  const Search({super.key, this.searchApi});
  @override
  SearchState createState() => SearchState();
}

class SearchState extends ConsumerState<Search> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  late final Widget _searchBox;
  List<String> _suggestions = [];
  bool _isLoading = false;
  bool _hasLoadedSuggestions = false;
  String? _loadingSongId;
  int _searchGeneration = 0;

  List<Song> _songs = [];
  List<Album> _albums = [];
  List<Artist> _artists = [];
  List<Playlist> _playlists = [];
  List<SongDetail> _lastSongs = [];
  List<Album> _lastAlbums = [];
  List<ExploreCategory> _exploreCategories = [];
  bool _exploreLoading = true;
  SearchFilter? _selectedFilter;

  late final YoutubeAPI youtube = widget.searchApi ?? YoutubeAPI();
  bool _showSuggestions = false;

  @override
  void dispose() {
    _controller.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _searchBox = _buildSearchBox();
    _init();
    _loadExploreCategories();
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

  Future<void> _loadExploreCategories() async {
    final categories = await youtube.fetchExploreCategories();
    if (!mounted) return;
    setState(() {
      _exploreCategories = categories;
      _exploreLoading = false;
    });
    _loadExploreArtwork(categories);
  }

  Future<void> _loadExploreArtwork(List<ExploreCategory> categories) async {
    const batchSize = 4;
    for (var start = 0; start < categories.length; start += batchSize) {
      final end = (start + batchSize).clamp(0, categories.length).toInt();
      final batch = categories.sublist(start, end);
      final previews = await Future.wait(
        batch.map((category) => youtube.fetchExploreCategoryPlaylists(category, limit: 1)),
      );
      if (!mounted) return;

      for (var offset = 0; offset < batch.length; offset++) {
        final categoryIndex = start + offset;
        if (_exploreCategories[categoryIndex].imageUrl.isNotEmpty) continue;
        final images = previews[offset].expand((playlist) => playlist.images);
        final image = images.map((source) => source.url).firstWhere((url) => url.isNotEmpty, orElse: () => '');
        if (image.isNotEmpty) {
          _exploreCategories[categoryIndex] = _exploreCategories[categoryIndex].withImageUrl(image);
        }
      }
      setState(() {});
    }
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
    final generation = ++_searchGeneration;
    if (value.isEmpty) {
      _resetSearch();
      return;
    }

    _isLoading = true;
    _showSuggestions = true;
    if (mounted) setState(() {});

    final results = await youtube.getSearchBoxSuggestions(query: value);

    if (!mounted || generation != _searchGeneration) return;
    _suggestions = results;
    _hasLoadedSuggestions = true;
    _isLoading = false;
    if (mounted) setState(() {});
  }

  void _onSuggestionTap(String suggestion, {bool onChange = false}) async {
    if (!onChange) {
      _searchFocus.unfocus();
      _controller.text = suggestion;
    }
    saveSearchTerm(suggestion);
    setState(() {
      _isLoading = !onChange;
      _showSuggestions = onChange;
      if (!onChange) _hasLoadedSuggestions = false;
      _clearResults();
    });

    final generation = ++_searchGeneration;
    final query = suggestion.trim();
    if (query.isEmpty) {
      _resetSearch();
      return;
    }

    final songsFuture = youtube.searchSongs(query: query, limit: 10);
    final albumsFuture = youtube.searchAlbums(query: query, limit: 10);
    final artistsFuture = youtube.searchArtists(query: query, limit: 10);
    final playlistsFuture = youtube.searchPlaylists(query: query, limit: 10);
    final songs = await songsFuture;
    final albums = await albumsFuture;
    final artists = await artistsFuture;
    final playlists = await playlistsFuture;
    if (!mounted || generation != _searchGeneration) return;
    setState(() {
      _songs = songs;
      _albums = albums;
      _artists = artists?.results ?? [];
      _playlists = playlists?.results ?? [];
      _isLoading = false;
    });
  }

  void _clearText() {
    _controller.clear();
    _selectedFilter = null;
    _resetSearch();
    _init();
  }

  void _resetSearch() {
    _searchGeneration++;
    _suggestions = [];
    _hasLoadedSuggestions = false;
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
          color: title.toLowerCase().contains('recently') ? Colors.white54 : Colors.white,
        ),
      ),
    );
  }

  Widget _buildItemImage(String url, String type) {
    return ClipRRect(
      borderRadius: type.toLowerCase().contains('artist') ? BorderRadius.circular(50) : BorderRadius.circular(4),
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
    final isLoadingSong = p.type == 'song' && _loadingSongId == p.id;
    final title = Text(
      p.title,
      style: TextStyle(
        color: ref.watch(currentSongProvider)?.id == p.id ? spotifyGreen : Colors.white,
        fontWeight: FontWeight.w500,
        fontSize: 16,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

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
                isLoadingSong
                    ? Shimmer.fromColors(
                        enabled: !MediaQuery.disableAnimationsOf(context),
                        baseColor: Colors.white54,
                        highlightColor: Colors.white,
                        child: title,
                      )
                    : title,
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
              final details = await youtube.getSongDetails(ids: [p.id]);
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
    final isPlaylist = p.type.toLowerCase().contains('playlist');
    final playlistSubtitle = playlistLibrarySubtitle(p);

    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        if (isPlaylist)
          Flexible(
            child: Text(
              playlistSubtitle == 'Playlist' && p.songCount != null ? '${p.songCount} songs' : playlistSubtitle,
              style: _subtitleStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (!isPlaylist && p.description.isNotEmpty)
          Flexible(
            child: Text(
              '${capitalize(p.description)} ',
              style: _subtitleStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (!isPlaylist && p.type.isNotEmpty && p.description.length < 20)
          Flexible(
            child: Text(capitalize(p.type), style: _subtitleStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),

        if (ref.watch(currentSongProvider)?.id == p.id)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Image.asset('assets/icons/player.gif', height: 16, width: 16, fit: BoxFit.contain),
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
          child: Text('Recent Search', style: TextStyle(fontSize: 13, color: Colors.white54)),
        ),
        const SizedBox(height: 2),
        SingleChildScrollView(
          padding: EdgeInsets.only(left: 12),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: searchHistory.map((term) {
              return GestureDetector(
                onTap: () => _onSuggestionTap(term),
                child: Container(
                  constraints: BoxConstraints(maxWidth: (MediaQuery.sizeOf(context).width * 0.65).clamp(0.0, 200.0)),
                  margin: const EdgeInsets.only(right: 3, top: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(20)),
                  child: Text(
                    term,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white),
                  ),
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
              label: const Icon(Icons.close_rounded, size: 20, color: Colors.white70),
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
              onSelected: (_) => setState(() {
                _selectedFilter = _selectedFilter == type ? null : type;
              }),
              labelStyle: TextStyle(color: _selectedFilter == type ? spotifyGreen : Colors.white),
              backgroundColor: Colors.grey[900],
              showCheckmark: false,
              visualDensity: const VisualDensity(vertical: -2, horizontal: 0),
              color: WidgetStateProperty.resolveWith<Color?>((states) {
                return Colors.grey.shade900;
              }),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: BorderSide(
                  color: _selectedFilter == type ? spotifyGreen : Colors.grey.shade800,
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
                backgroundImage: (profileFile != null && profileFile!.existsSync())
                    ? FileImage(profileFile!)
                    : const AssetImage('assets/icons/logo.png') as ImageProvider,
              ),
            ),
            const Text(
              'Search',
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            GestureDetector(
              onTap: () {
                info('Under construction, will update soon!', Severity.info);
              },
              child: const Icon(Icons.camera_alt_outlined, size: 28, color: Colors.white),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSearchBox() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _controller,
      builder: (context, value, _) => TextField(
        key: const ValueKey('search_input'),
        controller: _controller,
        focusNode: _searchFocus,
        cursorColor: spotifyGreen,
        style: const TextStyle(color: Colors.white),
        textInputAction: TextInputAction.search,
        onChanged: _onTextChanged,
        onSubmitted: (value) => _onSuggestionTap(value.trim()),
        decoration: InputDecoration(
          hintText: 'What do you want to listen to?',
          hintStyle: const TextStyle(color: Colors.grey),
          filled: true,
          fillColor: Colors.grey[900],
          prefixIcon: const Icon(LucideIcons.search, color: Colors.grey),
          suffixIcon: value.text.isNotEmpty
              ? IconButton(
                  onPressed: _clearText,
                  icon: const Icon(Icons.close, color: Colors.grey),
                  tooltip: 'Clear search',
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildSearchContent() {
    final bool isEmpty = _controller.text.trim().isEmpty;
    final hasResults = switch (_selectedFilter) {
      SearchFilter.songs => _songs.isNotEmpty,
      SearchFilter.albums => _albums.isNotEmpty,
      SearchFilter.artists => _artists.isNotEmpty,
      SearchFilter.playlists => _playlists.isNotEmpty,
      null => _songs.isNotEmpty || _albums.isNotEmpty || _artists.isNotEmpty || _playlists.isNotEmpty,
    };

    return CustomScrollView(
      slivers: [
        // HEADER → normal scroll
        SliverToBoxAdapter(
          child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10), child: _buildHeader()),
        ),

        // SEARCH BOX → sticky
        SliverPersistentHeader(
          pinned: true,
          delegate: StickyHeaderDelegate(
            height: 65,
            child: Container(
              color: spotifyBgColor,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              child: _searchBox,
            ),
          ),
        ),

        // Filter bar
        if (!isEmpty && !_showSuggestions)
          SliverPersistentHeader(pinned: true, delegate: StickyHeaderDelegate(height: 45, child: _buildFilterBar())),

        // LOADING SHIMMER or RESULTS
        if (_isLoading && (!_showSuggestions || !_hasLoadedSuggestions))
          buildSearchShimmerSliver()
        else
          SliverList(
            delegate: SliverChildListDelegate([
              if (isEmpty) ...[
                _buildSearchHistoryRow(),
                _buildRecentSection(),
                _buildExploreSection(),
                _buildNoResults(),
                const SizedBox(height: 100),
              ] else ...[
                if (_showSuggestions && _controller.text.isNotEmpty) ..._buildSuggestions(),
                if (!_showSuggestions && !hasResults)
                  EmptyState(
                    icon: LucideIcons.searchX,
                    title: _selectedFilter == null ? 'No results found' : 'No ${_selectedFilter!.name} found',
                    subtitle: 'Try a different search or check your spelling.',
                  ),
                if (_songs.isNotEmpty && (_selectedFilter == null || _selectedFilter == SearchFilter.songs))
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

                if (_albums.isNotEmpty && (_selectedFilter == null || _selectedFilter == SearchFilter.albums))
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

                if (_artists.isNotEmpty && (_selectedFilter == null || _selectedFilter == SearchFilter.artists))
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

                if (_playlists.isNotEmpty && (_selectedFilter == null || _selectedFilter == SearchFilter.playlists))
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
    return const EmptyState(
      icon: LucideIcons.music2,
      title: 'Play what you love',
      subtitle: 'Search for artists, songs, albums, and playlists.',
    );
  }

  Widget _buildExploreSection() {
    const colors = [
      Color(0xFF27876D),
      Color(0xFF203866),
      Color(0xFF9666A8),
      Color(0xFFE90055),
      Color(0xFFB12591),
      Color(0xFF8062A4),
      Color(0xFF223C70),
      Color(0xFFB65A00),
      Color(0xFF8963A8),
      Color(0xFFE92D00),
      Color(0xFFD80F84),
      Color(0xFF087D83),
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle('Explore'),
          if (_exploreLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2)),
            )
          else if (_exploreCategories.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final tileWidth = (constraints.maxWidth - 16) / 2;
                  return Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (var i = 0; i < _exploreCategories.length; i++)
                        _buildExploreTile(_exploreCategories[i], tileWidth, colors[i % colors.length]),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildExploreTile(ExploreCategory category, double width, Color color) {
    return GestureDetector(
      onTap: () {
        FocusScope.of(context).unfocus();
        Navigator.of(context).push(
          PageTransition(
            type: PageTransitionType.rightToLeft,
            duration: const Duration(milliseconds: 300),
            child: ExploreCategoryView(category: category, searchApi: youtube),
          ),
        );
      },
      child: Container(
        width: width,
        height: width / 1.78,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        child: Stack(
          children: [
            Positioned(
              left: 12,
              right: width * 0.38,
              top: 11,
              child: Text(
                category.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            Positioned(
              right: -9,
              bottom: -12,
              child: Transform.rotate(
                angle: 0.32,
                child: Container(
                  width: width * 0.55,
                  height: width * 0.55,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(3),
                    boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 3))],
                  ),
                  child: category.imageUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: CachedNetworkImage(
                            imageUrl: category.imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Shimmer.fromColors(
                              baseColor: Colors.grey.shade800,
                              highlightColor: Colors.grey.shade700,
                              child: Container(color: Colors.grey.shade800),
                            ),
                            errorWidget: (context, url, error) =>
                                const Center(child: Icon(LucideIcons.music2, color: Colors.white70, size: 32)),
                          ),
                        )
                      : const Icon(LucideIcons.music2, color: Colors.white70, size: 32),
                ),
              ),
            ),
          ],
        ),
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
                decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey[800]),
                child: const Icon(Icons.search, color: Colors.grey, size: 28),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  s,
                  style: TextStyle(color: Colors.grey, fontWeight: FontWeight.w500, fontSize: 16),
                ),
              ),
              Transform.rotate(
                angle: 45 * 3.1415926535 / 180,
                child: const Icon(Icons.arrow_upward, color: Colors.grey, size: 18),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _buildSection<T>(String title, List<T> items, Widget Function(T) builder) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(title),
        for (var index = 0; index < items.length; index++)
          StaggeredAppearance(key: ValueKey('$title-$index'), index: index, child: builder(items[index])),
      ],
    );
  }

  void _onSongTap(Song song) async {
    FocusScope.of(context).unfocus();
    setState(() => _loadingSongId = song.id);

    final loadedSong = song is SongDetail
        ? song
        : SongDetail(
            id: song.id,
            title: song.title,
            type: song.type,
            url: song.url,
            images: song.images,
            primaryArtists: song.primaryArtists,
            album: song.album,
            ytVideoId: song.id,
          );

    String? imageUrl = loadedSong.images.isNotEmpty ? loadedSong.images.last.url : null;

    if (imageUrl != null) {
      final dominant = await getDominantColorFromImage(imageUrl);

      if (!mounted) return;

      ref.read(playerColourProvider.notifier).state = getDominantDarker(dominant);

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
      (await audioHandler.playerStateStream.first).playing ? await audioHandler.pause() : await audioHandler.play();
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
