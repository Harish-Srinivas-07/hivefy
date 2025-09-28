import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/datamodel.dart';
import '../models/shimmers.dart';
import '../services/jiosaavn.dart';
import '../shared/constants.dart';
import '../shared/miniplayer.dart';
import '../utils/theme.dart';

class AlbumViewer extends ConsumerStatefulWidget {
  final String albumId;
  const AlbumViewer({super.key, required this.albumId});

  @override
  ConsumerState<AlbumViewer> createState() => _AlbumViewerState();
}

class _AlbumViewerState extends ConsumerState<AlbumViewer>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  Album? _album;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchAlbum();
  }

  Future<void> _fetchAlbum() async {
    final api = SaavnAPI();
    final alb = await api.fetchAlbumById(albumId: widget.albumId);
    debugPrint('--> fetched album Data: $alb');
    _album = alb;
    _loading = false;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          "Album",
          style: GoogleFonts.figtree(fontWeight: FontWeight.w600),
        ),
      ),
      body: _loading
          ? buildAlbumShimmer()
          : _album == null
          ? const Center(
              child: Text(
                "Failed to load album",
                style: TextStyle(color: Colors.white70),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Album cover
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(
                    _album!.images.isNotEmpty ? _album!.images.last.url : "",
                    width: double.infinity,
                    // height: 220,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 16),

                // Album title
                Text(
                  _album!.title,
                  style: GoogleFonts.figtree(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                // Artist
                if (_album!.artist.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      _album!.artist,
                      style: GoogleFonts.figtree(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ),

                // Year & Label
                if (_album!.year.isNotEmpty || _album!.label.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2.0),
                    child: Text(
                      "${_album!.year}  •  ${_album!.label}",
                      style: GoogleFonts.figtree(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),

                // Songs
                ..._album!.songs.map((song) {
                  final currentSong = ref.watch(currentSongProvider);
                  final isPlaying = currentSong?.id == song.id;

                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Row(
                      children: [
                        // Equalizer icon in front of the title
                        if (isPlaying)
                          Padding(
                            padding: const EdgeInsets.only(right: 6.0),
                            child: Icon(
                              Icons.graphic_eq,
                              color: Colors.greenAccent,
                              size: 16, // same height as font
                            ),
                          ),
                        Expanded(
                          child: Text(
                            song.title,
                            style: GoogleFonts.figtree(
                              color: isPlaying
                                  ? Colors.greenAccent
                                  : Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    subtitle: Text(
                      song.primaryArtists.isNotEmpty
                          ? song.primaryArtists
                          : _album!.artist,
                      style: GoogleFonts.figtree(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    trailing: SizedBox(
                      height: 40, // ensures vertical center alignment
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.add_circle_outline,
                              color: Colors.white70,
                              size: 24,
                            ),
                            onPressed: () {
                              // TODO: Add song to playlist/favorites
                            },
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.more_vert,
                              color: Colors.white70,
                              size: 24,
                            ),
                            onPressed: () {
                              // TODO: Show song menu
                            },
                          ),
                        ],
                      ),
                    ),
                    onTap: () async {
                      try {
                        final details = await SaavnAPI().getSongDetails(
                          ids: [song.id],
                        );
                        if (details.isNotEmpty) {
                          final songDetails = details.first;
                          String? imageUrl = songDetails.images.isNotEmpty
                              ? songDetails.images.last.url
                              : null;
                          final dominant = imageUrl != null
                              ? await getDominantColorFromImage(imageUrl)
                              : null;
                          final mixedColor =
                              Color.lerp(dominant, Colors.black, 0.6) ??
                              dominant;
                          if (mixedColor != null) {
                            playerColour = mixedColor.withAlpha(250);
                          }

                          final player = ref.read(playerProvider);

                          if (songDetails.downloadUrls.isNotEmpty) {
                            final url = songDetails.downloadUrls.last.url;
                            await player.setUrl(url);
                            ref.read(currentSongProvider.notifier).state =
                                songDetails;
                            await player.play();
                          }
                        }
                      } catch (e, st) {
                        debugPrint("Error playing song: $e\n$st");
                      }
                    },
                  );
                }),

                const SizedBox(height: 70),
              ],
            ),
    );
  }
}
