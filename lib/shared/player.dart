import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marquee/marquee.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';

import '../components/shimmers.dart';
import '../components/showmenu.dart';
import '../components/timersheet.dart';
import '../models/datamodel.dart';
import '../services/offlinemanager.dart';
import '../screens/features/queuesheet.dart';
import '../services/audiohandler.dart';
import '../services/jiosaavn.dart';
import '../services/sleeptimer.dart';
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
    // Schedule a delayed update after 3 seconds
    Future.delayed(const Duration(seconds: 3), () {
      _updatePlayerCardColour();
      if (mounted) {}
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

    if (!mounted) return;

    ref.read(playerColourProvider.notifier).state = getDominantDarker(dominant);
  }

  @override
  Widget build(BuildContext context) {
    final audioHandlerAsync = ref.watch(audioHandlerProvider);
    final song = ref.watch(currentSongProvider);

    if (song == null) return const SizedBox.shrink();
    final isLiked = ref.watch(likedSongsProvider).contains(song.id);
    double addIconSize = isLiked ? 28 : 33;

    // Listen for changes in currentSongProvider to update color
    ref.listen<SongDetail?>(currentSongProvider, (previous, next) {
      if (next != null && next != previous) {
        _updatePlayerCardColour();
      }
    });

    return audioHandlerAsync.when(
      data:
          (audioHandler) => GestureDetector(
            onHorizontalDragEnd: (details) async {
              final velocity = details.primaryVelocity ?? 0;
              if (velocity > 300) {
                // Swipe Right → Previous
                await audioHandler.skipToPrevious();
              } else if (velocity < -300) {
                // Swipe Left → Next
                await audioHandler.skipToNext();
              }
            },
            onTap: () async {
              await showModalBottomSheet(
                context: context,
                useRootNavigator: true,
                isScrollControlled: true,
                isDismissible: true,
                enableDrag: true,
                backgroundColor: Colors.transparent,
                barrierColor: Colors.black12,
                builder: (ctx) {
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      return Container(
                        width: constraints.maxWidth,
                        height: MediaQuery.of(context).size.height,
                        color: Colors.transparent,
                        child: Stack(
                          children: [
                            // --- Background Overlay ---
                            Container(color: Colors.black87),

                            // --- Rounded Player Sheet ---
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(24),
                                ),
                                child: DraggableScrollableSheet(
                                  expand: true,
                                  initialChildSize: 1.0,
                                  minChildSize: 0.95,
                                  maxChildSize: 1.0,

                                  builder: (_, scrollController) {
                                    return Container(
                                      width: double.infinity,
                                      height: double.infinity,
                                      decoration: const BoxDecoration(
                                        color: Colors.black,
                                        borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(24),
                                        ),
                                      ),
                                      clipBehavior: Clip.hardEdge,
                                      child: FullPlayerScreen(
                                        scrollController: scrollController,
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),

                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: IgnorePointer(
                                child: Container(
                                  height: 40,
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.black54,
                                        Colors.transparent,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              );

              if (!context.mounted) return;
              FocusScope.of(context).unfocus();
              Navigator.of(
                context,
                rootNavigator: true,
              ).popUntil((r) => r.isFirst);
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Artwork
                        CacheNetWorkImg(
                          url:
                              song.images.isNotEmpty
                                  ? song.images.last.url
                                  : '',
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        const SizedBox(width: 10),

                        // Title + Artist
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _marqueeText(
                                trimAfterParamText(song.title),
                                fontSize: 12,
                                letterSpacing: -.5,
                                fontWeight: FontWeight.w600,
                              ),
                              const SizedBox(height: 2),
                              _marqueeText(
                                '${song.contributors.all.first.title} • ${song.album}',
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                              ),
                            ],
                          ),
                        ),

                        // Like / Add button
                        GestureDetector(
                          onTap: () {
                            ref
                                .read(likedSongsProvider.notifier)
                                .toggle(song.id);
                          },
                          child: Padding(
                            padding: EdgeInsets.only(right: isLiked ? 8 : 5),
                            child: Image.asset(
                              isLiked
                                  ? 'assets/icons/tick.png'
                                  : 'assets/icons/add.png',
                              width: addIconSize,
                              height: addIconSize,
                              color: isLiked ? spotifyGreen : Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 3),

                        // Play / Pause / Loading button
                        SizedBox(
                          width: 32,
                          height: 32,
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
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: spotifyGreen,
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
    _pageController.dispose();
    _isBioExpanded.dispose();
    super.dispose();
  }

  Future<void> _updateBgColor() async {
    final song = ref.read(currentSongProvider);
    if (song?.images.isEmpty ?? true) return;

    final dominant = await getDominantColorFromImage(song!.images.last.url);
    ref.read(playerColourProvider.notifier).state = getDominantDarker(dominant);

    if (mounted) setState(() {});
  }

  Future<void> _fetchArtistDetails() async {
    final song = ref.read(currentSongProvider);
    if (song == null) return;

    final artistId = song.contributors.all.first.id;
    // if (primaryContributors.isEmpty) return;

    // final artistId = primaryContributors.first.id;
    if (artistId.isEmpty) return;

    final api = SaavnAPI();
    final details = await api.fetchArtistDetailsById(artistId: artistId);

    if (mounted && details != null) {
      _artistDetails = details;
      _isBioExpanded.value = false;
      if (mounted) setState(() {});
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
                    mainAxisSize: MainAxisSize.min,
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
                            vertical: 2,
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

  Widget _buildStatItem(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontFamily: 'SpotifyMix',
          fontSize: 13,
          color: Colors.white70,
          letterSpacing: 0,
          height: 1.3,
        ),
        children: [
          TextSpan(
            text: capitalize(value),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
          TextSpan(
            text: " $label",
            style: const TextStyle(
              color: Colors.white54,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
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
                      height: 200,
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                        ),
                        child: CacheNetWorkImg(
                          url:
                              _artistDetails!.images.isNotEmpty
                                  ? _artistDetails!.images.last.url
                                  : '',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),

                    Container(
                      height: 200,
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
              // --- Stats Section ---
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            _artistDetails!.title,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              letterSpacing: -1.1,
                              fontWeight: FontWeight.w600,
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
                    if (_artistDetails!.followerCount != null)
                      _buildStatItem(
                        "followers",
                        followersFormatter(_artistDetails!.followerCount ?? 0),
                      ),
                    if (_artistDetails!.dominantLanguage.isNotEmpty)
                      _buildStatItem(
                        "language",
                        _artistDetails!.dominantLanguage,
                      ),
                  ],
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
                                color: spotifyGreen,
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
              final processing = playerState?.processingState;
              final playing = playerState?.playing ?? false;

              final isLoading =
                  processing == ProcessingState.loading ||
                  processing == ProcessingState.buffering;

              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // Shuffle
                  _ControlButton(
                    iconWidget: Image.asset(
                      'assets/icons/shuffle.png',
                      color: isShuffle ? spotifyGreen : Colors.white70,
                      height: 24,
                      width: 24,
                    ),
                    enabled: true,
                    isActiveDot: isShuffle,
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
                    size: 55,
                  ),

                  // Play / Pause
                  SizedBox(
                    width: 75,
                    height: 75,
                    child: Center(
                      child:
                          isLoading
                              ? const SizedBox(
                                width: 64,
                                height: 64,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  color: spotifyGreen,
                                ),
                              )
                              : _ControlButton(
                                icon:
                                    playing
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
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
                    ),
                  ),
                  // Next
                  _ControlButton(
                    icon: Icons.skip_next,
                    enabled: audioHandler.hasNext,
                    onTap:
                        audioHandler.hasNext
                            ? () => audioHandler.skipToNext()
                            : null,
                    size: 55,
                  ),

                  // Repeat
                  _ControlButton(
                    iconWidget: Image.asset(
                      'assets/icons/repeat.png',
                      color:
                          repeatMode == RepeatMode.none
                              ? Colors.white70
                              : spotifyGreen,
                      height: 24,
                      width: 24,
                    ),
                    enabled: true,
                    isActiveDot: repeatMode == RepeatMode.one,
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
              padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 5),
              child: Column(
                children: [
                  // Slider
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 5,
                        pressedElevation: 5,
                        elevation: .5,
                      ),
                      overlayShape: SliderComponentShape.noOverlay,
                      trackShape: const CustomTrackShape(
                        activeTrackHeight: 2,
                        inactiveTrackHeight: 2,
                      ),
                      trackHeight: 2,
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
                    padding: const EdgeInsets.symmetric(vertical: 10),
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

  Widget _downloadSong(SongDetail song) {
    return ValueListenableBuilder<DownloadStatus>(
      valueListenable: offlineManager.statusNotifier(song.id),
      builder: (context, status, _) {
        return ValueListenableBuilder<double>(
          valueListenable: offlineManager.progressNotifier(song.id),
          builder: (context, progress, _) {
            Widget iconWidget;
            VoidCallback? onTap;

            if (status == DownloadStatus.completed) {
              iconWidget = Image.asset(
                'assets/icons/complete_download.png',
                width: 32,
                height: 32,
                color: spotifyGreen,
              );
              onTap = () async => await offlineManager.deleteSong(song.id);
            } else if (status == DownloadStatus.downloading) {
              iconWidget = SizedBox(
                width: 32,
                height: 32,
                child: Padding(
                  padding: const EdgeInsets.all(6.0),
                  child: CircularProgressIndicator(
                    value: progress / 100,
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
              onTap = () async {
                offlineManager.updateStatus(
                  song.id,
                  DownloadStatus.downloading,
                );
                offlineManager.updateProgress(song.id, 0.0);
                offlineManager.requestSongDownload(
                  song.id,
                  onProgress: (p) => offlineManager.updateProgress(song.id, p),
                );
              };
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
                        ? "Downloading ${progress.toStringAsFixed(0)}%"
                        : status == DownloadStatus.completed
                        ? "Offline available"
                        : "Download",
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
    final song = ref.watch(currentSongProvider);

    if (song == null) {
      return const SizedBox.shrink();
    }

    final isLiked = ref.watch(likedSongsProvider).contains(song.id);
    double addIconSize = isLiked ? 30 : 35;

    final secondaryParts = <String>[];
    if ((song.albumName ?? song.album).isNotEmpty) {
      secondaryParts.add(song.albumName ?? song.album);
    }
    if (song.contributors.all.isNotEmpty) {
      secondaryParts.add(
        song.contributors.all.map((a) => a.title).toList().toSet().join(', '),
      );
    }

    final handlerAsync = ref.watch(audioHandlerProvider);
    ref.read(audioHandlerProvider.future).then((handler) {
      handler.playbackState.listen((state) {
        final index = handler.currentIndex;
        if (_pageController.hasClients &&
            !handler.isShuffleChanging &&
            index >= 0 &&
            index < handler.queueLength &&
            index != _pageController.page?.round()) {
          _pageController.jumpToPage(index);
        }
      });
    });

    return handlerAsync.when(
      data: (handler) {
        final queueAsync = ref.watch(queueStreamProvider(handler));

        return queueAsync.when(
          data: (queue) {
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    ref.watch(playerColourProvider),
                    Colors.black,
                    Colors.black,
                  ],
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
                            icon: Image.asset(
                              'assets/icons/down_arrow.png',
                              width: 20,
                              height: 20,
                              color: Colors.white,
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
                                    fontSize: 12.5,
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
                            icon: Image.asset(
                              'assets/icons/menu.png',
                              width: 20,
                              height: 20,
                              color: Colors.white,
                            ),
                            onPressed: () {
                              showMediaItemMenu(context, song);
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
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Colors.black],
                                ),
                              ),
                              child: Column(
                                children: [
                                  const SizedBox(height: 25),
                                  SizedBox(
                                    height: 350,
                                    child: PageView.builder(
                                      controller: _pageController,
                                      itemCount: handler.queueLength,
                                      onPageChanged: (index) async {
                                        final audioHandler = await ref.read(
                                          audioHandlerProvider.future,
                                        );

                                        // Only skip if the user actually swiped
                                        if (_pageController.hasClients &&
                                            audioHandler.currentIndex !=
                                                index &&
                                            !audioHandler.isShuffleChanging) {
                                          await audioHandler.skipToQueueItem(
                                            index,
                                          );
                                        }
                                      },
                                      itemBuilder: (context, index) {
                                        final song = handler.queueSongs[index];
                                        return Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            LayoutBuilder(
                                              builder: (context, constraints) {
                                                final screenWidth =
                                                    MediaQuery.of(
                                                      context,
                                                    ).size.width;
                                                double imageWidth =
                                                    screenWidth * 0.80 > 400
                                                        ? 400
                                                        : screenWidth * 0.80;

                                                return CacheNetWorkImg(
                                                  url:
                                                      song.images.isNotEmpty
                                                          ? song.images.last.url
                                                          : '',
                                                  width: imageWidth,
                                                  height: imageWidth,
                                                  fit: BoxFit.contain,
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                );
                                              },
                                            ),
                                            const SizedBox(height: 16),
                                            // Other content goes here
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 25),

                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 15,
                                      vertical: 15,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
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
                                                  '  ${trimAfterParamText(song.title)}',
                                                  fontSize: 22,
                                                  letterSpacing: -1.4,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                if (secondaryParts.isNotEmpty)
                                                  ConstrainedBox(
                                                    constraints:
                                                        const BoxConstraints(
                                                          maxHeight: 30,
                                                        ),
                                                    child: _marqueeText(
                                                      secondaryParts.join(
                                                        " • ",
                                                      ),
                                                      fontSize: 15,
                                                      letterSpacing: -1.4,
                                                      fontWeight:
                                                          FontWeight.w300,
                                                      color: Colors.white70,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        Padding(
                                          padding: EdgeInsets.only(
                                            right: isLiked ? 13 : 10,
                                          ),
                                          child: GestureDetector(
                                            onTap: () {
                                              ref
                                                  .read(
                                                    likedSongsProvider.notifier,
                                                  )
                                                  .toggle(song.id);
                                            },
                                            child: Image.asset(
                                              isLiked
                                                  ? 'assets/icons/tick.png'
                                                  : 'assets/icons/add.png',
                                              width: addIconSize,
                                              height: addIconSize,
                                              color:
                                                  isLiked
                                                      ? spotifyGreen
                                                      : Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  _streamProgressBar(),
                                  _playBackControl(),
                                  const SizedBox(height: 12),

                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 10,
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        // Download Button + Status Indicator
                                        _downloadSong(song),

                                        const Spacer(),
                                        Consumer(
                                          builder: (context, ref, _) {
                                            final sleepState = ref.watch(
                                              sleepTimerProvider,
                                            );
                                            final hasTimer =
                                                sleepState.option !=
                                                SleepTimerOption.off;

                                            return IconButton(
                                              icon: Image.asset(
                                                'assets/icons/timer.png',
                                                width: 20,
                                                height: 20,
                                                color:
                                                    hasTimer
                                                        ? spotifyGreen
                                                        : Colors.white70,
                                              ),
                                              onPressed: () {
                                                showSleepTimerSheet(context);
                                              },
                                            );
                                          },
                                        ),
                                        // queue & share
                                        IconButton(
                                          icon: Image.asset(
                                            'assets/icons/share.png',
                                            height: 22,
                                            width: 22,
                                            color: Colors.white70,
                                          ),
                                          tooltip: "Share",
                                          onPressed: () async {
                                            debugPrint('--> Share pressed');

                                            final box =
                                                context.findRenderObject()
                                                    as RenderBox?;

                                            final details = StringBuffer();
                                            details.writeln(
                                              "Sharing from Hivefy 🎵\n",
                                            );
                                            details.writeln(
                                              "Song: ${song.title}",
                                            );
                                            if (song
                                                .primaryArtists
                                                .isNotEmpty) {
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
                                              details.writeln(
                                                "Year: ${song.year}",
                                              );
                                            }
                                            if (song.url.isNotEmpty) {
                                              details.writeln(
                                                "URL: ${song.url}",
                                              );
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
                                                                    song
                                                                        .images
                                                                        .last
                                                                        .url,
                                                                  ),
                                                                ).load(
                                                                  song
                                                                      .images
                                                                      .last
                                                                      .url,
                                                                )).buffer
                                                                .asUint8List(),
                                                            mimeType:
                                                                'image/jpeg',
                                                            name:
                                                                '${song.title}_hivefy.jpg',
                                                          ),
                                                        ]
                                                        : [],
                                                title: "Sharing from Hivefy 🎵",
                                                sharePositionOrigin:
                                                    box!.localToGlobal(
                                                      Offset.zero,
                                                    ) &
                                                    box.size,
                                              ),
                                            );
                                          },
                                        ),
                                        IconButton(
                                          icon: Image.asset(
                                            'assets/icons/queue.png',
                                            height: 18,
                                            width: 18,
                                            color: Colors.white70,
                                          ),
                                          tooltip: "Queue",
                                          onPressed: () {
                                            openQueueBottomSheet();
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 45),
                                ],
                              ),
                            ),
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
  final IconData? icon;
  final Widget? iconWidget;
  final VoidCallback? onTap;
  final bool enabled;
  final bool isActiveDot;
  final double size;
  final Color background;
  final Color iconColor;

  const _ControlButton({
    this.icon,
    this.iconWidget,
    this.onTap,
    this.enabled = true,
    this.isActiveDot = false,
    this.size = 40,
    this.background = Colors.transparent,
    this.iconColor = Colors.white,
  }) : assert(
         icon != null || iconWidget != null,
         "Either icon or iconWidget must be provided",
       );

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child:
                  iconWidget ??
                  Icon(
                    icon,
                    color: enabled ? iconColor : Colors.white24,
                    size: size * 0.6,
                  ),
            ),
            if (isActiveDot)
              Positioned(
                bottom: 2,
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: spotifyGreen,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
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
  double letterSpacing = 0,
  double height = 1.2,
}) {
  if (text.length <= 30) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
        height: height,
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
      velocity: 20,
      blankSpace: 50,
      fadingEdgeStartFraction: .5,
      fadingEdgeEndFraction: .5,
      startAfter: const Duration(seconds: 1),
      pauseAfterRound: const Duration(seconds: 1),
    ),
  );
}

class CustomTrackShape extends SliderTrackShape {
  final double activeTrackHeight;
  final double inactiveTrackHeight;

  const CustomTrackShape({
    required this.activeTrackHeight,
    required this.inactiveTrackHeight,
  });

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = inactiveTrackHeight;
    final double trackLeft =
        offset.dx +
        sliderTheme.overlayShape!
                .getPreferredSize(isEnabled, isDiscrete)
                .width /
            2;
    final double trackTop =
        offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth =
        parentBox.size.width -
        sliderTheme.overlayShape!.getPreferredSize(isEnabled, isDiscrete).width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
    Offset? secondaryOffset,
  }) {
    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final Paint activePaint =
        Paint()..color = sliderTheme.activeTrackColor ?? Colors.white;
    final Paint inactivePaint =
        Paint()..color = sliderTheme.inactiveTrackColor ?? Colors.grey;

    // Active track
    final Rect leftTrackSegment = Rect.fromLTRB(
      trackRect.left,
      trackRect.top + (trackRect.height - activeTrackHeight) / 2,
      thumbCenter.dx,
      trackRect.bottom - (trackRect.height - activeTrackHeight) / 2,
    );

    // Inactive track
    final Rect rightTrackSegment = Rect.fromLTRB(
      thumbCenter.dx,
      trackRect.top + (trackRect.height - inactiveTrackHeight) / 2,
      trackRect.right,
      trackRect.bottom - (trackRect.height - inactiveTrackHeight) / 2,
    );

    context.canvas.drawRect(leftTrackSegment, activePaint);
    context.canvas.drawRect(rightTrackSegment, inactivePaint);
  }
}
