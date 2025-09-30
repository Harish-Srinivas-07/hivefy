import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/datamodel.dart';
import '../services/jiosaavn.dart';
import '../shared/constants.dart';
import '../shared/miniplayer.dart';
import '../utils/format.dart';

class LikedSongsViewer extends ConsumerStatefulWidget {
  const LikedSongsViewer({super.key});

  @override
  ConsumerState<LikedSongsViewer> createState() => _LikedSongsViewerState();
}

class _LikedSongsViewerState extends ConsumerState<LikedSongsViewer> {
  List<SongDetail> _songs = [];
  bool _loading = true;
  int _totalDuration = 0;

  @override
  void initState() {
    super.initState();
    _fetchLikedSongs();
  }

  int getTotalDuration(List<SongDetail> songs) {
    return songs.fold<int>(0, (sum, s) {
      final dur =
          (s.duration is int)
              ? s.duration as int
              : int.tryParse(s.duration ?? '') ?? 0;
      return sum + dur;
    });
  }

  Future<void> _fetchLikedSongs() async {
    final ids = ref.read(likedSongsProvider);
    if (ids.isEmpty) {
      _songs = [];
      _loading = false;
      if (mounted) setState(() {});
      return;
    }

    final api = SaavnAPI();

    try {
      // Fetch all details in one go
      final freshDetails = await api.getSongDetails(ids: ids);

      // Maintain order based on liked ids
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
    } catch (e, st) {
      debugPrint("Failed to fetch liked songs: $e\n$st");
      // fallback: empty list if API fails
      _songs = [];
    }

    _totalDuration = getTotalDuration(_songs);
    _loading = false;
    if (mounted) setState(() {});
  }

  Widget _buildItemImage(String url) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(url, width: 45, height: 45, fit: BoxFit.cover),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<List<SongDetail>>(queueManagerProvider, (_, __) {
      final qm = ref.read(queueManagerProvider.notifier);
      ref.read(currentSongProvider.notifier).state = qm.currentSong;
    });

    final player = ref.read(playerProvider);
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
                ? const Center(
                  child: Text(
                    "No liked songs yet",
                    style: TextStyle(color: Colors.white70),
                  ),
                )
                : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Cover art (heart ❤️ with square background)
                    SizedBox(
                      width: MediaQuery.of(context).size.width * 0.70,
                      height: 250,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          color: Colors.pinkAccent.shade100.withAlpha(60),
                          child: const Center(
                            child: Icon(
                              Icons.favorite,
                              size: 120,
                              color: Colors.pinkAccent,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Title
                    Text(
                      "Liked Songs",
                      style: GoogleFonts.figtree(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    // Metadata (count + duration)
                    Padding(
                      padding: const EdgeInsets.only(top: 6.0),
                      child: Text(
                        "${_songs.length} songs • ${formatDuration(_totalDuration)}",
                        style: GoogleFonts.figtree(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ),

                    // Controls: Shuffle + Play
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () {
                              ref
                                  .read(queueManagerProvider.notifier)
                                  .toggleShuffle();
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                              ),
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
                              final qm = ref.read(
                                queueManagerProvider.notifier,
                              );
                              await qm.loadQueue(_songs, startIndex: 0);
                              await player.play();
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

                    const SizedBox(height: 10),

                    // Songs list
                    ..._songs.map((song) {
                      final currentSong = ref.watch(currentSongProvider);
                      final isPlaying = currentSong?.id == song.id;
                      final imageUrl =
                          song.images.isNotEmpty ? song.images.last.url : '';
                      // final isLiked = ref
                      //     .watch(likedSongsProvider)
                      //     .contains(song.id);

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () async {
                          final idx = _songs.indexWhere((s) => s.id == song.id);
                          await ref
                              .read(queueManagerProvider.notifier)
                              .loadQueue(_songs, startIndex: idx);
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
                                  children: [
                                    _buildItemImage(imageUrl),
                                    if (isPlaying)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          right: 8,
                                        ),
                                        child: Image.asset(
                                          'assets/player.gif',
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
                                                  isPlaying
                                                      ? Colors.greenAccent
                                                      : Colors.white,
                                              fontWeight: FontWeight.w500,
                                              fontSize: 14,
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
                                              fontSize: 12,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                            maxLines: 1,
                                          ),
                                        ],
                                      ),
                                    ),
                                    // if (isLiked)
                                    //   const Padding(
                                    //     padding: EdgeInsets.symmetric(
                                    //       horizontal: 8,
                                    //     ),
                                    //     child: Icon(
                                    //       Icons.check_circle,
                                    //       color: Colors.green,
                                    //       size: 20,
                                    //     ),
                                    //   ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.more_vert,
                                        color: Colors.white70,
                                        size: 20,
                                      ),
                                      onPressed: () {
                                        // TODO: Song menu
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
