import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_swipe_action_cell/core/cell.dart';
import 'package:just_audio/just_audio.dart';
import 'package:page_transition/page_transition.dart';
import 'package:readmore/readmore.dart';

import '../../components/showmenu.dart';
import '../../components/snackbar.dart';
import '../../models/datamodel.dart';
import '../../components/shimmers.dart';
import '../../services/audiohandler.dart';
import '../../services/jiosaavn.dart';
import '../../services/latestsaavnfetcher.dart';
import '../../shared/constants.dart';
import '../../utils/format.dart';
import '../../utils/theme.dart';
import '../features/language.dart';

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
  List<Playlist> similarPlaylist = [];

  @override
  void initState() {
    super.initState();
    _fetchPlaylist();

    _scrollController.addListener(() {
      bool isCollapsed =
          _scrollController.hasClients &&
          _scrollController.offset > (400 - kToolbarHeight - 20);

      if (isCollapsed != _isTitleCollapsed) {
        _isTitleCollapsed = isCollapsed;
        if (mounted) setState(() {});
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

    if (!mounted) return;

    playlistCoverColor = getDominantDarker(dominant);

    if (mounted) setState(() {});
  }

  Future<void> _fetchPlaylist() async {
    if (mounted) setState(() => _loading = true);

    try {
      final playlist = await SaavnAPI().fetchPlaylistById(
        playlistId: widget.playlistId,
        limit: 50,
      );

      if (playlist == null) {
        debugPrint('No playlist or songs available for ${widget.playlistId}');
        if (mounted) setState(() => _loading = false);
        return;
      }

      _playlist = playlist;
      debugPrint(
        '--> ${widget.playlistId} Playlist has ${_playlist?.songs.length} songs',
      );
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

      final lang = ref.read(languageNotifierProvider).value;
      similarPlaylist =
          (await LatestSaavnFetcher.getLatestPlaylists(
              lang,
            )).where((p) => p.id != widget.playlistId).toList()
            ..shuffle();

      similarPlaylist = similarPlaylist.take(5).toList();
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
        child: Center(
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
              child: Image.asset(
                'assets/icons/shuffle.png',
                width: 24,
                height: 24,
                color: isShuffle ? spotifyGreen : Colors.grey[600],
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

  Widget _sectionList(String title, List<Playlist> list) {
    if (list.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16),
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            height: 220,
            child: PageView.builder(
              controller: PageController(viewportFraction: 0.45),
              padEnds: false,
              physics: const BouncingScrollPhysics(),
              itemCount: list.length,
              itemBuilder: (context, index) {
                final playlist = list[index];
                return Padding(
                  padding: EdgeInsets.only(left: 16),
                  child: _playlistCard(playlist),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _playlistCard(Playlist playlist) {
    final imageUrl =
        playlist.images.isNotEmpty ? playlist.images.first.url : '';
    final subtitle =
        playlist.artists.isNotEmpty
            ? playlist.artists.first.title
            : (playlist.songCount != null ? '${playlist.songCount} songs' : '');
    final description = playlist.description;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.of(context).push(
          PageTransition(
            type: PageTransitionType.rightToLeft,
            duration: const Duration(milliseconds: 300),
            child: PlaylistViewer(playlistId: playlist.id),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child:
                  imageUrl.isNotEmpty
                      ? CacheNetWorkImg(url: imageUrl, fit: BoxFit.cover)
                      : Container(
                        color: Colors.grey.shade800,
                        child: const Icon(
                          Icons.album,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
            ),
          ),
          const SizedBox(height: 6),
          Flexible(
            child: Text(
              playlist.title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          if (subtitle.isNotEmpty)
            Flexible(
              child: Text(
                subtitle,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          if (description.isNotEmpty)
            Flexible(
              child: Text(
                description,
                style: TextStyle(color: Colors.white38, fontSize: 10),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
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
                      expandedHeight: 400,
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!_isTitleCollapsed)
                              Text(
                                _playlist!.title,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            const SizedBox(height: 8),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (_playlist!.description.isNotEmpty)
                                        ReadMoreText(
                                          _playlist!.description,
                                          trimLines: 3,
                                          trimMode: TrimMode.Line,
                                          colorClickableText: spotifyGreen,
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
                                          padding: const EdgeInsets.only(
                                            top: 2.0,
                                          ),
                                          child: Text(
                                            formatDuration(
                                              _totalPlaylistDuration,
                                            ),
                                            style: TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [_buildShufflePlayButtons()],
                            ),
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
                        ],
                      ),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 35)),

                    SliverToBoxAdapter(
                      child: _sectionList(
                        'You might also like',
                        similarPlaylist,
                      ),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
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
          color: spotifyGreen,
          icon: Image.asset('assets/icons/add_to_queue.png', height: 20),
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
            final shuffleIndex =
                audioHandler.isShuffle
                    ? currentQueue.indexWhere((s) => s.id == song.id)
                    : tappedIndex;
            if (shuffleIndex == -1) return;
            await audioHandler.skipToQueueItem(shuffleIndex);
          } else {
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
          padding: const EdgeInsets.only(
            top: 8,
            left: 16,
            right: 6,
            bottom: 10,
          ),
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
                              'assets/icons/player.gif',
                              height: 18,
                              fit: BoxFit.contain,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            song.title,
                            style: TextStyle(
                              color: isPlaying ? spotifyGreen : Colors.white,
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
              if (isLiked)
                Padding(
                  padding: const EdgeInsets.only(right: 6, left: 6),
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
                  showMediaItemMenu(context, song);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
