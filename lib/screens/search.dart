import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconly/iconly.dart';
import 'package:page_transition/page_transition.dart';

import '../models/database.dart';
import '../models/datamodel.dart';
import '../models/shimmers.dart';
import '../services/audiohandler.dart';
import '../services/jiosaavn.dart';
import '../shared/constants.dart';
import '../shared/player.dart';
import '../utils/format.dart';
import '../utils/theme.dart';
import 'albumviewer.dart';
import 'artistviewer.dart';
import 'playlistviewer.dart';

class Search extends ConsumerStatefulWidget {
  const Search({super.key});
  @override
  SearchState createState() => SearchState();
}

class SearchState extends ConsumerState<Search> {
  bool _extraSongsLoaded = false;
  bool _extraArtistsLoaded = false;

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
    debugPrint('--> her ethe data $_lastSongs & $_lastAlbums');
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

  Future<void> _fetchExtraSongs() async {
    if (_extraSongsLoaded) return;

    final extraSongs = await saavn.searchSongs(query: _controller.text.trim());

    if (extraSongs.isNotEmpty) {
      final existingIds = _songs.map((s) => s.id).toSet();

      _songs.addAll(
        extraSongs
            .where((s) => !existingIds.contains(s.id))
            .map(
              (s) => Song(
                id: s.id,
                title: s.title,
                images: s.images,
                url: s.url,
                type: s.type,
                language: s.language,
                description: s.description,
              ),
            ),
      );

      _extraSongsLoaded = true;
      setState(() {});
    }
  }

  Future<void> _fetchExtraArtists() async {
    if (_extraArtistsLoaded) return;

    final extraArtistsResponse = await saavn.searchArtists(
      query: _controller.text.trim(),
    );

    if (extraArtistsResponse != null &&
        extraArtistsResponse.results.isNotEmpty) {
      final existingIds = _artists.map((a) => a.id).toSet();

      _artists.addAll(
        extraArtistsResponse.results
            .where((a) => !existingIds.contains(a.id))
            .toList(),
      );

      _extraArtistsLoaded = true;
      setState(() {});
    }
  }

  void _onTextChanged(String value) async {
    if (value.isEmpty) {
      _resetSearch();
      return;
    }

    setState(() {
      _isLoading = true;
      _showSuggestions = true;
    });

    final results = await saavn.getSearchBoxSuggestions(query: value);

    if (!mounted) return;
    setState(() {
      _suggestions = results;
      _isLoading = false;
    });
  }

  void _onSuggestionTap(String suggestion, {bool onChange = false}) async {
    if (!onChange) _controller.text = suggestion;
    saveSearchTerm(suggestion);
    setState(() {
      _isLoading = !onChange;
      _showSuggestions = onChange;
      _clearResults();
    });

    final results = await saavn.globalSearch(suggestion);
    await _fetchExtraSongs();
    await _fetchExtraArtists();

    if (!mounted || results == null) return;

    _songs = results.songs.results;
    _albums = results.albums.results;
    _artists = results.artists.results;
    _playlists = results.playlists.results;
    _isLoading = false;
    setState(() {});
  }

  void _clearText() {
    _controller.clear();
    _resetSearch();
    _init();
  }

  void _resetSearch() {
    setState(() {
      _suggestions = [];
      _songs = [];
      _albums = [];
      _artists = [];
      _playlists = [];
      _showSuggestions = true;
      _isLoading = false;
    });
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
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: GoogleFonts.figtree(
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
              : BorderRadius.circular(8),
      child: Image.network(url, width: 60, height: 60, fit: BoxFit.cover),
    );
  }

  Widget _buildPlaylistRow(Playlist p, {VoidCallback? onRemove}) {
    final imageUrl = p.images.isNotEmpty ? p.images.last.url : '';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10),
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
                  style: GoogleFonts.figtree(
                    color:
                        ref.watch(currentSongProvider)?.id == p.id
                            ? Colors.greenAccent
                            : Colors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                _buildSubtitleRow(p),
              ],
            ),
          ),
          if (onRemove != null) // show only in recent list
            IconButton(
              icon: const Icon(Icons.close, color: Colors.grey, size: 18),
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }

  Widget _buildSubtitleRow(Playlist p) {
    return Row(
      children: [
        if (p.language.isNotEmpty)
          Text('${capitalize(p.description)} ', style: _subtitleStyle),
        if (p.type.isNotEmpty) Text(capitalize(p.type), style: _subtitleStyle),
        const Spacer(),
        if (_loadingSongId == p.id &&
            ref.watch(currentSongProvider)?.id != p.id)
          const SizedBox(
            height: 15,
            width: 15,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.greenAccent,
            ),
          )
        else if (ref.watch(currentSongProvider)?.id == p.id)
          Image.asset(
            'assets/player.gif',
            height: 16,
            width: 16,
            fit: BoxFit.contain,
          ),
      ],
    );
  }

  Widget _buildSearchHistoryRow() {
    if (searchHistory.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent Search',
          style: GoogleFonts.figtree(fontSize: 13, color: Colors.white54),
        ),
        const SizedBox(height: 2),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children:
                searchHistory.map((term) {
                  return GestureDetector(
                    onTap: () => _onSuggestionTap(term),
                    child: Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 2,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[800],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        term,
                        style: GoogleFonts.figtree(color: Colors.white),
                      ),
                    ),
                  );
                }).toList(),
          ),
        ),
      ],
    );
  }

  TextStyle get _subtitleStyle =>
      GoogleFonts.figtree(color: Colors.grey, fontSize: 12);

  @override
  Widget build(BuildContext context) {
    // super.build(context);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildSearchBox(),
              const SizedBox(height: 10),
              Flexible(child: _buildSearchContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        CircleAvatar(
          radius: 18,
          backgroundImage: AssetImage('assets/logo.png'),
        ),
        Text(
          'Search',
          style: GoogleFonts.figtree(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Icon(Icons.camera_alt_outlined, size: 28, color: Colors.white),
      ],
    );
  }

  Widget _buildSearchBox() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
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
              cursorColor: Colors.greenAccent,
              style: GoogleFonts.figtree(color: Colors.white),
              onTapOutside: (_) => FocusScope.of(context).unfocus(),
              onChanged: _onTextChanged,
              onSubmitted: (value) => _onSuggestionTap(value.trim()),
              decoration: InputDecoration(
                hintText: "What do you want to listen to?",
                hintStyle: GoogleFonts.figtree(color: Colors.grey),
                border: InputBorder.none,
              ),
            ),
          ),
          if (_controller.text.isNotEmpty)
            GestureDetector(
              onTap: _clearText,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.close, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchContent() {
    if (_isLoading) return buildSearchShimmer();

    if (_hasNoResults || _controller.text.trim().isEmpty) {
      return ListView(
        padding: EdgeInsets.zero,
        children: [
          _buildSearchHistoryRow(),
          _buildRecentSection(),
          _buildNoResults(),
          const SizedBox(height: 100),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 60),
      children: [
        if (_showSuggestions && _controller.text.isNotEmpty)
          ..._buildSuggestions(),

        if (_songs.isNotEmpty)
          _buildSection(
            "Songs",
            _songs,
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
                  explicitContent: false,
                  description: song.album,
                ),
              ),
            ),
          ),

        if (_albums.isNotEmpty)
          _buildSection(
            "Albums",
            _albums,
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
                  description: album.artist,
                ),
              ),
            ),
          ),

        if (_artists.isNotEmpty)
          _buildSection(
            "Artists",
            _artists,
            (artist) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _onArtistTap(artist),
              child: _buildPlaylistRow(
                Playlist(
                  id: artist.id,
                  title: artist.title,
                  images: artist.images,
                  url: '',
                  type: artist.type,
                  language: '',
                  explicitContent: false,
                  description: artist.description,
                ),
              ),
            ),
          ),

        if (_playlists.isNotEmpty)
          _buildSection(
            "Playlists",
            _playlists,
            (playlist) => GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _onPlaylistTap(playlist),
              child: _buildPlaylistRow(
                Playlist(
                  id: playlist.id,
                  title: playlist.title,
                  images: playlist.images,
                  url: playlist.url,
                  type: playlist.type,
                  language: playlist.language,
                  explicitContent: playlist.explicitContent,
                  description: playlist.description,
                ),
              ),
            ),
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
            style: GoogleFonts.figtree(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Search for artists, songs, and more',
            style: GoogleFonts.figtree(fontSize: 13, color: Colors.grey),
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
          padding: const EdgeInsets.symmetric(horizontal: 5),
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
                  style: GoogleFonts.figtree(
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                  ),
                ),
              ),
              const Icon(Icons.arrow_upward, color: Colors.grey, size: 18),
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

    //  Save this song into SharedPreferences
    await storeLastSongs([loadedSong]);

    //  Reload to update UI
    _lastSongs = await loadLastSongs();
    if (mounted) setState(() {});

    String? imageUrl =
        loadedSong.images.isNotEmpty ? loadedSong.images.last.url : null;
    if (imageUrl != null) {
      final dominant = await getDominantColorFromImage(imageUrl);
      ref
          .read(playerColourProvider.notifier)
          .state = (Color.lerp(dominant, Colors.black, 0.85) ?? dominant)!
          .withAlpha(250);
    }

    final audioHandler = await ref.read(audioHandlerProvider.future);
    final currentSong = ref.read(currentSongProvider);
    final isCurrentSong = currentSong?.id == loadedSong.id;

    if (!isCurrentSong) {
      await audioHandler.loadQueue([loadedSong], startIndex: 0);
      await audioHandler.play();
    } else {
      (await audioHandler.playerStateStream.first).playing
          ? await audioHandler.pause()
          : await audioHandler.play();
    }

    setState(() => _loadingSongId = null);
  }

  void _onAlbumTap(Album album) async {
    FocusScope.of(context).unfocus();
    //  Save album into SharedPreferences
    await storeLastAlbums([album]);

    //  Reload to update UI
    _lastAlbums = await loadLastAlbums();
    if (mounted) setState(() {});
    if (!mounted) return;
    Navigator.of(context).push(
      PageTransition(
        type: PageTransitionType.rightToLeft,
        duration: const Duration(milliseconds: 300),
        child: AlbumViewer(albumId: album.id),
      ),
    );
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
