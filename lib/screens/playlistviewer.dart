import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_swipe_action_cell/core/cell.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:readmore/readmore.dart';

import '../components/snackbar.dart';
import '../models/datamodel.dart';
import '../models/shimmers.dart';
import '../services/audiohandler.dart';
import '../services/jiosaavn.dart';
import '../shared/constants.dart';
import '../shared/player.dart';
import '../utils/format.dart';

class PlaylistViewer extends ConsumerStatefulWidget {
  final String playlistId;

  const PlaylistViewer({super.key, required this.playlistId});

  @override
  ConsumerState<PlaylistViewer> createState() => _PlaylistViewerState();
}

class _PlaylistViewerState extends ConsumerState<PlaylistViewer> {
  Playlist? _playlist;
  bool _loading = true;

  final ScrollController _scrollController = ScrollController();
  bool _isTitleCollapsed = false;
  List<SongDetail> _playlistSongDetails = [];
  int _totalPlaylistDuration = 0;

  @override
  void initState() {
    super.initState();
    _fetchPlaylist();

    _scrollController.addListener(() {
      bool isCollapsed =
          _scrollController.hasClients &&
          _scrollController.offset > (350 - kToolbarHeight - 20);

      if (isCollapsed != _isTitleCollapsed) {
        setState(() {
          _isTitleCollapsed = isCollapsed;
        });
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchPlaylist() async {
    setState(() => _loading = true);

    try {
      final playlist = await SaavnAPI().fetchPlaylistById(
        playlistId: widget.playlistId,
      );

      if (playlist != null && playlist.songs.isNotEmpty) {
        _playlistSongDetails = await SaavnAPI().getSongDetails(
          ids: playlist.songs.map((s) => s.id).toList(),
        );
        _totalPlaylistDuration = getTotalDuration(_playlistSongDetails);
      }

      if (mounted) {
        setState(() {
          _playlist = playlist;
          _loading = false;
        });
      }
    } catch (e, st) {
      debugPrint("Error fetching playlist: $e\n$st");
      setState(() => _loading = false);
    }
  }

  Widget _buildHeader() {
    if (_playlist == null) return const SizedBox.shrink();

    final imageUrl =
        _playlist!.images.isNotEmpty ? _playlist!.images.last.url : '';

    return Padding(
      padding: const EdgeInsets.only(
        top: kToolbarHeight + 16,
        bottom: 16,
        left: 16,
        right: 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.80,
              height: 300,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child:
                    imageUrl.isNotEmpty
                        ? Image.network(imageUrl, fit: BoxFit.contain)
                        : Container(
                          color: Colors.grey.shade800,
                          child: const Icon(
                            Icons.playlist_play,
                            size: 100,
                            color: Colors.white,
                          ),
                        ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _playlist!.title,
            style: GoogleFonts.figtree(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildSongList() {
    final songs = _playlist?.songs ?? [];
    if (_loading) return buildAlbumShimmer();

    if (songs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            "Songs",
            style: GoogleFonts.figtree(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...songs.map(
          (song) => SongRow(song: song, allSongs: _playlistSongDetails),
        ),
      ],
    );
  }

  Widget _buildShufflePlayButtons() {
    final isShuffle = ref.watch(shuffleProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Shuffle button
          GestureDetector(
            onTap: () async {
              final handler = await ref.read(audioHandlerProvider.future);
              handler.toggleShuffle();
            },
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(shape: BoxShape.circle),
              child: Icon(
                isShuffle ? Icons.shuffle : Icons.shuffle,
                color: isShuffle ? Colors.greenAccent : Colors.grey[600],
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
              final isPlaying = snapshot.data?.playing ?? false;
              final currentSong = ref.watch(currentSongProvider);

              final bool isCurrentAlbumSong =
                  currentSong != null &&
                  _playlistSongDetails.any((s) => s.id == currentSong.id);

              // --- Icon logic ---
              IconData icon;
              if (isCurrentAlbumSong) {
                icon = isPlaying ? Icons.pause : Icons.play_arrow;
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
                            DateTime.now().millisecondsSinceEpoch %
                            _playlistSongDetails.length;
                      }

                      await audioHandler.loadQueue(
                        _playlistSongDetails,
                        startIndex: startIndex,
                      );

                      // If shuffle is enabled, apply it after loading
                      if (isShuffle && !audioHandler.isShuffle) {
                        audioHandler.toggleShuffle();
                      }

                      await audioHandler.play();
                    }
                  } catch (e, st) {
                    debugPrint("Error handling album play: $e\n$st");
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.green,
                  ),
                  child: Icon(icon, color: Colors.black, size: 30),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ref.watch(playerColourProvider),
      body: Container(
        decoration: BoxDecoration(color: Colors.black),
        child:
            _loading
                ? Padding(
                  padding: const EdgeInsets.only(top: 60),
                  child: buildAlbumShimmer(),
                )
                : _playlist == null
                ? const Center(
                  child: Text(
                    "Failed to load playlist",
                    style: TextStyle(color: Colors.white70),
                  ),
                )
                : CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverAppBar(
                      pinned: true,
                      backgroundColor: Colors.transparent,
                      expandedHeight: 400,
                      elevation: 0,
                      leading: const BackButton(color: Colors.white),
                      flexibleSpace: Stack(
                        fit: StackFit.expand,
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  ref.watch(playerColourProvider),
                                  Colors.black,
                                ],
                              ),
                            ),
                          ),
                          FlexibleSpaceBar(
                            collapseMode: CollapseMode.pin,
                            centerTitle: false,
                            titlePadding: EdgeInsets.only(
                              left: _isTitleCollapsed ? 72 : 16,
                              bottom: 16,
                              right: 16,
                            ),
                            title: AnimatedOpacity(
                              opacity: _isTitleCollapsed ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 200),
                              child: Text(
                                _playlist?.title ?? "",
                                style: GoogleFonts.figtree(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            background: _buildHeader(),
                          ),
                        ],
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_playlist!.description.isNotEmpty)
                                    ReadMoreText(
                                      _playlist!.description,
                                      trimLines: 3,
                                      trimMode: TrimMode.Line,
                                      colorClickableText: Colors.greenAccent,
                                      trimCollapsedText: " ...more",
                                      trimExpandedText: " Show less",
                                      style: GoogleFonts.figtree(
                                        color: Colors.white54,
                                        fontSize: 14,
                                      ),
                                    ),
                                  const SizedBox(height: 4),
                                  if (_totalPlaylistDuration > 0)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2.0),
                                      child: Text(
                                        formatDuration(_totalPlaylistDuration),
                                        style: GoogleFonts.figtree(
                                          color: Colors.white54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            _buildShufflePlayButtons(),
                          ],
                        ),
                      ),
                    ),

                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 16),
                          _buildSongList(),
                          const SizedBox(height: 100),
                        ],
                      ),
                    ),
                  ],
                ),
      ),
    );
  }
}

class SongRow extends ConsumerWidget {
  final SongDetail song;
  final List<SongDetail> allSongs;

  const SongRow({super.key, required this.song, required this.allSongs});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSong = ref.watch(currentSongProvider);
    final isPlaying = currentSong?.id == song.id;
    final isLiked = ref.watch(likedSongsProvider).contains(song.id);

    return SwipeActionCell(
      backgroundColor: Colors.transparent,
      key: ValueKey(song.id),
      fullSwipeFactor: 0.01,
      editModeOffset: 2,
      leadingActions: [
        SwipeAction(
          color: Colors.greenAccent.shade700,
          icon: const Icon(Icons.playlist_add),
          performsFirstActionWithFullSwipe: true,
          onTap: (handler) async {
            final audioHandler = await ref.read(audioHandlerProvider.future);
            await audioHandler.addSongToQueue(song);
            info('${song.title} added to queue', Severity.success);
            await handler(false);
          },
        ),
      ],
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          final audioHandler = await ref.read(audioHandlerProvider.future);
          await audioHandler.loadQueue(allSongs, startIndex: 0);
          await audioHandler.play();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  song.images.isNotEmpty ? song.images.last.url : '',
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      style: GoogleFonts.figtree(
                        color: isPlaying ? Colors.greenAccent : Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
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
                    ),
                  ],
                ),
              ),
              if (isLiked) const Icon(Icons.check_circle, color: Colors.green),
              if (isPlaying) Image.asset('assets/player.gif', height: 18),
            ],
          ),
        ),
      ),
    );
  }
}
