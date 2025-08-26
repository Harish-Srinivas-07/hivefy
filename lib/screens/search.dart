import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hivefy/shared/miniplayer.dart';
import 'package:iconly/iconly.dart';

import '../models/datamodel.dart';
import '../services/jiosaavn.dart';
import '../shared/constants.dart';
import '../shared/queue.dart';
import '../utils/format.dart';
import '../utils/theme.dart';

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

  void _onTextChanged(String value) async {
    if (value.isEmpty) {
      setState(() {
        _suggestions = [];
        _showSuggestions = true;
        _songs = [];
        _albums = [];
        _artists = [];
        _playlists = [];
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _showSuggestions = true;
    });

    final results = await saavn.getSearchBoxSuggestions(query: value);

    if (mounted) {
      setState(() {
        _suggestions = results;
        _isLoading = false;
      });
    }
  }

  void _onSuggestionTap(String suggestion) async {
    _controller.text = suggestion;
    setState(() {
      _isLoading = true;
      _showSuggestions = false;
      // reset all previous results
      _songs = [];
      _albums = [];
      _artists = [];
      _playlists = [];
      _suggestions = [];
    });
    final results = await saavn.globalSearch(suggestion);

    if (mounted && results != null) {
      setState(() {
        _songs = results.songs.results;
        _albums = results.albums.results;
        _artists = results.artists.results;
        _playlists = results.playlists.results;
        _isLoading = false;
      });
    }
  }

  void _clearText() {
    _controller.clear();
    setState(() {
      _suggestions = [];
      _songs = [];
      _albums = [];
      _artists = [];
      _playlists = [];
      _showSuggestions = true;
    });
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: GoogleFonts.figtree(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildItemImage(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(url, width: 60, height: 60, fit: BoxFit.cover),
    );
  }

  Widget _buildPlaylistRow(Playlist p) {
    final imageUrl = p.images.isNotEmpty ? p.images.last.url : '';
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          _buildItemImage(imageUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.title,
                  style: GoogleFonts.figtree(
                    color: ref.watch(currentSongProvider)?.id == p.id
                        ? Colors.greenAccent
                        : Colors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (p.language.isNotEmpty)
                      Text(
                        '${capitalize(p.language)} ',
                        style: GoogleFonts.figtree(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    if (p.type.isNotEmpty)
                      Text(
                        capitalize(p.type),
                        style: GoogleFonts.figtree(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    const Spacer(),
                    // Loader / Indicator
                    if (_loadingSongId == p.id)
                      const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.greenAccent,
                        ),
                      )
                    else if (ref.watch(currentSongProvider)?.id == p.id)
                      const Icon(
                        Icons.equalizer,
                        color: Colors.greenAccent,
                        size: 20,
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                if (p.songCount != null)
                  Text(
                    "${p.songCount} songs",
                    style: GoogleFonts.figtree(
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CircleAvatar(
                    radius: 20,
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
                  IconButton(
                    icon: const Icon(
                      Icons.camera_alt_outlined,
                      size: 28,
                      color: Colors.white,
                    ),
                    onPressed: () {},
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // /searchbox
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[900],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Icon(IconlyLight.search, color: Colors.grey),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        onTapOutside: (_) => FocusScope.of(context).unfocus(),
                        controller: _controller,
                        cursorColor: Colors.greenAccent,
                        onChanged: _onTextChanged,
                        style: GoogleFonts.figtree(color: Colors.white),
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
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Icon(Icons.close, color: Colors.grey),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
                  : Expanded(
                      child: _isLoading
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: Colors.white,
                              ),
                            )
                          : _hasNoResults
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
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
                                    style: GoogleFonts.figtree(
                                      fontSize: 13,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView(
                              children: [
                                // Suggestions
                                if (_showSuggestions &&
                                    _controller.text.isNotEmpty)
                                  ..._suggestions
                                      .take(5)
                                      .map(
                                        (s) => GestureDetector(
                                          onTap: () => _onSuggestionTap(s),
                                          child: Container(
                                            height: 50,
                                            margin: const EdgeInsets.symmetric(
                                              vertical: 2,
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 5,
                                            ),
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.all(
                                                    8,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: Colors.grey[800],
                                                  ),
                                                  child: const Icon(
                                                    Icons.search,
                                                    color: Colors.grey,
                                                    size: 28,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Text(
                                                    s,
                                                    style: GoogleFonts.figtree(
                                                      color: Colors.grey,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      fontSize: 16,
                                                    ),
                                                  ),
                                                ),
                                                Transform.rotate(
                                                  angle: -0.785398,
                                                  child: const Icon(
                                                    Icons.arrow_upward,
                                                    color: Colors.grey,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                // Songs
                                if (_songs.isNotEmpty)
                                  _buildSectionTitle("Songs"),
                                ..._songs.map(
                                  (s) => GestureDetector(
                                    onTap: () async {
                                      FocusScope.of(context).unfocus();

                                      setState(() {
                                        _loadingSongId = s.id;
                                      });

                                      try {
                                        final details = await saavn
                                            .getSongDetails(ids: [s.id]);

                                        if (details.isNotEmpty) {
                                          final song = details.first;

                                          debugPrint(
                                            "--- playing song: ${song.title} - ${song.url}",
                                          );
                                          final dominant =
                                              await getDominantColorFromImage(
                                                s.images.last.url,
                                              );
                                          playerColour =
                                              (dominant ?? playerColour)
                                                  .withOpacity(0.85);

                                          final player = ref.read(
                                            playerProvider,
                                          );

                                          await player.setUrl(
                                            song.downloadUrls.last.url,
                                          );

                                          // Update provider
                                          ref
                                                  .read(
                                                    currentSongProvider
                                                        .notifier,
                                                  )
                                                  .state =
                                              song;

                                              ref.listen<QueueState>(
                                            queueProvider,
                                            (prev, next) {
                                              if (next.current !=
                                                  prev?.current) {
                                                ref
                                                        .read(
                                                          currentSongProvider
                                                              .notifier,
                                                        )
                                                        .state =
                                                    next.current;
                                              }
                                            },
                                          );


                                          await player.play();

                                          // Reset loading
                                          setState(() {
                                            _loadingSongId = null;
                                          });
                                        }
                                      } catch (e) {
                                        debugPrint("Error playing song: $e");
                                        setState(() {
                                          _loadingSongId = null;
                                        });
                                      }
                                    },
                                    child: _buildPlaylistRow(
                                      Playlist(
                                        id: s.id,
                                        title: s.title,
                                        images: s.images,
                                        url: s.url,
                                        type: s.type,
                                        language: s.language,
                                        explicitContent: false,
                                        description: s.description,
                                      ),
                                    ),
                                  ),
                                ),
                                // Albums
                                if (_albums.isNotEmpty)
                                  _buildSectionTitle("Albums"),
                                ..._albums.map(
                                  (a) => _buildPlaylistRow(
                                    Playlist(
                                      id: a.id,
                                      title: a.title,
                                      images: a.images,
                                      url: a.url,
                                      type: a.type,
                                      language: a.language,
                                      explicitContent: false,
                                      description: a.description,
                                    ),
                                  ),
                                ),
                                // Artists
                                if (_artists.isNotEmpty)
                                  _buildSectionTitle("Artists"),
                                ..._artists.map(
                                  (ar) => _buildPlaylistRow(
                                    Playlist(
                                      id: ar.id,
                                      title: ar.title,
                                      images: ar.images,
                                      url: '',
                                      type: ar.type,
                                      language: '',
                                      explicitContent: false,
                                      description: ar.description,
                                    ),
                                  ),
                                ),
                                // Playlists
                                if (_playlists.isNotEmpty)
                                  _buildSectionTitle("Playlists"),
                                ..._playlists.map(_buildPlaylistRow),
                              ],
                            ),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
