import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_swipe_action_cell/core/cell.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';

import '../components/snackbar.dart';
import '../models/datamodel.dart';
import '../models/shimmers.dart';
import '../services/audiohandler.dart';
import '../services/jiosaavn.dart';
import '../shared/constants.dart';
import '../shared/player.dart';
import '../utils/format.dart';
import '../utils/theme.dart';

class AlbumViewer extends ConsumerStatefulWidget {
  final String albumId;
  const AlbumViewer({super.key, required this.albumId});

  @override
  ConsumerState<AlbumViewer> createState() => _AlbumViewerState();
}

class _AlbumViewerState extends ConsumerState<AlbumViewer> {
  Album? _album;
  List<SongDetail> _albumSongDetails = [];
  bool _loading = true;
  int _totalAlbumDuration = 0;

  @override
  void initState() {
    super.initState();
    _fetchAlbum();
  }

  int getTotalDuration(List<SongDetail> songs) {
    return songs.fold<int>(0, (sum, song) {
      final dur =
          (song.duration is int)
              ? song.duration as int
              : int.tryParse(song.duration.toString()) ?? 0;
      return sum + dur;
    });
  }

  Future<void> _fetchAlbum() async {
    final api = SaavnAPI();

    try {
      final alb = await api.fetchAlbumById(albumId: widget.albumId);
      _album = alb;

      // ⚡ Pre-fetch all song details for the album
      if (_album?.songs.isNotEmpty ?? false) {
        _albumSongDetails = await api.getSongDetails(
          ids: _album!.songs.map((s) => s.id).toList(),
        );
        _totalAlbumDuration = getTotalDuration(_albumSongDetails);
        await _updateBgColor();
      }
    } catch (e, st) {
      debugPrint("Error fetching album: $e\n$st");
    }

    _loading = false;
    setState(() {});
  }

  Future<void> _updateBgColor() async {
    if (_album?.images.last.url.isEmpty ?? true) return;

    final dominant = await getDominantColorFromImage(_album!.images.last.url);
    if (dominant == null) return;

    ref.read(playerColourProvider.notifier).state = darken(dominant, 0.25);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isShuffle = ref.watch(shuffleProvider);
    ref.listen<SongDetail?>(currentSongProvider, (_, __) {
      _updateBgColor();
    });

    return Scaffold(
      backgroundColor: ref.watch(playerColourProvider),
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [ref.watch(playerColourProvider), Colors.black],
          ),
        ),
        child:
            _loading
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
                    // Album cover with Hero animation
                    SizedBox(
                      width: MediaQuery.of(context).size.width * 0.80,
                      height: 300,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          _album!.images.isNotEmpty
                              ? _album!.images.last.url
                              : "",
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Album title
                    Text(
                      _album!.title,
                      style: GoogleFonts.figtree(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    // Album metaData
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Album details
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
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
                              if (_album!.description.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2.0),
                                  child: Text(
                                    _album!.description,
                                    style: GoogleFonts.figtree(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              if (_totalAlbumDuration > 0)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2.0),
                                  child: Text(
                                    formatDuration(_totalAlbumDuration),
                                    style: GoogleFonts.figtree(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),

                        // Album Controls: Shuffle + Play/Pause
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Shuffle button
                              GestureDetector(
                                onTap: () async {
                                  final handler = await ref.read(
                                    audioHandlerProvider.future,
                                  );
                                  handler.toggleShuffle();
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: const BoxDecoration(
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    isShuffle ? Icons.shuffle : Icons.shuffle,
                                    color:
                                        isShuffle
                                            ? Colors.greenAccent
                                            : Colors.grey[600],
                                    size: 24,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Play Album / Play First / Shuffle
                              StreamBuilder<PlayerState>(
                                stream: ref
                                    .read(audioHandlerProvider.future)
                                    .asStream()
                                    .asyncExpand((h) => h.playerStateStream),
                                builder: (context, snapshot) {
                                  final isPlaying =
                                      snapshot.data?.playing ?? false;
                                  final currentSong = ref.watch(
                                    currentSongProvider,
                                  );

                                  final bool isCurrentAlbumSong =
                                      currentSong != null &&
                                      _albumSongDetails.any(
                                        (s) => s.id == currentSong.id,
                                      );

                                  // --- Icon logic ---
                                  IconData icon;
                                  if (isCurrentAlbumSong) {
                                    icon =
                                        isPlaying
                                            ? Icons.pause
                                            : Icons.play_arrow;
                                  } else {
                                    icon = Icons.play_arrow;
                                  }

                                  return GestureDetector(
                                    onTap: () async {
                                      try {
                                        final audioHandler = await ref.read(
                                          audioHandlerProvider.future,
                                        );

                                        if (isCurrentAlbumSong) {
                                          // If this album’s song is already playing -> toggle pause/play
                                          if (isPlaying) {
                                            await audioHandler.pause();
                                          } else {
                                            await audioHandler.play();
                                          }
                                        } else {
                                          // Load full album queue
                                          int startIndex = 0;
                                          if (isShuffle) {
                                            startIndex =
                                                DateTime.now()
                                                    .millisecondsSinceEpoch %
                                                _albumSongDetails.length;
                                          }

                                          await audioHandler.loadQueue(
                                            _albumSongDetails,
                                            startIndex: startIndex,
                                          );

                                          // If shuffle is enabled, apply it after loading
                                          if (isShuffle &&
                                              !audioHandler.isShuffle) {
                                            audioHandler.toggleShuffle();
                                          }

                                          await audioHandler.play();
                                        }
                                      } catch (e, st) {
                                        debugPrint(
                                          "Error handling album play: $e\n$st",
                                        );
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: const BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.green,
                                      ),
                                      child: Icon(
                                        icon,
                                        color: Colors.black,
                                        size: 30,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 20),

                    // Songs
                    ..._album!.songs.map((song) {
                      final currentSong = ref.watch(currentSongProvider);
                      final isPlaying = currentSong?.id == song.id;
                      final isLiked = ref
                          .watch(likedSongsProvider)
                          .contains(song.id);

                      return SwipeActionCell(
                        backgroundColor: Colors.transparent,
                        key: ValueKey(song.id),
                        fullSwipeFactor: 0.3,
                        editModeOffset: 10,
                        trailingActions: [
                          SwipeAction(
                            color: Colors.greenAccent.shade700,
                            icon: const Icon(Icons.playlist_add),
                            performsFirstActionWithFullSwipe: true,
                            onTap: (handler) async {
                              final audioHandler = await ref.read(
                                audioHandlerProvider.future,
                              );
                              await audioHandler.playSongNow(
                                song,
                                insertNext: true,
                              );
                              info(
                                '${song.title} added to Queue',
                                Severity.success,
                              );
                              await handler(false);
                            },
                          ),
                        ],
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            try {
                              if (_albumSongDetails.isEmpty) return;

                              final tappedIndex = _albumSongDetails.indexWhere(
                                (s) => s.id == song.id,
                              );
                              if (tappedIndex == -1) return;

                              final audioHandler = await ref.read(
                                audioHandlerProvider.future,
                              );

                              // Check if tapped song is currently playing
                              final isCurrentSong = currentSong?.id == song.id;

                              if (!isCurrentSong) {
                                // Load album queue starting at tapped song
                                await audioHandler.loadQueue(
                                  _albumSongDetails,
                                  startIndex: tappedIndex,
                                );

                                // Respect shuffle mode if enabled
                                final isShuffle = ref.read(shuffleProvider);
                                if (isShuffle) audioHandler.toggleShuffle();

                                await audioHandler.play();
                              } else {
                                // Toggle play/pause for current song
                                await audioHandler.pause();
                              }
                            } catch (e, st) {
                              debugPrint(
                                "Error playing tapped album song: $e\n$st",
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8.0,
                              horizontal: 4.0,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      // Playing indicator
                                      if (isPlaying)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 8.0,
                                          ),
                                          child: Image.asset(
                                            'assets/player.gif',
                                            height: 18,
                                            fit: BoxFit.contain,
                                          ),
                                        ),

                                      // Song details
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              song.title,
                                              style: GoogleFonts.figtree(
                                                color:
                                                    isPlaying
                                                        ? Colors.greenAccent
                                                        : Colors.white,
                                                fontWeight: FontWeight.w500,
                                                fontSize: 16,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                            Text(
                                              song.primaryArtists.isNotEmpty
                                                  ? song.primaryArtists
                                                  : _album!.artist,
                                              style: GoogleFonts.figtree(
                                                color: Colors.white70,
                                                fontSize: 13,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 1,
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Liked song indicator
                                      if (isLiked)
                                        const Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 8.0,
                                          ),
                                          child: Icon(
                                            Icons.check_circle,
                                            color: Colors.green,
                                            size: 20,
                                          ),
                                        ),

                                      // Menu icon
                                      IconButton(
                                        icon: const Icon(
                                          Icons.more_vert,
                                          color: Colors.white70,
                                          size: 20,
                                        ),
                                        onPressed: () {
                                          // TODO: Show song menu
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),

                    const SizedBox(height: 70),
                  ],
                ),
      ),
    );
  }
}
