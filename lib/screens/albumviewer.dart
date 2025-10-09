import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_swipe_action_cell/core/cell.dart';
import 'package:just_audio/just_audio.dart';

import '../components/snackbar.dart';
import '../models/datamodel.dart';
import '../components/shimmers.dart';
import '../services/audiohandler.dart';
import '../services/jiosaavn.dart';
import '../shared/constants.dart';
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
  Color albumCoverColour = Colors.black;

  final ScrollController _scrollController = ScrollController();
  bool _isTitleCollapsed = false;

  @override
  void initState() {
    super.initState();
    _fetchAlbum();
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
    if (mounted) setState(() {});
  }

  Future<void> _updateBgColor() async {
    if (_album?.images.last.url.isEmpty ?? true) return;

    final dominant = await getDominantColorFromImage(_album!.images.last.url);
    if (dominant == null) return;
    if (!mounted) return;

    albumCoverColour = dominant;

    if (mounted) setState(() {});
  }

  Widget _buildSwipeSongCard(SongDetail song) {
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
            await audioHandler.addSongNext(song);
            info('${song.title} will play next', Severity.success);
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

            final audioHandler = await ref.read(audioHandlerProvider.future);
            final currentSong = ref.read(currentSongProvider);
            final currentQueue = audioHandler.queueSongs;

            bool isSameAlbumQueue = false;

            // 🔹 Check if current queue belongs to the same album source
            if (audioHandler.queueSourceId == widget.albumId) {
              isSameAlbumQueue = true;
            } else if (currentQueue.isNotEmpty &&
                _albumSongDetails.isNotEmpty) {
              // Fallback: compare IDs if no source match
              final currentIds = currentQueue.map((s) => s.id).toSet();
              final albumIds = _albumSongDetails.map((s) => s.id).toSet();
              final overlap = currentIds.intersection(albumIds).length;
              final ratio = overlap / albumIds.length;
              if (ratio > 0.8) isSameAlbumQueue = true;
            }

            final bool isCurrentSong = currentSong?.id == song.id;

            if (isCurrentSong) {
              // 🎵 Toggle play/pause
              final playing =
                  (await audioHandler.playerStateStream.first).playing;
              if (playing) {
                await audioHandler.pause();
              } else {
                await audioHandler.play();
              }
              return;
            }

            if (isSameAlbumQueue) {
              // 🎯 Same album → jump to tapped song
              await audioHandler.skipToQueueItem(tappedIndex);
            } else {
              // 🚀 New album → replace queue with new album songs
              await audioHandler.loadQueue(
                _albumSongDetails,
                startIndex: tappedIndex,
                sourceId: widget.albumId,
                sourceName: _album?.title,
              );
            }

            // 🔁 Handle shuffle toggle
            final isShuffle = ref.read(shuffleProvider);
            if (isShuffle) {
              if (!audioHandler.isShuffle) {
                audioHandler.toggleShuffle();
              } else {
                audioHandler.regenerateShuffle();
              }
            }

            await audioHandler.play();
          } catch (e, st) {
            debugPrint("Error playing tapped album song: $e\n$st");
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Song details
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (isPlaying)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8.0),
                                  child: Image.asset(
                                    'assets/player.gif',
                                    height: 18,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  song.title,
                                  style: TextStyle(
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
                              ),
                            ],
                          ),
                          Text(
                            song.primaryArtists.isNotEmpty
                                ? song.primaryArtists
                                : _album!.artist,
                            style: TextStyle(
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
                        padding: EdgeInsets.symmetric(horizontal: 8.0),
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
                  _albumSongDetails.any((s) => s.id == currentSong.id);

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
                            _albumSongDetails.length;
                      }

                      await audioHandler.loadQueue(
                        _albumSongDetails,
                        startIndex: startIndex,
                      );

                      // If shuffle is enabled, apply it after loading
                      if (isShuffle) {
                        if (!audioHandler.isShuffle) {
                          audioHandler.toggleShuffle();
                        } else {
                          audioHandler.regenerateShuffle();
                        }
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
    ref.listen<SongDetail?>(currentSongProvider, (_, __) {
      _updateBgColor();
    });

    return Scaffold(
      backgroundColor: albumCoverColour,
      body: Container(
        decoration: BoxDecoration(color: Colors.black),
        child:
            _loading
                ? Padding(
                  padding: const EdgeInsets.only(top: 60),
                  child: buildAlbumShimmer(),
                )
                : _album == null
                ? const Center(
                  child: Text(
                    "Failed to load album",
                    style: TextStyle(color: Colors.white70),
                  ),
                )
                : CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverAppBar(
                      pinned: true,
                      backgroundColor: Colors.transparent,
                      expandedHeight: 350,
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
                                colors: [albumCoverColour, Colors.black],
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
                                _album!.title,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            background: Padding(
                              padding: const EdgeInsets.only(
                                top: kToolbarHeight,
                              ),
                              child: Center(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: SizedBox(
                                    width:
                                        MediaQuery.of(context).size.width *
                                        0.80,
                                    height: 300,
                                    child: Image.network(
                                      _album!.images.isNotEmpty
                                          ? _album!.images.last.url
                                          : "",
                                      fit: BoxFit.contain,
                                    ),
                                  ),
                                ),
                              ),
                            ),
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
                                  if (!_isTitleCollapsed)
                                    Text(
                                      _album!.title,
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 20,
                                      ),
                                      // overflow: TextOverflow.ellipsis,
                                    ),
                                  if (_album!.artist.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4.0),
                                      child: Text(
                                        _album!.artist,
                                        style: TextStyle(
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
                                        style: TextStyle(
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
                                        style: TextStyle(
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

                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final song = _album!.songs[index];
                        return _buildSwipeSongCard(song);
                      }, childCount: _album!.songs.length),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  ],
                ),
      ),
    );
  }
}
