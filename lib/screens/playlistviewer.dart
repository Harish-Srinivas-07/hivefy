import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_swipe_action_cell/core/cell.dart';
import 'package:just_audio/just_audio.dart';
import 'package:readmore/readmore.dart';

import '../components/snackbar.dart';
import '../models/datamodel.dart';
import '../components/shimmers.dart';
import '../services/audiohandler.dart';
import '../services/jiosaavn.dart';
import '../shared/constants.dart';
import '../utils/format.dart';
import '../utils/theme.dart';

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
  Color playlistCoverColor = Colors.indigo;

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

  Future<void> _updateBgColor() async {
    if (_playlist?.images.last.url.isEmpty ?? true) return;

    final dominant = await getDominantColorFromImage(
      _playlist!.images.last.url,
    );
    if (dominant == null) return;
    if (!mounted) return;

    playlistCoverColor = dominant;

    if (mounted) setState(() {});
  }

  Future<void> _fetchPlaylist() async {
    setState(() => _loading = true);

    try {
      final playlist = await SaavnAPI().fetchPlaylistById(
        playlistId: widget.playlistId,
        limit: 50,
      );

      if (playlist == null || playlist.songs.isEmpty) {
        setState(() => _loading = false);
        return;
      }

      _playlist = playlist;
      await _updateBgColor();
      _playlistSongDetails = [];
      _totalPlaylistDuration = 0;

      const batchSize = 20;
      final totalSongs = playlist.songs.length;

      for (int start = 0; start < totalSongs; start += batchSize) {
        final end = (start + batchSize).clamp(0, totalSongs);
        final batchIds =
            playlist.songs.sublist(start, end).map((s) => s.id).toList();

        final batchDetails = await SaavnAPI().getSongDetails(ids: batchIds);
        _playlistSongDetails.addAll(batchDetails);

        _totalPlaylistDuration = getTotalDuration(_playlistSongDetails);
        if (mounted) setState(() => _loading = false);
      }
    } catch (e, st) {
      debugPrint("Error fetching playlist: $e\n$st");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildHeader() {
    if (_playlist == null) return const SizedBox.shrink();

    final imageUrl =
        _playlist!.images.isNotEmpty ? _playlist!.images.last.url : '';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [playlistCoverColor, spotifyBgColor],
        ),
      ),
      child: Padding(
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
              child:
                  imageUrl.isNotEmpty
                      ? CacheNetWorkImg(
                        url: imageUrl,
                        width: 300,
                        height: 300,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.circular(20),
                      )
                      : Container(
                        width: 300,
                        height: 300,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade800,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.playlist_play,
                          size: 100,
                          color: Colors.white,
                        ),
                      ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Text(
                _playlist!.title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSongList() {
    if (_loading && _playlistSongDetails.isEmpty) {
      return buildAlbumShimmer();
    }

    if (_playlistSongDetails.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Padding(
        //   padding: const EdgeInsets.symmetric(horizontal: 16),
        //   child: Text(
        //     "Songs",
        //     style: TextStyle(
        //       color: Colors.white,
        //       fontSize: 16,
        //       fontWeight: FontWeight.w600,
        //     ),
        //   ),
        // ),
        // const SizedBox(height: 8),
        ..._playlistSongDetails.map(
          (song) => SongRow(
            song: song,
            allSongs: _playlistSongDetails,
            playlist: _playlist!,
          ),
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
              final audioHandlerFuture = ref.read(audioHandlerProvider.future);

              final bool isCurrentPlaylistSong =
                  currentSong != null &&
                  _playlistSongDetails.any((s) => s.id == currentSong.id);

              final icon =
                  isCurrentPlaylistSong
                      ? (isPlaying ? Icons.pause : Icons.play_arrow)
                      : Icons.play_arrow;

              return GestureDetector(
                onTap: () async {
                  final audioHandler = await audioHandlerFuture;

                  if (isCurrentPlaylistSong) {
                    // 🔁 toggle playback
                    if (isPlaying) {
                      await audioHandler.pause();
                    } else {
                      await audioHandler.play();
                    }
                    return;
                  }

                  // 🚀 new playlist or empty queue
                  int startIndex = 0;
                  if (isShuffle) {
                    startIndex =
                        DateTime.now().millisecondsSinceEpoch %
                        _playlistSongDetails.length;
                  }

                  await audioHandler.loadQueue(
                    _playlistSongDetails,
                    startIndex: startIndex,
                    sourceId: widget.playlistId,
                    sourceName: '${_playlist?.title} Playlist',
                  );

                  if (isShuffle && !audioHandler.isShuffle) {
                    audioHandler.toggleShuffle();
                  }

                  await audioHandler.play();
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
      backgroundColor: playlistCoverColor,
      body: Container(
        decoration: BoxDecoration(color: spotifyBgColor),
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
                      backgroundColor: playlistCoverColor,
                      expandedHeight: 420,
                      elevation: 0,
                      leading: const BackButton(color: Colors.white),
                      flexibleSpace: FlexibleSpaceBar(
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
                                      style: TextStyle(
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

                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 10),
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
  final Playlist playlist;

  const SongRow({
    super.key,
    required this.song,
    required this.allSongs,
    required this.playlist,
  });

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
            await audioHandler.addSongNext(song);
            info('${song.title} will play next', Severity.success);
            await handler(false);
          },
        ),
      ],
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          final audioHandler = await ref.read(audioHandlerProvider.future);
          final currentQueue = audioHandler.queueSongs;
          final currentSource = audioHandler.queueSourceId;

          final isSamePlaylist = currentSource == playlist.id;
          final tappedIndex = allSongs.indexWhere((s) => s.id == song.id);

          if (tappedIndex == -1) return;

          if (isSamePlaylist && currentQueue.isNotEmpty) {
            // 🎯 Already playing this playlist → jump to that song
            await audioHandler.skipToQueueItem(tappedIndex);
          } else {
            // 🚀 Load new queue for this playlist
            await audioHandler.loadQueue(
              allSongs,
              startIndex: tappedIndex,
              sourceId: playlist.id,
              sourceName: '${playlist.title} Playlist',
            );
          }

          await audioHandler.play();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            children: [
              CacheNetWorkImg(
                url: song.images.isNotEmpty ? song.images.last.url : '',
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(width: 12),
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
                                  isPlaying ? Colors.greenAccent : Colors.white,
                              fontWeight: FontWeight.w500,
                              fontSize: 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (song.primaryArtists.isNotEmpty) song.primaryArtists,
                        if (song.album.isNotEmpty) song.album,
                        if (song.language.isNotEmpty) song.language,
                      ].join(' • '),
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isLiked) const Icon(Icons.check_circle, color: Colors.green),
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
  }
}
