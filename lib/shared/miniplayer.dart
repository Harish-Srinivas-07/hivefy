import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:marquee/marquee.dart';
import 'package:just_audio/just_audio.dart';
import 'package:readmore/readmore.dart';

import '../models/datamodel.dart';
import '../services/jiosaavn.dart';
import '../utils/format.dart';
import '../utils/theme.dart';
import 'constants.dart';
import 'queue.dart';

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
  }

  Future<void> _updatePlayerCardColour() async {
    final song = ref.read(currentSongProvider);
    if (song?.images.isEmpty ?? true) return;

    final dominant = await getDominantColorFromImage(song!.images.last.url);
    if (dominant == null) return;

    ref.read(playerColourProvider.notifier).state = darken(dominant, 0.25);

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerProvider);
    final song = ref.watch(currentSongProvider);

    if (song == null) return const SizedBox.shrink();
    final isLiked = ref.watch(likedSongsProvider).contains(song.id);

    // Listen for changes in currentSongProvider
    ref.listen<SongDetail?>(currentSongProvider, (_, __) {
      _updatePlayerCardColour();
    });

    return GestureDetector(
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
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 1.0,
                minChildSize: 0.85,
                maxChildSize: 1.0,
                shouldCloseOnMinExtent: true,
                builder: (context, scrollController) {
                  return FullPlayerScreen(scrollController: scrollController);
                },
              ),
            );
          },
        ).then((_) {
          // This runs after the bottom sheet is dismissed
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

                  // Title + Album/Type with marquee
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _marqueeText(
                          song.title,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        // const SizedBox(height: 2),
                        Text(
                          song.contributors.primary.first.title,
                          style: GoogleFonts.gabarito(
                            color: Colors.white.withAlpha(190),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Add button
                  IconButton(
                    onPressed: () {
                      ref.read(likedSongsProvider.notifier).toggle(song.id);
                    },
                    icon: Icon(
                      isLiked ? Icons.check_circle : Icons.add_circle_outline,
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
                        stream: player.playerStateStream,
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
                              playing ? Icons.pause_outlined : Icons.play_arrow,
                              color: Colors.white,
                              size: 28,
                            ),
                            onPressed: () {
                              playing ? player.pause() : player.play();
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
                stream: player.positionStream,
                builder: (context, snapshot) {
                  final pos = snapshot.data ?? Duration.zero;
                  final total = player.duration ?? Duration.zero;
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

    ref.read(playerColourProvider.notifier).state = darken(dominant, 0.25);

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
      setState(() {});
      debugPrint('--> loaded artist details: $_artistDetails');
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return "$m:${s.toString().padLeft(2, '0')}";
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerProvider);
    final song = ref.watch(currentSongProvider);
    final queueManager = ref.watch(queueManagerProvider.notifier);
    final isShuffle = ref.watch(shuffleProvider);
    final repeatMode = ref.watch(repeatModeProvider);

    // update colour at song change
    ref.listen<SongDetail?>(currentSongProvider, (_, __) {
      _updateBgColor();
      _fetchArtistDetails();
    });

    if (song == null) {
      //  { Future.microtask(() => Navigator.of(context).maybePop());}
      return const SizedBox.shrink();
    }
    final isLiked = ref.watch(likedSongsProvider).contains(song.id);

    // Compose secondary info line
    final secondaryParts = <String>[];
    if ((song.albumName ?? song.album).isNotEmpty) {
      secondaryParts.add(song.albumName ?? song.album);
    }
    if (song.primaryArtists.isNotEmpty) secondaryParts.add(song.primaryArtists);

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
            const SizedBox(height: 60),
            // Top bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Text(
                  "Now Playing",
                  style: GoogleFonts.figtree(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),

            // Scrollable content
            Expanded(
              child: SingleChildScrollView(
                controller: widget.scrollController,
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    // Artwork (full width, no height restriction)
                    SizedBox(
                      width: MediaQuery.of(context).size.width * 0.80,
                      // height: 300,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          song.images.isNotEmpty ? song.images.last.url : "",
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 35),

                    // Title & metadata
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _marqueeText(
                                    trimAfterParamText(song.title),
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  if (secondaryParts.isNotEmpty)
                                    _marqueeText(
                                      secondaryParts.join(" • "),
                                      fontSize: 14,
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
                              color: isLiked ? Colors.red : Colors.white,
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

                    // Progress slider
                    StreamBuilder<Duration>(
                      stream: player.positionStream,
                      builder: (context, snapshot) {
                        final pos = snapshot.data ?? Duration.zero;
                        final total = player.duration ?? Duration.zero;
                        final progress =
                            total.inMilliseconds > 0
                                ? pos.inMilliseconds / total.inMilliseconds
                                : 0.0;

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 5,
                          ),
                          child: Column(
                            children: [
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
                                          : (v) {
                                            player.seek(
                                              Duration(
                                                milliseconds:
                                                    (v * total.inMilliseconds)
                                                        .toInt(),
                                              ),
                                            );
                                          },
                                  activeColor: Colors.white,
                                  inactiveColor: ref
                                      .watch(playerColourProvider)
                                      .withAlpha(100),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 10,
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _fmt(pos),
                                      style: GoogleFonts.figtree(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      _fmt(total),
                                      style: GoogleFonts.figtree(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 15),

                    // Playback controls
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12.0,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          //  Shuffle button
                          _ControlButton(
                            icon: Icons.shuffle,
                            enabled: true,
                            iconColor:
                                isShuffle ? Colors.greenAccent : Colors.white70,
                            onTap: () {
                              queueManager.toggleShuffle();
                            },
                          ),

                          // ⏮ Previous
                          _ControlButton(
                            icon: Icons.skip_previous,
                            enabled: queueManager.hasPrevious,
                            onTap:
                                queueManager.hasPrevious
                                    ? () => queueManager.playPrevious()
                                    : null,
                            size: 45,
                          ),

                          // ▶️ / ⏸ Play/Pause
                          StreamBuilder<PlayerState>(
                            stream: player.playerStateStream,
                            builder: (context, snapshot) {
                              final st = snapshot.data;
                              final playing = st?.playing ?? false;
                              return _ControlButton(
                                icon: playing ? Icons.pause : Icons.play_arrow,
                                enabled: true,
                                onTap:
                                    () =>
                                        playing
                                            ? player.pause()
                                            : player.play(),
                                size: 64,
                                background: Colors.white,
                                iconColor: Colors.black,
                              );
                            },
                          ),

                          // ⏭ Next
                          _ControlButton(
                            icon: Icons.skip_next,
                            enabled: queueManager.hasNext,
                            onTap:
                                queueManager.hasNext
                                    ? () => queueManager.playNext()
                                    : null,
                            size: 45,
                          ),

                          // 🔁 Repeat button
                          _ControlButton(
                            icon:
                                repeatMode == RepeatMode.one
                                    ? Icons.repeat_one
                                    : Icons.repeat,
                            enabled: true,
                            iconColor:
                                repeatMode == RepeatMode.none
                                    ? Colors.white70
                                    : Colors.greenAccent,
                            onTap: () {
                              queueManager.toggleRepeatMode();
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    if (_artistDetails != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
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
                                        bottom: 0,
                                        left: 16,
                                        right: 16,
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.center,
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _artistDetails!.title,
                                                style: GoogleFonts.figtree(
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
                                            if (_artistDetails!.isVerified ==
                                                true)
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
                                          style: GoogleFonts.figtree(
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
                                      if (_artistDetails!
                                          .dominantLanguage
                                          .isNotEmpty)
                                        "Language: ${_artistDetails!.dominantLanguage}",
                                    ].join(" • "),
                                    style: GoogleFonts.figtree(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 12),

                                if (_artistDetails!.bio.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    child: GestureDetector(
                                      onTap: () {
                                        _isBioExpanded.value =
                                            !_isBioExpanded.value;
                                      },
                                      child: ReadMoreText(
                                        _artistDetails!.bio
                                            .map((bio) => sanitizeBio(bio))
                                            .join("\n\n"),
                                        trimLines: 3,
                                        trimMode: TrimMode.Line,
                                        colorClickableText: Colors.greenAccent,
                                        trimCollapsedText: " ...more",
                                        trimExpandedText: " Show less",
                                        style: GoogleFonts.figtree(
                                          color: Colors.white70,
                                          fontSize: 14,
                                        ),
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
                                        isExpandable:
                                            false, // We will handle expand ourselves
                                        isCollapsed:
                                            _isBioExpanded, // toggle expand
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
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
      style: GoogleFonts.gabarito(
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  return SizedBox(
    height: fontSize + 4,
    child: Marquee(
      text: text,
      style: GoogleFonts.gabarito(
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
