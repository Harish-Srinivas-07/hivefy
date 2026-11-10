import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../components/staggered_appearance.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_swipe_action_cell/core/cell.dart';

import 'package:just_audio/just_audio.dart';
import 'package:page_transition/page_transition.dart';
import 'package:readmore/readmore.dart';
import 'package:shimmer/shimmer.dart';
import 'package:hivefy/utils/logger.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../components/empty_state.dart';
import '../../components/song_row_parts.dart';
import '../../components/shimmers.dart';
import '../../components/snackbar.dart';
import '../../components/showmenu.dart';
import '../../models/datamodel.dart';
import '../../services/apple_artist_art.dart';
import '../../services/audiohandler.dart';
import '../../services/youtube.dart';
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
  String? _appleHeroImageUrl;
  int _artistFetchGeneration = 0;
  bool _loading = true;
  Color artistCoverColour = Colors.indigo;

  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _isBioCollapsed = ValueNotifier(true);
  bool _isTitleCollapsed = false;

  @override
  void initState() {
    super.initState();
    _fetchArtist();
    _scrollController.addListener(() {
      bool isCollapsed = _scrollController.hasClients && _scrollController.offset > (400 - kToolbarHeight - 20);

      if (isCollapsed != _isTitleCollapsed) {
        _isTitleCollapsed = isCollapsed;
        setState(() {});
      }
    });
  }

  Future<void> _updateBgColor() async {
    final imageUrl = _headerImageUrl;
    if (imageUrl.isEmpty) return;

    final dominant = await getDominantColorFromImage(imageUrl, maxWidth: 96, maxHeight: 96);
    if (!mounted || _headerImageUrl != imageUrl) return;
    artistCoverColour = getDominantDarker(dominant);
    setState(() {});
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _isBioCollapsed.dispose();
    super.dispose();
  }

  Future<void> _fetchArtist() async {
    final generation = ++_artistFetchGeneration;
    setState(() {
      _loading = true;
      _artist = null;
      _appleHeroImageUrl = null;
      artistCoverColour = Colors.indigo;
      _isTitleCollapsed = false;
      _isBioCollapsed.value = true;
    });
    ArtistDetails? details;
    try {
      details = await YoutubeAPI().fetchArtistDetailsById(artistId: widget.artistId);
    } catch (error) {
      Logger.error('ArtistViewer', 'Unable to load artist ${widget.artistId}: $error');
    }

    if (!mounted || generation != _artistFetchGeneration) return;
    setState(() {
      _artist = details;
      _loading = false;
    });
    if (details == null) return;

    unawaited(_updateBgColor());

    final catalogueTitles = [
      ...details.topSongs.map((song) => song.title),
      ...details.topAlbums.map((album) => album.title),
      ...details.singles.map((album) => album.title),
    ];
    final appleArt = await AppleArtistArtRepository.instance.artFor(
      browseId: details.id,
      artistName: details.title,
      catalogueTitles: catalogueTitles,
    );
    if (!mounted || generation != _artistFetchGeneration || _artist?.id != details.id) return;
    if (appleArt == null || appleArt.heroUrl.isEmpty) {
      Logger.warn(
        'ArtistViewer',
        'No Apple artist hero image for "${details.title}" (${details.id}); using YouTube artwork.',
      );
      return;
    }

    Logger.log('ArtistViewer', 'Using Apple hero artwork for "${details.title}": ${appleArt.heroUrl}');
    setState(() => _appleHeroImageUrl = appleArt.heroUrl);
    unawaited(_updateBgColor());
  }

  @override
  void didUpdateWidget(covariant ArtistViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artistId == widget.artistId) return;
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
    _fetchArtist();
  }

  String get _headerImageUrl {
    final appleUrl = _appleHeroImageUrl?.trim() ?? '';
    if (appleUrl.isNotEmpty) return appleUrl;
    final images = _artist?.images ?? const <SourceUrl>[];
    for (final image in images.reversed) {
      if (image.url.trim().isNotEmpty) return image.url.trim();
    }
    return '';
  }

  Widget _buildHeaderImage() {
    final imageUrl = _headerImageUrl;
    final fallbackImageUrl = _artist?.images.reversed
        .map((image) => image.url.trim())
        .firstWhere((url) => url.isNotEmpty, orElse: () => '');

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [artistCoverColour, spotifyBgColor],
            ),
          ),
        ),
        if (imageUrl.isNotEmpty)
          Positioned.fill(
            child: imageUrl == _appleHeroImageUrl
                ? CachedNetworkImage(
                    key: ValueKey(imageUrl),
                    imageUrl: imageUrl,
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    placeholder: (context, url) => Shimmer.fromColors(
                      baseColor: Colors.grey.shade800,
                      highlightColor: Colors.grey.shade700,
                      child: Container(color: Colors.grey.shade800),
                    ),
                    errorWidget: (context, url, error) {
                      Logger.error('ArtistViewer', 'Apple artist image failed to load: $url ($error)');
                      final fallback = fallbackImageUrl?.trim() ?? '';
                      if (fallback.isEmpty || fallback == url) return const SizedBox.expand();
                      Logger.warn('ArtistViewer', 'Falling back to YouTube artist image: $fallback');
                      return CacheNetWorkImg(url: fallback, fit: BoxFit.cover, alignment: Alignment.center);
                    },
                  )
                : CacheNetWorkImg(url: imageUrl, fit: BoxFit.cover, alignment: Alignment.center),
          ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, artistCoverColour.withValues(alpha: .25), spotifyBgColor],
                  stops: const [0.42, 0.78, 1],
                ),
              ),
            ),
          ),
        ),
      ],
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
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
                ),
                if (_artist!.isVerified == true) const Icon(Icons.verified, size: 18, color: Colors.blueAccent),
              ],
            ),
          const SizedBox(height: 4),
          Text(
            '${followersFormatter(_artist?.followerCount ?? 0)} followers',
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          Text('Known as ${_artist?.dominantType}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
          if (_artist!.bio.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: () => _isBioCollapsed.value = !_isBioCollapsed.value,
                child: ReadMoreText(
                  _artist!.bio.map((bio) => sanitizeBio(bio)).join("\n\n"),
                  isCollapsed: _isBioCollapsed,
                  trimLines: 3,
                  trimMode: TrimMode.Line,
                  colorClickableText: spotifyGreen,
                  trimCollapsedText: " ...more",
                  trimExpandedText: " Show less",
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
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
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [_buildShufflePlayButtons()]),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Top Songs",
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
              ),
              Text(
                'Famous for ${_artist?.dominantLanguage} Language',
                style: TextStyle(color: Colors.white30, fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        for (var index = 0; index < songs.length; index++)
          StaggeredAppearance(
            index: index,
            child: ArtistSongRow(song: songs[index], artist: _artist!),
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

          // Play Artist / Top Songs / Shuffle
          StreamBuilder<PlayerState>(
            stream: ref.read(audioHandlerProvider.future).asStream().asyncExpand((h) => h.playerStateStream),
            builder: (context, snapshot) {
              final isPlaying = snapshot.data?.playing ?? false;
              final currentSong = ref.watch(currentSongProvider);

              return FutureBuilder(
                future: ref.read(audioHandlerProvider.future),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox();
                  final audioHandler = snapshot.data!;

                  // ✅ Check if current queue matches artist's top songs
                  final bool isSameSource = audioHandler.queueSourceId == _artist?.id;
                  final bool isCurrentInList =
                      isSameSource && currentSong != null && _artist!.topSongs.any((s) => s.id == currentSong.id);

                  // Icon logic
                  final icon = isCurrentInList ? (isPlaying ? Icons.pause : Icons.play_arrow) : Icons.play_arrow;

                  return GestureDetector(
                    onTap: () async {
                      try {
                        if (isSameSource) {
                          // 🔁 Current artist queue already loaded → toggle playback
                          if (isPlaying) {
                            await audioHandler.pause();
                          } else {
                            await audioHandler.play();
                          }
                        } else {
                          // 🚀 New artist queue → load top songs
                          int startIndex = 0;

                          // Shuffle handling
                          final isShuffle = ref.read(shuffleProvider);
                          if (isShuffle && _artist!.topSongs.isNotEmpty) {
                            startIndex = DateTime.now().millisecondsSinceEpoch % _artist!.topSongs.length;
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
                        }
                      } catch (e, st) {
                        Logger.error('ArtistViewer', "Error handling artist play button: $e\n$st");
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.green),
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

  Widget _buildAlbumList(String title, List<Album> albums, {bool grid = false}) {
    if (_loading) return buildAlbumShimmer();
    if (albums.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            title,
            style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(height: 8),
        if (grid)
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = (constraints.maxWidth - 48) / 2;
              return GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  mainAxisExtent: cardWidth + 54,
                ),
                itemCount: albums.length,
                itemBuilder: (context, index) => StaggeredAppearance(
                  index: index,
                  child: AlbumRow(album: albums[index]),
                ),
              );
            },
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            height: 200,
            child: PageView.builder(
              controller: PageController(viewportFraction: 0.45),
              padEnds: false,
              itemCount: albums.length,
              itemBuilder: (context, index) {
                return StaggeredAppearance(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 20),
                    child: AlbumRow(album: albums[index]),
                  ),
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
        child: _loading
            ? Padding(padding: const EdgeInsets.only(top: 60), child: buildAlbumShimmer())
            : _artist == null
            ? const EmptyStatePage(
                state: EmptyState(
                  icon: LucideIcons.users,
                  title: 'Artist unavailable',
                  subtitle: 'This artist could not be loaded. Please try again later.',
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
                      titlePadding: EdgeInsets.only(left: _isTitleCollapsed ? 72 : 16, bottom: 16, right: 16),
                      title: AnimatedOpacity(
                        opacity: _isTitleCollapsed ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          _artist?.title ?? "",
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
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
                        if (_artist!.topSongs.isEmpty && _artist!.topAlbums.isEmpty && _artist!.singles.isEmpty)
                          const EmptyState(
                            icon: LucideIcons.music2,
                            title: 'No music available',
                            subtitle: 'Songs and albums for this artist could not be found.',
                            compact: true,
                          ),
                        _buildSongList(),

                        const SizedBox(height: 16),
                        _buildAlbumList("Top Albums", _artist?.topAlbums ?? [], grid: true),
                        const SizedBox(height: 16),
                        _buildAlbumList("Top Singles", _artist?.singles ?? []),
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

class ArtistSongRow extends ConsumerStatefulWidget {
  final SongDetail song;
  final ArtistDetails artist;

  const ArtistSongRow({super.key, required this.song, required this.artist});

  @override
  ConsumerState<ArtistSongRow> createState() => _ArtistSongRowState();
}

class _ArtistSongRowState extends ConsumerState<ArtistSongRow> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final song = widget.song;
    final artist = widget.artist;
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
          if (_isLoading) return;
          setState(() => _isLoading = true);
          try {
            final audioHandler = await ref.read(audioHandlerProvider.future);
            final queue = audioHandler.queue.valueOrNull ?? [];
            final queueIds = queue.map((m) => m.id).toList();

            final tappedIndex = artist.topSongs.indexWhere((s) => s.id == song.id);
            if (tappedIndex == -1) return;

            final currentSong = ref.read(currentSongProvider);
            final isPlaying = currentSong?.id == song.id;
            final isShuffle = audioHandler.isShuffle;

            // -------------------------------
            // 1️⃣ Tapped song is currently playing → toggle play/pause
            // -------------------------------
            if (isPlaying) {
              final playing = (await audioHandler.playerStateStream.first).playing;
              if (playing) {
                await audioHandler.pause();
              } else {
                await audioHandler.play();
              }
              return;
            }

            // -------------------------------
            // 2️⃣ Queue already contains all artist top songs
            // -------------------------------
            final isSameQueue =
                queueIds.length == artist.topSongs.length &&
                queueIds.every((id) => artist.topSongs.any((s) => s.id == id));

            if (isSameQueue) {
              // Try to find tapped song after current song
              final currentIndex = queue.indexWhere((m) => m.id == currentSong?.id);

              int nextIndex = -1;
              if (currentIndex != -1 && currentIndex + 1 < queue.length) {
                final subQueue = queue.sublist(currentIndex + 1);
                final subIndex = subQueue.indexWhere((m) => m.id == song.id);
                if (subIndex != -1) nextIndex = currentIndex + 1 + subIndex;
              }

              // Fallback: search entire queue
              if (nextIndex == -1) {
                nextIndex = queue.indexWhere((m) => m.id == song.id);
              }

              if (nextIndex != -1) {
                await audioHandler.skipToQueueItem(nextIndex);
                await audioHandler.play();
                return;
              }
            }

            // -------------------------------
            // 3️⃣ Queue missing artist songs → load top songs
            // -------------------------------
            if (isShuffle) await audioHandler.disableShuffle();

            await audioHandler.loadQueue(
              artist.topSongs,
              startIndex: tappedIndex,
              sourceId: artist.id,
              sourceName: '${artist.title} Artist',
            );

            if (isShuffle) await audioHandler.toggleShuffle();

            await audioHandler.play();
          } catch (e, st) {
            Logger.error('ArtistViewer', "Error playing artist song: $e\n$st");
          } finally {
            if (mounted) setState(() => _isLoading = false);
          }
        },

        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            children: [
              SongRowArtwork(imageUrl: song.images.isNotEmpty ? song.images.last.url : ''),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SongRowTitle(title: song.title, isPlaying: isPlaying, maxLines: 1, isLoading: _isLoading),
                    Text(
                      song.primaryArtists.isNotEmpty ? song.primaryArtists : song.album,
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ],
                ),
              ),
              if (isLiked)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Image.asset(
                    'assets/icons/tick.png',
                    width: 26,
                    height: 26,
                    fit: BoxFit.contain,
                    color: spotifyGreen,
                  ),
                ),
              IconButton(
                icon: Image.asset('assets/icons/menu.png', width: 20, height: 20, color: Colors.white70),
                onPressed: () => showMediaItemMenu(context, song),
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
            child: CacheNetWorkImg(url: imageUrl, fit: BoxFit.cover, borderRadius: BorderRadius.circular(8)),
          ),
          const SizedBox(height: 6),
          Flexible(
            child: Text(
              album.title,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14),
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
