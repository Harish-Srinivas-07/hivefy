import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_swipe_action_cell/core/cell.dart';

import '../../components/showmenu.dart';
import '../../components/snackbar.dart';
import '../../models/datamodel.dart';
import '../../components/shimmers.dart';
import '../../services/latestsaavnfetcher.dart';
import '../../services/offlinemanager.dart';
import '../../services/audiohandler.dart';
import '../../services/jiosaavn.dart';
import '../../shared/constants.dart';
import '../../utils/format.dart';
import '../../utils/theme.dart';
import '../features/language.dart';
import 'artistviewer.dart';

class AlbumViewer extends ConsumerStatefulWidget {
  final String albumId;
  const AlbumViewer({super.key, required this.albumId});

  @override
  ConsumerState<AlbumViewer> createState() => _AlbumViewerState();
}

class _AlbumViewerState extends ConsumerState<AlbumViewer> {
  Album? _album;
  List<Album> _similarAlbum = [];
  List<SongDetail> _albumSongDetails = [];
  bool _loading = true;
  int _totalAlbumDuration = 0;
  Color albumCoverColour = spotifyBgColor;

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
        _isTitleCollapsed = isCollapsed;
        setState(() {});
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

    if (!mounted) return;
    final lang = ref.read(languageNotifierProvider).value;
    _similarAlbum =
        (await LatestSaavnFetcher.getLatestAlbums(
            lang,
          )).where((a) => a.id != widget.albumId).toList()
          ..shuffle();
    _similarAlbum = _similarAlbum.take(5).toList();
  }

  Future<void> _updateBgColor() async {
    if (_album?.images.last.url.isEmpty ?? true) return;

    final dominant = await getDominantColorFromImage(_album!.images.last.url);

    if (!mounted) return;

    albumCoverColour = getDominantLighter(dominant);

    if (mounted) setState(() {});
  }

  Widget _buildAlbumList(String title, List<Album> albums) {
    if (_loading) return buildAlbumShimmer();
    if (albums.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              title,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            height: 200,
            child: PageView.builder(
              controller: PageController(viewportFraction: 0.45),
              padEnds: false,
              itemCount: albums.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(right: 20),
                  child: AlbumRow(album: albums[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
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
          try {
            if (_albumSongDetails.isEmpty) return;

            final tappedIndex = _albumSongDetails.indexWhere(
              (s) => s.id == song.id,
            );
            if (tappedIndex == -1) return;

            final audioHandler = await ref.read(audioHandlerProvider.future);
            final currentQueue = audioHandler.queueSongs;
            final isShuffle = audioHandler.isShuffle;

            final albumIds = _albumSongDetails.map((s) => s.id).toSet();
            final queueIds = currentQueue.map((s) => s.id).toSet();
            final hasAlbumSongs = albumIds.difference(queueIds).isEmpty;

            // -------------------------------
            // CASE 1: Load album if not in queue
            // -------------------------------
            if (!hasAlbumSongs) {
              // Temporarily disable shuffle for ordered album load
              if (isShuffle) await audioHandler.disableShuffle();

              await audioHandler.loadQueue(
                _albumSongDetails,
                startIndex: tappedIndex,
                sourceId: widget.albumId,
                sourceName: '${_album?.title} Album',
              );

              // Re-enable shuffle if it was previously ON
              if (isShuffle) await audioHandler.toggleShuffle();
              return;
            }

            // -------------------------------
            // CASE 2: Queue already has album songs
            // -------------------------------
            final currentSong = ref.read(currentSongProvider);
            final currentIndex = currentQueue.indexWhere(
              (s) => s.id == currentSong?.id,
            );

            // If tapped song is currently playing → toggle play/pause
            if (currentSong?.id == song.id) {
              final playing =
                  (await audioHandler.playerStateStream.first).playing;
              if (playing) {
                await audioHandler.pause();
              } else {
                await audioHandler.play();
              }
              return;
            }

            // -------------------------------
            // CASE 3: Skip to tapped song in queue
            // Prefer songs after current index to avoid repeating
            // -------------------------------
            int targetIndex = -1;
            if (currentIndex != -1 && currentIndex + 1 < currentQueue.length) {
              final subQueue = currentQueue.sublist(currentIndex + 1);
              final subIndex = subQueue.indexWhere((s) => s.id == song.id);
              if (subIndex != -1) targetIndex = currentIndex + 1 + subIndex;
            }

            // Fallback: search entire queue
            if (targetIndex == -1) {
              targetIndex = currentQueue.indexWhere((s) => s.id == song.id);
            }

            if (targetIndex != -1) {
              await audioHandler.skipToQueueItem(targetIndex);
              await audioHandler.play();
            }
          } catch (e, st) {
            debugPrint("Error playing tapped album song: $e\n$st");
          }
        },

        child: Container(
          padding: const EdgeInsets.only(
            top: 8,
            left: 16,
            right: 6,
            bottom: 10,
          ),
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
                                    'assets/icons/player.gif',
                                    height: 18,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  song.title,
                                  style: TextStyle(
                                    color:
                                        isPlaying ? spotifyGreen : Colors.white,
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
                            song.contributors.all
                                .map((a) => a.title)
                                .toList()
                                .toSet()
                                .join(', '),
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
                      icon: Image.asset(
                        'assets/icons/menu.png',
                        width: 20,
                        height: 20,
                        color: Colors.white70,
                      ),
                      onPressed: () {
                        showMediaItemMenu(context, song);
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
          // --- Menu ---
          IconButton(
            icon: Image.asset(
              'assets/icons/menu.png',
              width: 20,
              height: 20,
              color: Colors.grey[600],
            ),
            onPressed: () {
              if (_album != null) showMediaItemMenu(context, _album!);
            },
          ),

          // --- Shuffle Button ---
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

          // --- Play/Pause or Start Album ---
          StreamBuilder<PlaybackState>(
            stream: ref
                .read(audioHandlerProvider.future)
                .asStream()
                .asyncExpand((h) => h.playbackState),
            builder: (context, snapshot) {
              final state = snapshot.data;
              final isPlaying = state?.playing ?? false;

              return FutureBuilder(
                future: ref.read(audioHandlerProvider.future),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox();
                  final audioHandler = snapshot.data!;
                  final currentSourceId = audioHandler.queueSourceId;
                  final bool isSameSource = currentSourceId == widget.albumId;

                  // --- Icon logic ---
                  final icon =
                      (isSameSource && isPlaying)
                          ? Icons.pause
                          : Icons.play_arrow;

                  return GestureDetector(
                    onTap: () async {
                      try {
                        if (isSameSource) {
                          // 🔁 Current album already loaded → just toggle playback
                          if (isPlaying) {
                            await audioHandler.pause();
                          } else {
                            await audioHandler.play();
                          }
                        } else {
                          // 🎵 New album — load full queue
                          await audioHandler.loadQueue(
                            _albumSongDetails,
                            startIndex: 0, // load all songs in order
                            sourceId: widget.albumId,
                            sourceName: '${_album?.title} Album',
                          );

                          // ✅ Shuffle handled internally by loadQueue()
                          // If shuffle is ON, just move to a random start position
                          final isShuffle = ref.read(shuffleProvider);
                          if (isShuffle && _albumSongDetails.isNotEmpty) {
                            final randomIndex =
                                DateTime.now().millisecondsSinceEpoch %
                                _albumSongDetails.length;
                            await audioHandler.skipToQueueItem(randomIndex);
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
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _downloadAlbumSong(Album album) {
    return ValueListenableBuilder<DownloadStatus>(
      valueListenable: offlineManager.albumStatusNotifier(album.id),
      builder: (context, status, _) {
        return ValueListenableBuilder<int>(
          valueListenable: offlineManager.albumDownloadedCountNotifier(
            album.id,
          ),
          builder: (context, downloadedCount, _) {
            Widget iconWidget;
            VoidCallback? onTap;

            if (status == DownloadStatus.completed) {
              iconWidget = Image.asset(
                'assets/icons/complete_download.png',
                width: 32,
                height: 32,
                color: spotifyGreen,
              );
              onTap = () async {
                offlineManager.deleteAlbumById(album.id);
              };
            } else if (status == DownloadStatus.downloading) {
              // ✅ Use same size + padding
              iconWidget = SizedBox(
                width: 32,
                height: 32,
                child: Padding(
                  padding: const EdgeInsets.all(6.0),
                  child: CircularProgressIndicator(
                    value: downloadedCount / album.songs.length,
                    color: spotifyGreen,
                    strokeWidth: 2.2,
                    backgroundColor: Colors.grey.shade800,
                  ),
                ),
              );
            } else {
              iconWidget = Image.asset(
                'assets/icons/download.png',
                width: 32,
                height: 32,
                color: Colors.white70,
              );
              onTap =
                  () async => await offlineManager.downloadAlbumSongs(album);
            }

            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: onTap,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  iconWidget,
                  const SizedBox(width: 6),
                  Text(
                    status == DownloadStatus.downloading
                        ? "$downloadedCount of ${album.songs.length} downloaded"
                        : status == DownloadStatus.completed
                        ? "Offline Available"
                        : "Download Album",
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
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
        decoration: BoxDecoration(color: spotifyBgColor),
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
                      backgroundColor: getDominantDarker(albumCoverColour),
                      expandedHeight: 300,
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
                            _album!.title,
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        background: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                getDominantDarker(albumCoverColour),
                                spotifyBgColor,
                              ],
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.only(top: kToolbarHeight),
                            child: Center(
                              child: CacheNetWorkImg(
                                url:
                                    _album!.images.isNotEmpty
                                        ? _album!.images.last.url
                                        : "",
                                width: 280,
                                height: 280,
                                fit: BoxFit.cover,
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
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
                                        '${_albumSongDetails.length} songs • ${formatDuration(_totalAlbumDuration)}',
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
                      ),
                    ),

                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            if (_album != null) _downloadAlbumSong(_album!),
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

                    SliverToBoxAdapter(
                      child: _buildAlbumList(
                        'You might also like',
                        _similarAlbum,
                      ),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  ],
                ),
      ),
    );
  }
}
