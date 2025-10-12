import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_swipe_action_cell/core/cell.dart';

import '../../components/snackbar.dart';
import '../../models/database.dart';
import '../../models/datamodel.dart';
import '../../components/shimmers.dart';
import '../../services/audiohandler.dart';
import '../../services/jiosaavn.dart';
import '../../services/offlinemanager.dart';
import '../../shared/constants.dart';
import '../../shared/player.dart';
import '../../utils/format.dart';
import '../../utils/theme.dart';

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
  late ScrollController _scrollController;
  bool _isTitleCollapsed = false;

  @override
  void initState() {
    super.initState();
    _fetchSongs();
    _scrollController = ScrollController();
    _scrollController.addListener(() {
      setState(() {
        _isTitleCollapsed = _scrollController.offset > 200;
      });
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchSongs() async {
    setState(() => _loading = true);

    try {
      if (widget.showLikedSongs) {
        final ids = ref.read(likedSongsProvider);
        if (ids.isEmpty) {
          _songs = [];
          _totalDuration = 0;
          setState(() => _loading = false);
          return;
        }

        _songs = [];
        _totalDuration = 0;

        const batchSize = 20;
        final total = ids.length;

        for (int start = 0; start < total; start += batchSize) {
          final end = (start + batchSize).clamp(0, total);
          final batchIds = ids.sublist(start, end);

          // Fetch this batch of song details
          final freshDetails = await SaavnAPI().getSongDetails(ids: batchIds);

          // Keep original liked order
          final orderedBatch =
              batchIds.map((id) {
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

          _songs.addAll(orderedBatch);

          // Recalculate total duration
          _totalDuration = _songs.fold(
            0,
            (sum, s) => sum + (int.tryParse(s.duration ?? '0') ?? 0),
          );

          // Update UI progressively
          if (mounted) setState(() {});
        }
      } else {
        // For offline songs, no batching needed
        _songs = await AppDatabase.getAllSongs();
        _totalDuration = _songs.fold(
          0,
          (sum, s) => sum + (int.tryParse(s.duration ?? '0') ?? 0),
        );
      }
    } catch (e, st) {
      debugPrint("Failed to fetch songs: $e\n$st");
      _songs = [];
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildItemImage(String url) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: CacheNetWorkImg(
      url: url,
      width: 50,
      height: 50,
      fit: BoxFit.cover,
      borderRadius: BorderRadius.circular(6),
    ),
  );

  Widget _buildSongSwipeCard(SongDetail song) {
    final currentSong = ref.watch(currentSongProvider);

    final isPlaying = currentSong?.id == song.id;
    final isLiked = ref.watch(likedSongsProvider).contains(song.id);

    return ValueListenableBuilder(
      valueListenable: hasInternet,
      builder: (context, value, child) {
        bool isEnabled = true;

        if (!value) {
          isEnabled = offlineManager.isAvailableOffline(songId: song.id);
        }

        return SwipeActionCell(
          backgroundColor: Colors.transparent,
          key: ValueKey(song.id),
          fullSwipeFactor: 0.01,
          editModeOffset: 2,
          leadingActions: [
            SwipeAction(
              color: spotifyGreen,
              icon: Image.asset('assets/icons/add_to_queue.png', height: 20),
              performsFirstActionWithFullSwipe: true,
              onTap: (handler) async {
                final audioHandler = await ref.read(
                  audioHandlerProvider.future,
                );
                await audioHandler.addSongNext(song);
                info('${song.title} will play next', Severity.success);
                await handler(false);
              },
            ),
          ],
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              if (!isEnabled) return; // No internet

              try {
                final audioHandler = await ref.read(
                  audioHandlerProvider.future,
                );
                final currentQueue = audioHandler.queueSongs;
                final sourceId = audioHandler.queueSourceId;

                final isPlaying = ref.read(currentSongProvider)?.id == song.id;

                if (isPlaying) {
                  // Toggle pause/play
                  final playing =
                      (await audioHandler.playerStateStream.first).playing;
                  if (playing) {
                    await audioHandler.pause();
                  } else {
                    await audioHandler.play();
                  }
                  return;
                }

                final isSameLikedQueue =
                    sourceId == "liked_songs" && currentQueue.isNotEmpty;

                if (isSameLikedQueue) {
                  // Skip to the correct song in **current queue**
                  final queueIndex = currentQueue.indexWhere(
                    (s) => s.id == song.id,
                  );
                  if (queueIndex != -1) {
                    await audioHandler.skipToQueueItem(queueIndex);
                  } else {
                    // If somehow song not in queue, reload queue
                    await audioHandler.loadQueue(
                      _songs,
                      startIndex: _songs.indexWhere((s) => s.id == song.id),
                      sourceId: "liked_songs",
                      sourceName: "Liked Songs",
                    );
                  }
                } else {
                  // Load fresh queue
                  final startIndex = _songs.indexWhere((s) => s.id == song.id);
                  if (startIndex == -1) return;

                  await audioHandler.loadQueue(
                    _songs,
                    startIndex: startIndex,
                    sourceId: "liked_songs",
                    sourceName: "Liked Songs",
                  );
                }

                await audioHandler.play();
              } catch (e, st) {
                debugPrint("Error playing liked song: $e\n$st");
              }
            },

            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                children: [
                  _buildItemImage(
                    song.images.isNotEmpty ? song.images.last.url : '',
                  ),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isPlaying)
                              const Padding(
                                padding: EdgeInsets.only(right: 8),
                                child: Image(
                                  image: AssetImage('assets/icons/player.gif'),
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
                                          ? spotifyGreen
                                          : isEnabled
                                          ? Colors.white
                                          : Colors.white38,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 16,
                                ),
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          song.primaryArtists.isNotEmpty
                              ? song.primaryArtists
                              : song.album,
                          style: TextStyle(color: Colors.white70, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                  if (isLiked)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0),
                      child: Image.asset(
                        'assets/icons/tick.png',
                        width: 26,
                        height: 26,
                        fit: BoxFit.contain,
                        color: spotifyGreen,
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
          ),
        );
      },
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.only(
        top: kToolbarHeight + 16,
        bottom: 16,
        left: 16,
        right: 16,
      ),
      child: Center(
        child: SizedBox(
          width: 250,
          height: 250,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              color: Colors.pinkAccent.shade100.withAlpha(60),
              child: Center(
                child: Icon(
                  widget.showLikedSongs ? Icons.favorite : Icons.music_note,
                  size: 120,
                  color: Colors.pinkAccent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderInfo() {
    final isShuffle = ref.watch(shuffleProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            widget.showLikedSongs ? "Liked Songs" : "All Songs",
            style: TextStyle(
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
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Shuffle Button
              GestureDetector(
                onTap: () async {
                  final audioHandler = await ref.read(
                    audioHandlerProvider.future,
                  );
                  audioHandler.toggleShuffle();
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: const BoxDecoration(shape: BoxShape.circle),
                  child: Image.asset(
                    'assets/icons/shuffle.png',
                    width: 24,
                    height: 24,
                    color: isShuffle ? spotifyGreen : Colors.grey[600],
                  ),
                ),
              ),

              const SizedBox(width: 8),

              // Play/Pause Button
              StreamBuilder<PlayerState>(
                stream: ref
                    .read(audioHandlerProvider.future)
                    .asStream()
                    .asyncExpand((h) => h.playerStateStream),
                builder: (context, snapshot) {
                  final isPlaying = snapshot.data?.playing ?? false;
                  final currentSong = ref.watch(currentSongProvider);

                  final bool isCurrentLikedSong =
                      currentSong != null &&
                      _songs.any((s) => s.id == currentSong.id);

                  final icon =
                      isCurrentLikedSong
                          ? (isPlaying ? Icons.pause : Icons.play_arrow)
                          : Icons.play_arrow;

                  return GestureDetector(
                    onTap: () async {
                      try {
                        final audioHandler = await ref.read(
                          audioHandlerProvider.future,
                        );

                        if (isCurrentLikedSong) {
                          // 🔁 Toggle play/pause
                          if (isPlaying) {
                            await audioHandler.pause();
                          } else {
                            await audioHandler.play();
                          }
                        } else {
                          // 🚀 Load liked songs queue
                          int startIndex = 0;
                          if (isShuffle) {
                            startIndex =
                                DateTime.now().millisecondsSinceEpoch %
                                _songs.length;
                          }

                          await audioHandler.loadQueue(
                            _songs,
                            startIndex: startIndex,
                            sourceId: "liked_songs",
                            sourceName: "Liked Songs",
                          );

                          if (isShuffle && !audioHandler.isShuffle) {
                            audioHandler.toggleShuffle();
                          }

                          await audioHandler.play();
                        }
                      } catch (e, st) {
                        debugPrint("Error handling liked play button: $e\n$st");
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
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(currentSongProvider);
    ref.watch(likedSongsProvider);

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
                : _songs.isEmpty
                ? Center(
                  child: Text(
                    "No ${widget.showLikedSongs ? 'liked' : 'songs'} found",
                    style: const TextStyle(color: Colors.white70),
                  ),
                )
                : CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverAppBar(
                      pinned: true,
                      backgroundColor: Colors.transparent,
                      expandedHeight: 300,
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
                                  getDominantDarker(Colors.pink),
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
                                widget.showLikedSongs
                                    ? "Liked Songs"
                                    : "All Songs",
                                style: TextStyle(
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

                    SliverToBoxAdapter(child: const SizedBox(height: 16)),

                    SliverList(
                      delegate: SliverChildListDelegate([
                        _buildHeaderInfo(),
                        const SizedBox(height: 16),
                        ..._songs.map((song) => _buildSongSwipeCard(song)),
                        const SizedBox(height: 100),
                      ]),
                    ),
                  ],
                ),
      ),
    );
  }
}
