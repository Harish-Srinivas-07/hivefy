import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_swipe_action_cell/core/cell.dart';
import 'package:google_fonts/google_fonts.dart';

import '../components/snackbar.dart';
import '../models/database.dart';
import '../models/datamodel.dart';
import '../services/audiohandler.dart';
import '../services/jiosaavn.dart';
import '../shared/constants.dart';
import '../shared/player.dart';
import '../utils/format.dart';

class SongsViewer extends ConsumerStatefulWidget {
  final bool showLikedSongs;

  const SongsViewer({super.key, this.showLikedSongs = false});

  @override
  ConsumerState<SongsViewer> createState() => _SongsViewerState();
}

class _SongsViewerState extends ConsumerState<SongsViewer> {
  List<SongDetail> _songs = [];
  bool _loading = true;
  int _totalDuration = 0;

  @override
  void initState() {
    super.initState();
    _fetchSongs();
  }

  Future<void> _fetchSongs() async {
    _loading = true;
    if (widget.showLikedSongs) {
      final ids = ref.read(likedSongsProvider);
      if (ids.isEmpty) {
        _songs = [];
        _loading = false;
        if (mounted) setState(() {});
        return;
      }
      try {
        final freshDetails = await SaavnAPI().getSongDetails(ids: ids);
        _songs =
            ids.map((id) {
              return freshDetails.firstWhere(
                (s) => s.id == id,
                orElse:
                    () => SongDetail(
                      id: id,
                      title: "Unknown Song",
                      type: "",
                      url: "",
                      images: [],
                    ),
              );
            }).toList();
      } catch (e) {
        debugPrint("Failed to fetch liked songs: $e");
        _songs = [];
      }
    } else {
      _songs = await AppDatabase.getAllSongs();
    }

    _totalDuration = _songs.fold(
      0,
      (sum, s) => sum + (int.tryParse(s.duration ?? '0') ?? 0),
    );
    _loading = false;
    if (mounted) setState(() {});
  }

  Widget _buildItemImage(String url) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(url, width: 50, height: 50, fit: BoxFit.cover),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final isShuffle = ref.watch(shuffleProvider);

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
                ? const Center(child: CircularProgressIndicator())
                : _songs.isEmpty
                ? Center(
                  child: Text(
                    "No ${widget.showLikedSongs ? 'liked' : 'songs'} found",
                    style: const TextStyle(color: Colors.white70),
                  ),
                )
                : ListView(
                  // padding: const EdgeInsets.all(16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width * 0.70,
                        height: 250,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            color: Colors.pinkAccent.shade100.withAlpha(60),
                            child: Center(
                              child: Icon(
                                widget.showLikedSongs
                                    ? Icons.favorite
                                    : Icons.music_note,
                                size: 120,
                                color: Colors.pinkAccent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Album title
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),

                      child: Text(
                        widget.showLikedSongs ? "Liked Songs" : "All Songs",
                        style: GoogleFonts.figtree(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 16, top: 3),
                      child: Text(
                        "${_songs.length} songs • ${formatDuration(_totalDuration)}",
                        style: GoogleFonts.figtree(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 16,
                        horizontal: 16,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () async {
                              final audioHandler = await ref.read(
                                audioHandlerProvider.future,
                              );
                              audioHandler.toggleShuffle();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              child: Icon(
                                Icons.shuffle,
                                color:
                                    isShuffle
                                        ? Colors.greenAccent
                                        : Colors.grey[600],
                                size: 24,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () async {
                              final audioHandler = await ref.read(
                                audioHandlerProvider.future,
                              );
                              await audioHandler.loadQueue(
                                _songs,
                                startIndex: 0,
                              );
                              await audioHandler.play();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.green,
                              ),
                              child: const Icon(
                                Icons.play_arrow,
                                color: Colors.black,
                                size: 30,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    ..._songs.map((song) {
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
                          onTap: () async {
                            final audioHandler = await ref.read(
                              audioHandlerProvider.future,
                            );
                            final idx = _songs.indexWhere(
                              (s) => s.id == song.id,
                            );
                            await audioHandler.loadQueue(
                              _songs,
                              startIndex: idx,
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 4,
                            ),
                            child: Row(
                              children: [
                                _buildItemImage(
                                  song.images.isNotEmpty
                                      ? song.images.last.url
                                      : '',
                                ),
                                if (ref.watch(currentSongProvider)?.id ==
                                    song.id)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 8),
                                    child: Image(
                                      image: AssetImage('assets/player.gif'),
                                      height: 18,
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        song.title,
                                        style: GoogleFonts.figtree(
                                          color:
                                              ref
                                                          .watch(
                                                            currentSongProvider,
                                                          )
                                                          ?.id ==
                                                      song.id
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
                                            : song.album,
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
