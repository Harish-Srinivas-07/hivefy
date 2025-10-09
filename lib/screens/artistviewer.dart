import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_swipe_action_cell/core/cell.dart';

import 'package:just_audio/just_audio.dart';
import 'package:page_transition/page_transition.dart';
import 'package:readmore/readmore.dart';

import '../components/shimmers.dart';
import '../components/snackbar.dart';
import '../models/datamodel.dart';
import '../services/audiohandler.dart';
import '../services/jiosaavn.dart';
import '../shared/constants.dart';
import '../utils/theme.dart';
import 'albumviewer.dart';

class ArtistViewer extends ConsumerStatefulWidget {
  final String artistId;

  const ArtistViewer({super.key, required this.artistId});

  @override
  ConsumerState<ArtistViewer> createState() => _ArtistViewerState();
}

class _ArtistViewerState extends ConsumerState<ArtistViewer> {
  ArtistDetails? _artist;
  bool _loading = true;
  Color artistCoverColour = Colors.pink;

  final ScrollController _scrollController = ScrollController();
  bool _isTitleCollapsed = false;

  @override
  void initState() {
    super.initState();
    _fetchArtist();
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

  Future<void> _updateBgColor() async {
    if (_artist?.images.last.url.isEmpty ?? true) return;

    final dominant = await getDominantColorFromImage(_artist!.images.last.url);
    if (dominant == null) return;
    if (!mounted) return;

    artistCoverColour = dominant;

    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchArtist() async {
    setState(() => _loading = true);
    final details = await SaavnAPI().fetchArtistDetailsById(
      artistId: widget.artistId,
    );
    await _updateBgColor();
    if (mounted) {
      _artist = details;
      _loading = false;
      setState(() {});
    }
  }

  Widget _buildHeader() {
    if (_artist == null) return const SizedBox.shrink();

    final imageUrl = _artist!.images.isNotEmpty ? _artist!.images.last.url : '';

    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
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
                              Icons.person,
                              size: 100,
                              color: Colors.white,
                            ),
                          ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _artist!.title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (_artist!.isVerified == true) ...[
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.verified,
                    size: 18,
                    color: Colors.blueAccent,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${_artist!.followerCount ?? 0} followers',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            if (_artist!.bio.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: ReadMoreText(
                  _artist!.bio.join("\n\n"),
                  trimLines: 3,
                  trimMode: TrimMode.Line,
                  colorClickableText: Colors.greenAccent,
                  trimCollapsedText: " ...more",
                  trimExpandedText: " Show less",
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                  moreStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.greenAccent,
                  ),
                  lessStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.greenAccent,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSongList() {
    final songs = _artist?.topSongs ?? [];
    if (_loading) return buildAlbumShimmer();

    if (songs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Top Songs",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    _artist?.dominantLanguage ??
                        _artist?.language ??
                        'Artist Favs',
                    style: TextStyle(
                      color: Colors.white30,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              _buildShufflePlayButtons(),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ...songs.map(
          (song) => ArtistSongRow(song: song, allSongs: _artist!.topSongs),
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
                  _artist != null &&
                  _artist!.topSongs.any((s) => s.id == currentSong.id);

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
                        _artist!.topSongs.length;
                  }

                  await audioHandler.loadQueue(
                    _artist!.topSongs,
                    startIndex: startIndex,
                    sourceId: _artist?.id,
                    sourceName: _artist?.title,
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

  Widget _buildAlbumList(String title, List<Album> albums) {
    if (_loading) return buildAlbumShimmer();
    if (albums.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            title,
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: artistCoverColour,
      body: Container(
        decoration: BoxDecoration(color: Colors.black),
        child:
            _loading
                ? Padding(
                  padding: const EdgeInsets.only(top: 60),
                  child: buildAlbumShimmer(),
                )
                : _artist == null
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
                                colors: [artistCoverColour, Colors.black],
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
                                _artist?.title ?? "",
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

                    SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 16),
                          _buildSongList(),

                          const SizedBox(height: 16),
                          _buildAlbumList(
                            "Top Albums",
                            _artist?.topAlbums ?? [],
                          ),
                          const SizedBox(height: 16),
                          _buildAlbumList("Singles", _artist?.singles ?? []),
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

class ArtistSongRow extends ConsumerWidget {
  final SongDetail song;
  final List<SongDetail> allSongs;

  const ArtistSongRow({super.key, required this.song, required this.allSongs});

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
          try {
            final audioHandler = await ref.read(audioHandlerProvider.future);
            final queue = audioHandler.queue.valueOrNull ?? [];
            final queueIds = queue.map((m) => m.id).toList();
            final isSameQueue =
                queueIds.length == allSongs.length &&
                queueIds.every((id) => allSongs.any((s) => s.id == id));

            final tappedIndex = allSongs.indexWhere((s) => s.id == song.id);
            if (tappedIndex == -1) return;

            // 1️⃣ Same song toggle play/pause
            if (isPlaying) {
              if (audioHandler.playbackState.value.playing) {
                await audioHandler.pause();
              } else {
                await audioHandler.play();
              }
              return;
            }

            // 2️⃣ Same queue → just skip
            if (isSameQueue) {
              await audioHandler.skipToQueueItem(tappedIndex);
              await audioHandler.play();
              return;
            }

            // 3️⃣ Load artist songs as new queue
            await audioHandler.loadQueue(allSongs, startIndex: tappedIndex);
            await audioHandler.play();
          } catch (e, st) {
            debugPrint("Error playing artist song: $e\n$st");
          }
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
                    Row(
                      children: [
                        if (isPlaying)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Image(
                              image: AssetImage('assets/player.gif'),
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
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
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
                const Padding(
                  padding: EdgeInsets.only(left: 10),
                  child: Icon(Icons.check_circle, color: Colors.green),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class AlbumRow extends StatelessWidget {
  final Album album;
  const AlbumRow({super.key, required this.album});

  @override
  Widget build(BuildContext context) {
    final imageUrl = album.images.isNotEmpty ? album.images.last.url : '';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.of(context).push(
          PageTransition(
            type: PageTransitionType.rightToLeft,
            duration: const Duration(milliseconds: 300),
            child: AlbumViewer(albumId: album.id),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child:
                  imageUrl.isNotEmpty
                      ? Image.network(imageUrl, fit: BoxFit.cover)
                      : Container(
                        color: Colors.grey.shade800,
                        child: const Icon(
                          Icons.album,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
            ),
          ),
          const SizedBox(height: 6),
          Flexible(
            child: Text(
              album.title,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          if (album.artist.isNotEmpty)
            Flexible(
              child: Text(
                album.artist,
                style: TextStyle(color: Colors.white54, fontSize: 12),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
        ],
      ),
    );
  }
}
