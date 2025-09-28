import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconly/iconly.dart';
import 'package:marquee/marquee.dart';
import 'package:just_audio/just_audio.dart';

import '../models/database.dart';
import '../models/datamodel.dart';
import '../services/jiosaavn.dart';
import '../utils/theme.dart';
import 'constants.dart';
import 'queue.dart';

Color playerColour = Colors.black.withAlpha(205);

class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  @override
  void didUpdateWidget(covariant MiniPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateDominantColor();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateDominantColor();
  }

  Future<void> _updateDominantColor() async {
    final song = ref.read(currentSongProvider);
    if (song == null || song.images.isEmpty) return;

    final dominant = await getDominantColorFromImage(song.images.last.url);
    if (mounted && dominant != null) {
      final mixedColor = Color.lerp(dominant, Colors.black, 0.6) ?? dominant;
      playerColour = mixedColor.withAlpha(250);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = ref.watch(playerProvider);
    final song = ref.watch(currentSongProvider);
    ref.listen<QueueState>(queueProvider, (prev, next) {
      if (next.current != prev?.current) {
        ref.read(currentSongProvider.notifier).state = next.current;
      }
    });

    if (song == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          PageRouteBuilder(
            opaque: false,
            pageBuilder: (_, __, ___) => const FullPlayerScreen(),
            transitionsBuilder:
                (context, animation, secondaryAnimation, child) {
                  final tween = Tween(
                    begin: const Offset(0, 1),
                    end: Offset.zero,
                  ).chain(CurveTween(curve: Curves.easeInOut));
                  return SlideTransition(
                    position: animation.drive(tween),
                    child: child,
                  );
                },
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: ShapeDecoration(
          color: playerColour,
          shape: SmoothRectangleBorder(
            borderRadius: SmoothBorderRadius(
              cornerRadius: 12,
              cornerSmoothing: 0.8,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  // Artwork
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      song.images.isNotEmpty ? song.images.last.url : "",
                      height: 50,
                      width: 50,
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
                        const SizedBox(height: 2),
                        Text(
                          song.albumName ?? song.type,
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
                      // TODO: Add song to playlist or favorites
                    },
                    icon: const Icon(
                      Icons.add_circle_outline,
                      color: Colors.white,
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
                              playing
                                  ? Icons.pause_circle_filled
                                  : IconlyBold.play,
                              color: Colors.white,
                              size: 36,
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
                  final progress = total.inMilliseconds > 0
                      ? pos.inMilliseconds / total.inMilliseconds
                      : 0.0;

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.white.withAlpha(51),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.greenAccent,
                      ),
                      minHeight: 4,
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
  const FullPlayerScreen({super.key});

  @override
  ConsumerState<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

class _FullPlayerScreenState extends ConsumerState<FullPlayerScreen> {
  ArtistDetails? _artistDetails;

  @override
  void didUpdateWidget(covariant FullPlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateBgColor();
    _fetchArtistDetails();
  }

  @override
  void initState() {
    super.initState();
    _updateBgColor();
    _fetchArtistDetails();
  }

  Future<void> _updateBgColor() async {
    final song = ref.read(currentSongProvider);
    if (song == null) return;

    final dominant = await getDominantColorFromImage(
      song.images.isNotEmpty ? song.images.last.url : "",
    );

    if (dominant != null) {
      final mixedColor = Color.lerp(dominant, Colors.black, 0.6) ?? dominant;
      playerColour = mixedColor.withAlpha((0.85 * 255).toInt());
      setState(() {});
    }
  }

  Future<void> _fetchArtistDetails() async {
    final song = ref.read(currentSongProvider);
    if (song == null) return;

    final artistId = song.contributors.primary.first.id;
    if (artistId.isEmpty) return;

    final cache = ArtistCache();

    // Try to get from cache first
    final cached = cache.get(artistId);
    if (cached != null) {
      _artistDetails = cached;
      setState(() {});
      debugPrint('--> loaded artist details from cache: $_artistDetails');
      return;
    }

    // Fetch from API if not cached
    final api = SaavnAPI();
    final details = await api.fetchArtistDetailsById(artistId: artistId);

    if (mounted && details != null) {
      _artistDetails = details;

      // Save to cache
      cache.set(artistId, details);

      setState(() {});
      debugPrint('--> fetched artist details from API: $_artistDetails');
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

    debugPrint('--> here the song details $song');

    if (song == null) {
      //  { Future.microtask(() => Navigator.of(context).maybePop());}
      return const SizedBox.shrink();
    }

    // Compose secondary info line
    final secondaryParts = <String>[];
    if ((song.albumName ?? song.album).isNotEmpty) {
      secondaryParts.add(song.albumName ?? song.album);
    }
    if (song.primaryArtists.isNotEmpty) secondaryParts.add(song.primaryArtists);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [playerColour.withAlpha(205), Colors.black, Colors.black],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
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
                  physics: const BouncingScrollPhysics(),
                  child: Column(
                    children: [
                      const SizedBox(height: 24),
                      // Artwork (full width, no height restriction)
                      Hero(
                        tag: 'artwork_${song.id}',
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(20),
                          child: Image.network(
                            song.images.isNotEmpty ? song.images.last.url : "",
                            width: MediaQuery.of(context).size.width * 0.85,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Title & metadata
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 30,
                          vertical: 15,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _marqueeText(
                                    song.title,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  if (secondaryParts.isNotEmpty)
                                    _marqueeText(
                                      secondaryParts.join(" • "),
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      color: Colors.white70,
                                    ),
                                ],
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 8.0),
                              child: IconButton(
                                icon: const Icon(Icons.favorite_border),
                                color: Colors.white,
                                tooltip: "Add to liked songs",
                                onPressed: () {},
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
                          final progress = total.inMilliseconds > 0
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
                                    overlayShape:
                                        SliderComponentShape.noOverlay,
                                    trackHeight: 2.5,
                                  ),
                                  child: Slider(
                                    value: progress.clamp(0.0, 1.0),
                                    onChanged: total == Duration.zero
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
                                    inactiveColor: Colors.grey[900],
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
                            _ControlButton(
                              icon: Icons.shuffle,
                              enabled: true,
                              onTap: () {},
                            ),
                            _ControlButton(
                              icon: Icons.skip_previous,
                              enabled: player.hasPrevious,
                              onTap: player.hasPrevious
                                  ? player.seekToPrevious
                                  : null,
                              size: 42,
                            ),
                            StreamBuilder<PlayerState>(
                              stream: player.playerStateStream,
                              builder: (context, snapshot) {
                                final st = snapshot.data;
                                final playing = st?.playing ?? false;
                                return _ControlButton(
                                  icon: playing
                                      ? Icons.pause
                                      : Icons.play_arrow,
                                  enabled: true,
                                  onTap: () =>
                                      playing ? player.pause() : player.play(),
                                  size: 64,
                                  background: Colors.white,
                                  iconColor: Colors.black,
                                );
                              },
                            ),
                            _ControlButton(
                              icon: Icons.skip_next,
                              enabled: player.hasNext,
                              onTap: player.hasNext ? player.seekToNext : null,
                              size: 42,
                            ),
                            _ControlButton(
                              icon: Icons.repeat,
                              enabled: true,
                              onTap: () {},
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Artist details
                      if (_artistDetails != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16.0,
                            vertical: 12,
                          ),
                          child: Container(
                            width: double.infinity,
                            constraints: BoxConstraints(maxHeight: 300),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              image: _artistDetails!.images.isNotEmpty
                                  ? DecorationImage(
                                      image: NetworkImage(
                                        _artistDetails!.images.last.url,
                                      ),
                                      fit: BoxFit.cover,
                                      colorFilter: ColorFilter.mode(
                                        Colors.black.withAlpha(125),
                                        BlendMode.darken,
                                      ),
                                    )
                                  : null,
                              color: Colors.grey[900],
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "About the Artist",
                                    style: GoogleFonts.figtree(
                                      color: Colors.white70,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Spacer(),
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _artistDetails!.title,
                                          style: GoogleFonts.figtree(
                                            color: Colors.white,
                                            fontSize: 20,
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
                                  const SizedBox(height: 6),
                                  Text(
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
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                  if (_artistDetails!.bio.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      _artistDetails!.bio.join("\n"),
                                      style: GoogleFonts.figtree(
                                        color: Colors.white70,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
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
  if (text.length <= 25) {
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
      startAfter: const Duration(seconds: 1),
      pauseAfterRound: const Duration(seconds: 1),
      numberOfRounds: 1,
    ),
  );
}
