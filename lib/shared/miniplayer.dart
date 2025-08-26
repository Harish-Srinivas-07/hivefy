import 'package:figma_squircle/figma_squircle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconly/iconly.dart';
import 'package:just_audio/just_audio.dart';

import '../utils/theme.dart';
import 'constants.dart';
import 'queue.dart';

Color playerColour = Colors.black.withOpacity(0.85);

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

    final color = await getDominantColorFromImage(song.images.last.url);
    if (mounted && color != null) {
      setState(() {
        playerColour = color.withOpacity(.5);
      });
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
        // margin: const EdgeInsets.only(left:8 , right: 8),
        decoration: ShapeDecoration(
          color: playerColour,
          shape: SmoothRectangleBorder(
            borderRadius: SmoothBorderRadius(
              cornerRadius: 18,
              cornerSmoothing: 0.8,
            ),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Row: artwork + title + play/pause
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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

                  // Title + Album / Type
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          song.title ,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          song.albumName ?? song.type,
                          style: GoogleFonts.poppins(
                            color: Colors.white.withOpacity(0.7),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),

                  // Play / Pause
                  StreamBuilder<PlayerState>(
                    stream: player.playerStateStream,
                    builder: (context, snapshot) {
                      final state = snapshot.data;
                      final playing = state?.playing ?? false;

                      if (state?.processingState == ProcessingState.loading ||
                          state?.processingState == ProcessingState.buffering) {
                        return const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.greenAccent),
                        );
                      }

                      return IconButton(
                        icon: Icon(
                          playing ? Icons.pause_circle_filled : IconlyBold.play,
                          color: Colors.white,
                          size: 36,
                        ),
                        onPressed: () {
                          playing ? player.pause() : player.play();
                        },
                      );
                    },
                  ),
                ],
              ),
            ),

            // Progress bar inside with padding
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 12),
              child: StreamBuilder<Duration>(
                stream: player.positionStream,
                builder: (context, snapshot) {
                  final pos = snapshot.data ?? Duration.zero;
                  final total = player.duration ?? Duration.zero;
                  double progress = 0;
                  if (total.inMilliseconds > 0) {
                    progress = pos.inMilliseconds / total.inMilliseconds;
                  }

                  return ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: Colors.white.withOpacity(0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.greenAccent,
                      ),
                      minHeight: 3,
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
    @override
  void didUpdateWidget(covariant FullPlayerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateBgColor();
  }

  @override
  void initState() {
    super.initState();
    _updateBgColor();
  }

  Future<void> _updateBgColor() async {
    final song = ref.read(currentSongProvider);
    if (song == null) return;

    final dominant = await getDominantColorFromImage(
      song.images.isNotEmpty ? song.images.last.url : "",
    );

    if (dominant != null && mounted) {
      setState(() {
        playerColour = dominant;
      });
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

    if (song == null) {
      Future.microtask(() => Navigator.of(context).maybePop());
      return const SizedBox.shrink();
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Container(
         decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [playerColour.withOpacity(0.8), Colors.black],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // top bar
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
                    style: GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
                  ),
                  const SizedBox(width: 48), // spacer
                ],
              ),
          
              // artwork
              Expanded(
                child: Center(
                  child: Hero(
                    tag: 'artwork_${song.id}',
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.network(
                        song.images.isNotEmpty ? song.images.last.url : "",
                        width: MediaQuery.of(context).size.width * 0.85,
                        height: MediaQuery.of(context).size.width * 0.85,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
              ),
          
              // title & artist
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                child: Column(
                  children: [
                    Text(
                      song.title,
                      style:  GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      song.albumName ?? song.type,
                      style:  GoogleFonts.poppins(color: Colors.white70, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
          
              // progress slider
              StreamBuilder<Duration>(
                stream: player.positionStream,
                builder: (context, snapshot) {
                  final pos = snapshot.data ?? Duration.zero;
                  final total = player.duration ?? Duration.zero;
                  final progress = total.inMilliseconds > 0
                      ? pos.inMilliseconds / total.inMilliseconds
                      : 0.0;
          
                  return Column(
                    children: [
                      Slider(
                        value: progress.clamp(0.0, 1.0),
                        onChanged: total == Duration.zero
                            ? null
                            : (v) {
                                player.seek(
                                  Duration(
                                    milliseconds: (v * total.inMilliseconds)
                                        .toInt(),
                                  ),
                                );
                              },
                        activeColor: Colors.white,
                        inactiveColor: Colors.white24,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _fmt(pos),
                              style:  GoogleFonts.poppins(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              _fmt(total),
                              style:  GoogleFonts.poppins(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
          
              const SizedBox(height: 20),
          
              // playback controls
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  IconButton(
                    icon: const Icon(Icons.shuffle, color: Colors.white70),
                    onPressed: () {},
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous, color: Colors.white),
                    iconSize: 40,
                    onPressed: player.hasPrevious ? player.seekToPrevious : null,
                  ),
                  StreamBuilder<PlayerState>(
                    stream: player.playerStateStream,
                    builder: (context, snapshot) {
                      final st = snapshot.data;
                      final playing = st?.playing ?? false;
          
                      return IconButton(
                        icon: Icon(
                          playing ? Icons.pause_circle : Icons.play_circle,
                          color: Colors.white,
                        ),
                        iconSize: 80,
                        onPressed: () => playing ? player.pause() : player.play(),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next, color: Colors.white),
                    iconSize: 40,
                    onPressed: player.hasNext ? player.seekToNext : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.repeat, color: Colors.white70),
                    onPressed: () {},
                  ),
                ],
              ),
          
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}
