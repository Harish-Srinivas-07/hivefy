import 'package:audio_service/audio_service.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marquee/marquee.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';

import '../models/datamodel.dart';
import '../screens/queuesheet.dart';
import '../services/audiohandler.dart';
import '../services/jiosaavn.dart';
import '../utils/format.dart';
import '../utils/theme.dart';
import 'constants.dart';

final playerColourProvider = StateProvider<Color>((ref) => Colors.black);

class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  @override
  void initState() {
    super.initState();

    // Initial update
    _updatePlayerCardColour();
    // Schedule a delayed update after 5 seconds
    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) {
        _updatePlayerCardColour();
      }
    });
    // Also handle current song when widget initializes
    final song = ref.read(currentSongProvider);
    if (song != null && mounted) {
      _updatePlayerCardColour();
    }
  }

  Future<void> _updatePlayerCardColour() async {
    final song = ref.read(currentSongProvider);
    if (song?.images.isEmpty ?? true) return;

    final dominant = await getDominantColorFromImage(song!.images.last.url);
    if (dominant == null) return;
    if (!mounted) return;

    ref.read(playerColourProvider.notifier).state = dominant;
  }

  @override
  Widget build(BuildContext context) {
    final audioHandlerAsync = ref.watch(audioHandlerProvider);
    final song = ref.watch(currentSongProvider);
    bool isUserDragging = false;
    final controller = DraggableScrollableController();

    if (song == null) return const SizedBox.shrink();
    final isLiked = ref.watch(likedSongsProvider).contains(song.id);

    // Listen for changes in currentSongProvider to update color
    ref.listen<SongDetail?>(currentSongProvider, (previous, next) {
      if (next != null && next != previous) {
        _updatePlayerCardColour();
      }
    });

    return audioHandlerAsync.when(
      data:
          (audioHandler) => GestureDetector(
            onTap: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) {
                  return ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: GestureDetector(
                      onVerticalDragStart:
                          (_) => setState(() => isUserDragging = true),
                      onVerticalDragEnd: (_) {
                        setState(() => isUserDragging = false);
                        if (!isUserDragging && controller.size < 0.95) {
                          Navigator.of(context).pop();
                        }
                      },
                      child: DraggableScrollableSheet(
                        controller: controller,
                        expand: false,
                        initialChildSize: 1.0,
                        minChildSize: .95,
                        maxChildSize: 1.0,
                        builder: (context, scrollController) {
                          return FullPlayerScreen(
                            scrollController: scrollController,
                          );
                        },
                      ),
                    ),
                  );
                },
              ).then((_) {
                if (!context.mounted) return;
                FocusScope.of(context).unfocus();
              });
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              padding: const EdgeInsets.only(top: 3),
              decoration: ShapeDecoration(
                color: ref.watch(playerColourProvider),
                shape: SmoothRectangleBorder(
                  borderRadius: SmoothBorderRadius(
                    cornerRadius: 8,
                    cornerSmoothing: 0.8,
                  ),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: [
                        // Artwork
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: Image.network(
                            song.images.isNotEmpty ? song.images.last.url : "",
                            height: 40,
                            width: 40,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 10),

                        // Title + Artist
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _marqueeText(
                                song.title,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                              Text(
                                song.contributors.primary.first.title,
                                style: TextStyle(
                                  color: Colors.white.withAlpha(190),
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),

                        // Like / Add button
                        IconButton(
                          onPressed: () {
                            ref
                                .read(likedSongsProvider.notifier)
                                .toggle(song.id);
                          },
                          icon: Icon(
                            isLiked
                                ? Icons.check_circle
                                : Icons.add_circle_outline,
                            color: isLiked ? Colors.green : Colors.white,
                            size: 28,
                          ),
                        ),

                        // Play / Pause / Loading button
                        SizedBox(
                          width: 36,
                          height: 36,
                          child: Center(
                            child: StreamBuilder<PlayerState>(
                              stream: audioHandler.playerStateStream,
                              builder: (context, snapshot) {
                                final state = snapshot.data;
                                final playing = state?.playing ?? false;

                                if (state?.processingState ==
                                        ProcessingState.loading ||
                                    state?.processingState ==
                                        ProcessingState.buffering) {
                                  return const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.greenAccent,
                                    ),
                                  );
                                }

                                return IconButton(
                                  padding: EdgeInsets.zero,
                                  icon: Icon(
                                    playing
                                        ? Icons.pause_outlined
                                        : Icons.play_arrow,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                  onPressed: () {
                                    playing
                                        ? audioHandler.pause()
                                        : audioHandler.play();
                                  },
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 3),

                  // Progress bar
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: StreamBuilder<Duration>(
                      stream: AudioService.position,
                      builder: (context, snapshot) {
                        final pos = snapshot.data ?? Duration.zero;
                        final total = Duration(
                          seconds: int.tryParse(song.duration ?? '0') ?? 0,
                        );

                        final progress =
                            total.inMilliseconds > 0
                                ? pos.inMilliseconds / total.inMilliseconds
                                : 0.0;

                        return ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: progress,
                            backgroundColor: Colors.white.withAlpha(51),
                            valueColor: const AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                            minHeight: 2,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class FullPlayerScreen extends ConsumerStatefulWidget {
  final ScrollController? scrollController;
  // const FullPlayerScreen({super.key});
  const FullPlayerScreen({super.key, this.scrollController});

  @override
  ConsumerState<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends ConsumerState<FullPlayerScreen> {
  ArtistDetails? _artistDetails;
  final ValueNotifier<bool> _isBioExpanded = ValueNotifier(false);
  final PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _updateBgColor();
    _fetchArtistDetails();
  }

  @override
  void dispose() {
    super.dispose();
    _isBioExpanded.dispose();
  }

  Future<void> _updateBgColor() async {
    final song = ref.read(currentSongProvider);
    if (song?.images.isEmpty ?? true) return;

    final dominant = await getDominantColorFromImage(song!.images.last.url);
    if (dominant == null) return;

    ref.read(playerColourProvider.notifier).state = dominant;

    if (mounted) setState(() {});
  }

  Future<void> _fetchArtistDetails() async {
    final song = ref.read(currentSongProvider);
    if (song == null) return;

    final primaryContributors = song.contributors.primary;
    if (primaryContributors.isEmpty) return;

    final artistId = primaryContributors.first.id;
    if (artistId.isEmpty) return;

    final api = SaavnAPI();
    final details = await api.fetchArtistDetailsById(artistId: artistId);

    if (mounted && details != null) {
      _artistDetails = details;
      _isBioExpanded.value = false;
      if (mounted) setState(() {});
      debugPrint('--> loaded artist details: $_artistDetails');
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return "$m:${s.toString().padLeft(2, '0')}";
  }

  void openQueueBottomSheet() {
    final song = ref.watch(currentSongProvider);
    final size = MediaQuery.of(context).size;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder:
          (context) => DraggableScrollableSheet(
            initialChildSize: 0.5,
            minChildSize: 0.01,
            maxChildSize: .95,
            expand: false,
            snap: true,
            builder:
                (_, scrollController) => Container(
                  constraints: BoxConstraints(
                    maxHeight: size.height,
                    maxWidth: size.width,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.grey.shade900, Colors.black87],
                    ),
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
                  child: Column(
                    children: [
                      // Drag handle
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: SizedBox(
                          width: 40,
                          height: 4,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white54,
                              borderRadius: BorderRadius.all(
                                Radius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // Header
                      Align(
                        alignment: Alignment.topLeft,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                "Queue",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text(
                                    "Playing ",
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.white60,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      song?.album ?? 'Now',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: Colors.white54,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Queue list
                      Flexible(
                        fit: FlexFit.tight,
                        child: QueueList(scrollController: scrollController),
                      ),
                    ],
                  ),
                ),
          ),
    );
  }

  Widget _artistInfoWidget() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: ClipRRect(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(color: Colors.grey[900]),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image with overlay
              if (_artistDetails!.images.isNotEmpty)
                Stack(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 220,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.rotationZ(0),
                          child: Image.network(
                            _artistDetails!.images.last.url,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    ),

                    Container(
                      height: 220,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withAlpha(150),
                            Colors.transparent,
                          ],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 6,
                      left: 16,
                      right: 16,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Text(
                              _artistDetails!.title,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                shadows: [
                                  Shadow(
                                    blurRadius: 10.0,
                                    color: Colors.black,
                                    offset: Offset(2.0, 2.0),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (_artistDetails!.isVerified == true)
                            const Icon(
                              Icons.verified,
                              color: Colors.blueAccent,
                              size: 20,
                            ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 16,
                      left: 16,
                      right: 16,
                      child: Text(
                        'About the artist',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          shadows: [
                            Shadow(
                              blurRadius: 10.0,
                              color: Colors.black,
                              offset: Offset(2.0, 2.0),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 12),

              // Stats
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Text(
                  [
                    if (_artistDetails!.followerCount != null)
                      "Followers: ${_artistDetails!.followerCount}",
                    if (_artistDetails!.dominantLanguage.isNotEmpty)
                      "Language: ${_artistDetails!.dominantLanguage}",
                  ].join(" • "),
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),

              const SizedBox(height: 12),

              if (_artistDetails!.bio.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _isBioExpanded,
                    builder: (context, expanded, _) {
                      final fullBio = _artistDetails!.bio
                          .map((bio) => sanitizeBio(bio))
                          .join("\n\n");

                      final displayBio =
                          expanded
                              ? fullBio
                              : (fullBio.length > 180
                                  ? '${fullBio.substring(0, 180)}...'
                                  : fullBio);

                      return GestureDetector(
                        onTap: () => _isBioExpanded.value = !expanded,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayBio,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              expanded ? "Show less" : "Read more",
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.greenAccent,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _playBackControl() {
    final isShuffle = ref.watch(shuffleProvider);
    final repeatMode = ref.watch(repeatModeProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: FutureBuilder<MyAudioHandler>(
        future: ref.read(audioHandlerProvider.future),
        builder: (context, snapshot) {
          final audioHandler = snapshot.data;
          if (audioHandler == null) {
            return const SizedBox.shrink();
          }

          return StreamBuilder<PlayerState>(
            stream: audioHandler.playerStateStream,
            builder: (context, stateSnapshot) {
              final playerState = stateSnapshot.data;
              final playing = playerState?.playing ?? false;

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // Shuffle
                  _ControlButton(
                    icon: Icons.shuffle,
                    enabled: true,
                    iconColor: isShuffle ? Colors.greenAccent : Colors.white70,
                    onTap: () => audioHandler.toggleShuffle(),
                  ),

                  // Previous
                  _ControlButton(
                    icon: Icons.skip_previous,
                    enabled: audioHandler.hasPrevious,
                    onTap:
                        audioHandler.hasPrevious
                            ? () => audioHandler.skipToPrevious()
                            : null,
                    size: 45,
                  ),

                  // Play / Pause
                  _ControlButton(
                    icon: playing ? Icons.pause : Icons.play_arrow,
                    enabled: true,
                    onTap:
                        () =>
                            playing
                                ? audioHandler.pause()
                                : audioHandler.play(),
                    size: 64,
                    background: Colors.white,
                    iconColor: Colors.black,
                  ),

                  // Next
                  _ControlButton(
                    icon: Icons.skip_next,
                    enabled: audioHandler.hasNext,
                    onTap:
                        audioHandler.hasNext
                            ? () => audioHandler.skipToNext()
                            : null,
                    size: 45,
                  ),

                  // Repeat
                  _ControlButton(
                    icon:
                        repeatMode == RepeatMode.one
                            ? Icons.repeat_one
                            : Icons.repeat,
                    iconColor:
                        repeatMode == RepeatMode.none
                            ? Colors.white70
                            : Colors.greenAccent,
                    enabled: true,
                    onTap: () => audioHandler.toggleRepeatMode(),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _streamProgressBar() {
    return FutureBuilder<MyAudioHandler>(
      future: ref.read(audioHandlerProvider.future),
      builder: (context, snapshot) {
        final audioHandler = snapshot.data;
        if (audioHandler == null) {
          return const SizedBox.shrink();
        }

        // Watch current song so UI updates when song changes
        final song = ref.watch(currentSongProvider);
        final total = Duration(
          seconds: int.tryParse(song?.duration ?? '0') ?? 0,
        );

        return StreamBuilder<Duration>(
          stream: audioHandler.positionStream,
          builder: (context, posSnapshot) {
            final pos = posSnapshot.data ?? Duration.zero;

            final progress =
                total.inMilliseconds > 0
                    ? pos.inMilliseconds / total.inMilliseconds
                    : 0.0;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 5),
              child: Column(
                children: [
                  // Slider
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 6,
                        pressedElevation: 8,
                      ),
                      overlayShape: SliderComponentShape.noOverlay,
                      trackHeight: 2.5,
                    ),
                    child: Slider(
                      value: progress.clamp(0.0, 1.0),
                      onChanged:
                          total == Duration.zero
                              ? null
                              : (v) => audioHandler.seek(
                                Duration(
                                  milliseconds:
                                      (v * total.inMilliseconds).toInt(),
                                ),
                              ),
                      activeColor: Colors.white,
                      inactiveColor: Colors.white54.withAlpha(50),
                    ),
                  ),

                  // Position / Duration labels
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _fmt(pos),
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        Text(
                          _fmt(total),
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
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
    final song = ref.watch(currentSongProvider);

    if (song == null) {
      return const SizedBox.shrink();
    }
    final isLiked = ref.watch(likedSongsProvider).contains(song.id);

    final secondaryParts = <String>[];
    if ((song.albumName ?? song.album).isNotEmpty) {
      secondaryParts.add(song.albumName ?? song.album);
    }
    if (song.primaryArtists.isNotEmpty) {
      secondaryParts.add(song.primaryArtists);
    }

    final handlerAsync = ref.watch(audioHandlerProvider);

    return handlerAsync.when(
      data: (handler) {
        final queueAsync = ref.watch(queueStreamProvider(handler));
        ref.read(audioHandlerProvider.future).then((handler) {
          handler.playbackState.listen((state) {
            final index = handler.currentIndex;

            if (_pageController.hasClients &&
                index >= 0 &&
                index < handler.queueLength &&
                index != _pageController.page?.round()) {
              _pageController.jumpToPage(index);
            }
          });
        });

        return queueAsync.when(
          data: (queue) {
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [ref.watch(playerColourProvider), Colors.black],
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 50),
                    // header
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            icon: const Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.white,
                              size: 24,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          SizedBox(
                            width: MediaQuery.of(context).size.width * 0.6,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  "Now Playing".toUpperCase(),
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                                Consumer(
                                  builder: (context, ref, _) {
                                    final audioHandler =
                                        ref
                                            .watch(audioHandlerProvider)
                                            .valueOrNull;
                                    final sourceName =
                                        audioHandler?.queueSourceName;

                                    if (sourceName == null ||
                                        sourceName.isEmpty) {
                                      return const SizedBox.shrink();
                                    }

                                    return _marqueeText(
                                      sourceName,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.more_vert,
                              color: Colors.white70,
                              size: 24,
                            ),
                            onPressed: () {
                              // TODO: Show song menu
                            },
                          ),
                        ],
                      ),
                    ),
                    //  scrollable player
                    Expanded(
                      child: SingleChildScrollView(
                        controller: widget.scrollController,
                        child: Column(
                          children: [
                            const SizedBox(height: 30),
                            SizedBox(
                              height: 300,
                              child: PageView.builder(
                                controller: _pageController,
                                itemCount: handler.queueLength,
                                onPageChanged: (index) async {
                                  final handler = await ref.read(
                                    audioHandlerProvider.future,
                                  );
                                  if (handler.currentIndex != index) {
                                    await handler.skipToQueueItem(index);
                                  }
                                },

                                itemBuilder: (context, index) {
                                  final song = handler.queueSongs[index];
                                  return Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width:
                                            MediaQuery.of(context).size.width *
                                            0.8,
                                        height: 300,
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          child: Image.network(
                                            song.images.isNotEmpty
                                                ? song.images.last.url
                                                : "",
                                            fit: BoxFit.contain,
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),

                            const SizedBox(height: 35),

                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 15,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _marqueeText(
                                            trimAfterParamText(song.title),
                                            fontSize: 22,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          if (secondaryParts.isNotEmpty)
                                            _marqueeText(
                                              secondaryParts.join(" • "),
                                              fontSize: 15,
                                              fontWeight: FontWeight.w300,
                                              color: Colors.white70,
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8.0),
                                    child: IconButton(
                                      icon: Icon(
                                        isLiked
                                            ? Icons.favorite
                                            : Icons.favorite_border,
                                      ),
                                      color:
                                          isLiked ? Colors.red : Colors.white,
                                      tooltip: "Add to liked songs",
                                      onPressed: () {
                                        ref
                                            .read(likedSongsProvider.notifier)
                                            .toggle(song.id);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            _streamProgressBar(),
                            const SizedBox(height: 15),
                            _playBackControl(),
                            const SizedBox(height: 12),

                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  IconButton(
                                    icon: const Icon(
                                      Icons.queue_music,
                                      size: 24,
                                    ),
                                    color: Colors.white70,
                                    tooltip: "Queue",
                                    onPressed: () {
                                      openQueueBottomSheet();
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.share, size: 24),
                                    color: Colors.white70,
                                    tooltip: "Share",
                                    onPressed: () async {
                                      debugPrint('--> Share pressed');

                                      final box =
                                          context.findRenderObject()
                                              as RenderBox?;

                                      // Prepare nice user-friendly share text
                                      final details = StringBuffer();
                                      details.writeln(
                                        "Sharing from Hivefy 🎵\n",
                                      );
                                      details.writeln("Song: ${song.title}");
                                      if (song.primaryArtists.isNotEmpty) {
                                        details.writeln(
                                          "Artist(s): ${song.primaryArtists}",
                                        );
                                      }
                                      if ((song.albumName ?? song.album)
                                          .isNotEmpty) {
                                        details.writeln(
                                          "Album: ${song.albumName ?? song.album}",
                                        );
                                      }
                                      if (song.duration != null) {
                                        details.writeln(
                                          "Duration: ${song.getHumanReadableDuration()}",
                                        );
                                      }
                                      if (song.year != null) {
                                        details.writeln("Year: ${song.year}");
                                      }
                                      if (song.url.isNotEmpty) {
                                        details.writeln("URL: ${song.url}");
                                      }

                                      await SharePlus.instance.share(
                                        ShareParams(
                                          text: details.toString(),
                                          files:
                                              song.images.isNotEmpty
                                                  ? [
                                                    XFile.fromData(
                                                      (await NetworkAssetBundle(
                                                        Uri.parse(
                                                          song.images.last.url,
                                                        ),
                                                      ).load(
                                                        song.images.last.url,
                                                      )).buffer.asUint8List(),
                                                      mimeType: 'image/jpeg',
                                                      name:
                                                          '${song.title}_hivefy.jpg',
                                                    ),
                                                  ]
                                                  : [],
                                          title: "Sharing from Hivefy 🎵",
                                          sharePositionOrigin:
                                              box!.localToGlobal(Offset.zero) &
                                              box.size,
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 24),

                            if (_artistDetails != null) ...[
                              _artistInfoWidget(),
                              const SizedBox(height: 24),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => Center(child: Text("Error loading queue")),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => Center(child: Text("Error loading handler")),
    );
  }
}

// control button
class _ControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool enabled;
  final double size;
  final Color background;
  final Color iconColor;

  const _ControlButton({
    required this.icon,
    this.onTap,
    this.enabled = true,
    this.size = 40,
    this.background = Colors.transparent,
    this.iconColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Icon(
          icon,
          color: enabled ? iconColor : Colors.white24,
          size: size * 0.6,
        ),
      ),
    );
  }
}

// shared fn
Widget _marqueeText(
  String text, {
  double fontSize = 14,
  FontWeight fontWeight = FontWeight.w600,
  color = Colors.white,
}) {
  if (text.length <= 30) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  return SizedBox(
    height: fontSize,
    child: Marquee(
      text: text,
      style: TextStyle(
        color: Colors.white,
        fontSize: fontSize,
        fontWeight: fontWeight,
      ),
      velocity: 25,
      blankSpace: 50,
      fadingEdgeStartFraction: .5,
      fadingEdgeEndFraction: .5,
      startAfter: const Duration(seconds: 1),
      pauseAfterRound: const Duration(seconds: 1),
    ),
  );
}
