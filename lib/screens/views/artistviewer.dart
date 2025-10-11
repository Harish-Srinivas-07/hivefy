import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_swipe_action_cell/core/cell.dart';

import 'package:just_audio/just_audio.dart';
import 'package:page_transition/page_transition.dart';
import 'package:readmore/readmore.dart';

import '../../components/shimmers.dart';
import '../../components/snackbar.dart';
import '../../models/datamodel.dart';
import '../../services/audiohandler.dart';
import '../../services/jiosaavn.dart';
import '../../shared/constants.dart';
import '../../utils/format.dart';
import '../../utils/theme.dart';
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
  Color artistCoverColour = Colors.indigo;

  final ScrollController _scrollController = ScrollController();
  bool _isTitleCollapsed = false;

  @override
  void initState() {
    super.initState();
    _fetchArtist();
    _scrollController.addListener(() {
      bool isCollapsed =
          _scrollController.hasClients &&
          _scrollController.offset > (400 - kToolbarHeight - 20);

      if (isCollapsed != _isTitleCollapsed) {
        _isTitleCollapsed = isCollapsed;
        setState(() {});
      }
    });
  }

  Future<void> _updateBgColor() async {
    if (_artist == null || _artist!.images.isEmpty) return;

    final imageUrl = _artist!.images.last.url;
    if (imageUrl.isEmpty) return;

    final dominant = await getDominantColorFromImage(imageUrl);
    artistCoverColour = getDominantLighter(dominant);
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

    if (mounted) {
      _artist = details;
      _loading = false;
      setState(() {});
    }
    await _updateBgColor();
  }

  Widget _buildHeaderImage() {
    final imageUrl = _artist!.images.isNotEmpty ? _artist!.images.last.url : '';

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [artistCoverColour, spotifyBgColor],
        ),
      ),
      child: Center(
        child: SizedBox(
          width: 300,
          height: 300,
          child: AspectRatio(
            aspectRatio: 1,
            child: CacheNetWorkImg(
              url: imageUrl.isNotEmpty ? imageUrl : '',
              fit: BoxFit.cover,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderDetails() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!_isTitleCollapsed)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _artist!.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                if (_artist!.isVerified == true)
                  const Icon(
                    Icons.verified,
                    size: 18,
                    color: Colors.blueAccent,
                  ),
              ],
            ),
          const SizedBox(height: 4),
          Text(
            '${followersFormatter(_artist?.followerCount ?? 0)} followers',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          Text(
            'Known as ${_artist?.dominantType}',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          if (_artist!.bio.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: ReadMoreText(
                _artist!.bio.map((bio) => sanitizeBio(bio)).join("\n\n"),
                trimLines: 3,
                trimMode: TrimMode.Line,
                colorClickableText: spotifyGreen,
                trimCollapsedText: " ...more",
                trimExpandedText: " Show less",
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSongList() {
    final songs = _artist?.topSongs ?? [];
    if (_loading) return buildAlbumShimmer();

    if (songs.isEmpty || _artist == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [_buildShufflePlayButtons()],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
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
                'Famous for ${_artist?.dominantLanguage} Language',
                style: TextStyle(
                  color: Colors.white30,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        ...songs.map((song) => ArtistSongRow(song: song, artist: _artist!)),
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
                    sourceName: '${_artist?.title} Artist',
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: artistCoverColour,
      body: Container(
        decoration: BoxDecoration(color: spotifyBgColor),
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
                      backgroundColor: artistCoverColour,
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
                            _artist?.title ?? "",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        background: _buildHeaderImage(),
                      ),
                    ),

                    SliverToBoxAdapter(child: _buildHeaderDetails()),

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
                          _buildAlbumList(
                            "Top Singles",
                            _artist?.singles ?? [],
                          ),
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
  final ArtistDetails artist;

  const ArtistSongRow({super.key, required this.song, required this.artist});

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
                queueIds.length == artist.topSongs.length &&
                queueIds.every((id) => artist.topSongs.any((s) => s.id == id));

            final tappedIndex = artist.topSongs.indexWhere(
              (s) => s.id == song.id,
            );
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
            await audioHandler.loadQueue(
              artist.topSongs,
              startIndex: tappedIndex,
              sourceId: artist.id,
              sourceName: '${artist.title} Artist',
            );
            await audioHandler.play();
          } catch (e, st) {
            debugPrint("Error playing artist song: $e\n$st");
          }
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
                              color: isPlaying ? spotifyGreen : Colors.white,
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
                if (isLiked)
                  Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Image.asset(
                      'assets/icons/tick.png',
                      width: 20,
                      height: 20,
                      fit: BoxFit.contain,
                    ),
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
            child: CacheNetWorkImg(
              url: imageUrl,
              fit: BoxFit.cover,
              borderRadius: BorderRadius.circular(8),
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
