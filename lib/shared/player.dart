import 'dart:ui' show FontFeature, ImageFilter;
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:marquee/marquee.dart';
import 'package:just_audio/just_audio.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../components/shimmers.dart';
import '../components/empty_state.dart';
import '../components/playback_artwork.dart';
import '../components/liquid_glass.dart';
import '../components/player_sheet.dart';
import '../components/player_glass_background.dart';
import '../components/lyrics_lines.dart';
import '../components/lyrics_offset.dart';
import '../components/lyrics_provider_sheet.dart';
import '../components/sheet_surface.dart';
import '../components/song_credits.dart';
import '../components/showmenu.dart';
import '../models/datamodel.dart';
import '../services/offlinemanager.dart';
import '../screens/features/queuesheet.dart';
import '../services/audiohandler.dart';
import '../services/youtube.dart';
import '../services/lyrics.dart';
import '../services/song_artist_resolver.dart';
import '../utils/format.dart';
import '../utils/artwork.dart';
import '../utils/song_metadata.dart';
import '../utils/theme.dart';
import 'package:audio_session/audio_session.dart';
import 'package:hivefy/utils/logger.dart';
import 'constants.dart';

final playerColourProvider = StateProvider<Color>((ref) => Colors.black);

final connectedBluetoothDeviceProvider = StreamProvider<String?>((ref) async* {
  final session = await AudioSession.instance;

  while (true) {
    try {
      final devices = await session.getDevices();
      String? bluetoothDevice;
      for (var device in devices) {
        // ignore: experimental_member_use
        if (device.type == AudioDeviceType.bluetoothA2dp ||
            // ignore: experimental_member_use
            device.type == AudioDeviceType.bluetoothSco ||
            // ignore: experimental_member_use
            device.type == AudioDeviceType.bluetoothLe) {
          bluetoothDevice = (device.name.isNotEmpty) ? device.name : "Bluetooth";
          break;
        }
      }
      yield bluetoothDevice;
    } catch (e) {
      yield null;
    }
    await Future.delayed(const Duration(seconds: 5));
  }
});

class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  final GlobalKey _artworkKey = GlobalKey();
  final GlobalKey _barKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    playerSheet.miniArtworkKey = _artworkKey;
    playerSheet.miniBarKey = _barKey;
    _updatePlayerCardColour();
  }

  @override
  void dispose() {
    if (identical(playerSheet.miniArtworkKey, _artworkKey)) playerSheet.miniArtworkKey = null;
    if (identical(playerSheet.miniBarKey, _barKey)) playerSheet.miniBarKey = null;
    super.dispose();
  }

  Future<void> _updatePlayerCardColour() async {
    final song = ref.read(currentSongProvider);
    if (song?.images.isEmpty ?? true) return;

    final dominant = await getDominantColorFromImage(song!.images.last.url);

    if (!mounted || ref.read(currentSongProvider)?.id != song.id) return;

    ref.read(playerColourProvider.notifier).state = getDominantDarker(dominant);
  }

  @override
  Widget build(BuildContext context) {
    final audioHandlerAsync = ref.watch(audioHandlerProvider);
    final song = ref.watch(currentSongProvider);

    if (song == null) return const SizedBox.shrink();

    // Listen for changes in currentSongProvider to update color
    ref.listen<SongDetail?>(currentSongProvider, (previous, next) {
      if (next != null && next != previous) {
        _updatePlayerCardColour();
      }
    });

    return audioHandlerAsync.when(
      data: (audioHandler) => PlayerSheetHandle(
        child: Container(
          key: _barKey,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: LiquidGlass(
            child: ValueListenableBuilder<double>(
              valueListenable: playerSheet.progress,
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 14, 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // Artwork
                          PlayerArtworkHero(
                            key: _artworkKey,
                            child: CacheNetWorkImg(
                              key: ValueKey(song.id),
                              url: song.images.isNotEmpty ? miniPlayerArtworkUrl(song.images.last.url) : '',
                              fallbackUrl: song.images.isNotEmpty ? song.images.last.url : null,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              borderRadius: BorderRadius.circular(10),
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Title + Artist
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _marqueeText(
                                  trimAfterParamText(song.title),
                                  fontSize: 14,
                                  letterSpacing: -.5,
                                  fontWeight: FontWeight.w600,
                                ),
                                const SizedBox(height: 2),
                                _marqueeText(playerSongSubtitle(song), fontSize: 14, fontWeight: FontWeight.w400),
                              ],
                            ),
                          ),

                          // Play / Pause / Loading button
                          SizedBox(
                            width: 38,
                            height: 38,
                            child: Center(
                              child: StreamBuilder<PlayerState>(
                                stream: audioHandler.playerStateStream,
                                builder: (context, snapshot) {
                                  final state = snapshot.data;
                                  final playing = state?.playing ?? false;

                                  if (state?.processingState == ProcessingState.loading ||
                                      state?.processingState == ProcessingState.buffering) {
                                    return const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: spotifyGreen),
                                    );
                                  }

                                  return IconButton(
                                    padding: EdgeInsets.zero,
                                    icon: Icon(
                                      playing ? Icons.pause_outlined : Icons.play_arrow,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                    onPressed: () {
                                      playing ? audioHandler.pause() : audioHandler.play();
                                    },
                                  );
                                },
                              ),
                            ),
                          ),

                          const SizedBox(width: 4),

                          // Skip to the next queued song
                          SizedBox(
                            width: 30,
                            height: 38,
                            child: StreamBuilder<List<MediaItem>>(
                              stream: audioHandler.queue,
                              builder: (context, _) {
                                final hasNext = audioHandler.hasNext;
                                return IconButton(
                                  padding: EdgeInsets.zero,
                                  tooltip: 'Next',
                                  icon: Icon(
                                    CupertinoIcons.forward_fill,
                                    color: hasNext ? Colors.white : Colors.white38,
                                    size: 22,
                                  ),
                                  onPressed: hasNext ? audioHandler.skipToNext : null,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              builder: (context, progress, child) => Opacity(opacity: (1 - progress * 6).clamp(0.0, 1.0), child: child),
            ),
          ),
        ),
      ),
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// The artwork that flies from the mini player to the full player (see PlayerSheetLayer).
class PlayerFlightArtwork extends ConsumerWidget {
  const PlayerFlightArtwork({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSong = ref.watch(currentSongProvider);
    if (currentSong == null) return const SizedBox.shrink();
    final fallbackUrl = currentSong.images.isNotEmpty ? currentSong.images.last.url : null;
    return CacheNetWorkImg(
      key: ValueKey(currentSong.id),
      url: fallbackUrl == null ? '' : fullPlayerArtworkUrl(fallbackUrl),
      fallbackUrl: fallbackUrl,
      fit: BoxFit.cover,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
    );
  }
}

void showOutputSwitcher(BuildContext context, WidgetRef ref) {
  final bluetoothDevice = ref.read(connectedBluetoothDeviceProvider).asData?.value;

  showModalBottomSheet(
    context: context,
    useRootNavigator: true,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: Stack(
          children: [
            const Positioned.fill(child: SheetSurface(child: SizedBox.expand())),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: SizedBox(
                        width: 38,
                        height: 4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.white30,
                            borderRadius: BorderRadius.all(Radius.circular(2)),
                          ),
                        ),
                      ),
                    ),

                    const Text(
                      "Audio Output",
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                    ),

                    const SizedBox(height: 16),

                    // Volume Slider
                    Consumer(
                      builder: (context, ref, _) {
                        final handlerAsync = ref.watch(audioHandlerProvider);
                        return handlerAsync.when(
                          data: (handler) => StreamBuilder<double>(
                            stream: handler.volumeStream,
                            initialData: handler.volume,
                            builder: (context, snapshot) {
                              final volume = snapshot.data ?? 1.0;
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                                child: Row(
                                  children: [
                                    const Icon(Icons.volume_down_rounded, color: Colors.white54, size: 20),
                                    Expanded(
                                      child: SliderTheme(
                                        data: SliderTheme.of(context).copyWith(
                                          trackHeight: 2,
                                          thumbShape: const RoundSliderThumbShape(
                                            enabledThumbRadius: 8,
                                            pressedElevation: 8,
                                          ),
                                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 6),
                                        ),
                                        child: Slider(
                                          value: volume,
                                          onChanged: (v) => handler.setVolume(v),
                                          activeColor: spotifyGreen,
                                          inactiveColor: Colors.white10,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Icon(Icons.volume_up_rounded, color: Colors.white54, size: 20),
                                  ],
                                ),
                              );
                            },
                          ),
                          loading: () => const SizedBox.shrink(),
                          error: (_, _) => const SizedBox.shrink(),
                        );
                      },
                    ),

                    const SizedBox(height: 8),
                    const Divider(color: Colors.white12, height: 1),

                    Material(
                      color: Colors.transparent,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
                        child: Column(
                          children: [
                            // This Phone
                            ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                              leading: Icon(
                                Icons.phone_android_rounded,
                                color: bluetoothDevice == null ? spotifyGreen : Colors.white38,
                                size: 24,
                              ),
                              title: const Text(
                                "This Phone",
                                style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.w400),
                              ),
                              trailing: bluetoothDevice == null
                                  ? const Icon(Icons.check, color: spotifyGreen, size: 24)
                                  : null,
                              onTap: () async {
                                final session = await AudioSession.instance;
                                // Force to phone speaker
                                await session.configure(
                                  AudioSessionConfiguration(
                                    avAudioSessionCategory: AVAudioSessionCategory.playAndRecord,
                                    avAudioSessionCategoryOptions:
                                        AVAudioSessionCategoryOptions.allowBluetooth |
                                        AVAudioSessionCategoryOptions.defaultToSpeaker,
                                    avAudioSessionMode: AVAudioSessionMode.defaultMode,
                                    androidAudioAttributes: const AndroidAudioAttributes(
                                      contentType: AndroidAudioContentType.music,
                                      usage: AndroidAudioUsage.media,
                                    ),
                                    androidWillPauseWhenDucked: false,
                                  ),
                                );
                                if (context.mounted) Navigator.pop(context);
                              },
                            ),

                            const SizedBox(height: 12),

                            // Bluetooth Device
                            if (bluetoothDevice != null)
                              ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                                leading: const Icon(Icons.bluetooth_audio_rounded, color: spotifyGreen, size: 24),
                                title: Text(
                                  bluetoothDevice,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    color: spotifyGreen,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                trailing: const Icon(Icons.check, color: spotifyGreen, size: 24),
                                onTap: () async {
                                  final session = await AudioSession.instance;
                                  // Reset to default (let OS decide routing)
                                  await session.configure(const AudioSessionConfiguration.music());
                                  if (context.mounted) Navigator.pop(context);
                                },
                              )
                            else
                              ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                                leading: const Icon(Icons.bluetooth_disabled_rounded, color: Colors.white12, size: 24),
                                title: const Text(
                                  "Bluetooth not connected",
                                  style: TextStyle(fontSize: 16, color: Colors.white12, fontWeight: FontWeight.w400),
                                ),
                                onTap: null,
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

class FullPlayerScreen extends ConsumerStatefulWidget {
  final ScrollController? scrollController;
  final bool preview;
  const FullPlayerScreen({super.key, this.scrollController, this.preview = false});

  @override
  ConsumerState<FullPlayerScreen> createState() => _FullPlayerScreenState();
}

enum PlayerView { player, lyrics, queue }

class _PlayerSheetScrollPhysics extends ScrollPhysics {
  const _PlayerSheetScrollPhysics({required this.isSheetDragging, super.parent});

  final bool Function() isSheetDragging;

  @override
  _PlayerSheetScrollPhysics applyTo(ScrollPhysics? ancestor) =>
      _PlayerSheetScrollPhysics(isSheetDragging: isSheetDragging, parent: buildParent(ancestor));

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    if (isSheetDragging()) return value - position.pixels;
    return super.applyBoundaryConditions(position, value);
  }
}

class _FullPlayerScreenState extends ConsumerState<FullPlayerScreen> {
  ArtistDetails? _artistDetails;
  int _artistRequestGeneration = 0;
  final ValueNotifier<bool> _isBioExpanded = ValueNotifier(false);
  late final PageController _pageController;
  final ScrollController _queueController = ScrollController();
  final GlobalKey _artworkPositionKey = GlobalKey();
  PlayerView _view = PlayerView.player;
  bool _artworkDragging = false;
  bool _artworkSyncing = false;
  int? _pendingArtworkIndex;
  int _artworkRequestGeneration = 0;
  double _closeDragDistance = 0;
  bool _closeDragAllowed = true;
  bool _mainCloseDragActive = false;
  double _lyricsScrollOffset = 0;
  bool _lyricsPointerDown = false;
  bool _lyricsControlsHidden = false;
  bool _queueControlsHidden = false;
  double _queueScrollDistance = 0;
  StreamSubscription<PlaybackState>? _playbackSubscription;
  Timer? _artistFetchTimer;
  bool _initialArtistRequested = false;

  @override
  void initState() {
    super.initState();
    final index = ref.read(audioHandlerProvider).asData?.value.currentIndex ?? 0;
    _pageController = PageController(initialPage: index < 0 ? 0 : index, viewportFraction: 1.0);
    ref.read(audioHandlerProvider.future).then((handler) {
      if (!mounted) return;
      _playbackSubscription = handler.playbackState.listen((state) {
        _syncArtworkPage(handler);
      });
    });
    if (!widget.preview) {
      playerSheet.fullArtworkKey = _artworkPositionKey;
      playerSheet.progress.addListener(_scheduleInitialArtistFetch);
      _scheduleInitialArtistFetch();
    }
  }

  void _scheduleInitialArtistFetch() {
    if (_initialArtistRequested) return;
    if (playerSheet.engaged.value && playerSheet.progress.value < 1) {
      _artistFetchTimer?.cancel();
      _artistFetchTimer = null;
      return;
    }
    _artistFetchTimer ??= Timer(const Duration(milliseconds: 300), () {
      _initialArtistRequested = true;
      if (mounted) _fetchArtistDetails();
    });
  }

  @override
  void dispose() {
    if (identical(playerSheet.fullArtworkKey, _artworkPositionKey)) playerSheet.fullArtworkKey = null;
    playerSheet.progress.removeListener(_scheduleInitialArtistFetch);
    _artistFetchTimer?.cancel();
    _playbackSubscription?.cancel();
    _pageController.dispose();
    _queueController.dispose();
    _isBioExpanded.dispose();
    super.dispose();
  }

  Future<void> _updateBgColor() async {
    final song = ref.read(currentSongProvider);
    if (song?.images.isEmpty ?? true) return;

    final dominant = await getDominantColorFromImage(song!.images.last.url);
    if (!mounted || ref.read(currentSongProvider)?.id != song.id) return;
    ref.read(playerColourProvider.notifier).state = getDominantDarker(dominant);
  }

  Future<void> _fetchArtistDetails() async {
    final generation = ++_artistRequestGeneration;
    final song = ref.read(currentSongProvider);
    if (mounted) setState(() => _artistDetails = null);
    if (song == null) return;

    final api = YoutubeAPI();
    ArtistDetails? details;
    try {
      details = await resolveSongArtist(song, api);
    } catch (error) {
      Logger.error('Player', 'Unable to load artist details: $error');
      return;
    }

    if (mounted &&
        generation == _artistRequestGeneration &&
        ref.read(currentSongProvider)?.id == song.id &&
        details != null) {
      _artistDetails = details;
      _isBioExpanded.value = false;
      if (mounted) setState(() {});
    }
  }

  void _setPlayerView(PlayerView view) {
    if (widget.preview) return;
    HapticFeedback.selectionClick();
    setState(() {
      _view = _view == view ? PlayerView.player : view;
      _lyricsControlsHidden = false;
      _lyricsPointerDown = false;
      _queueControlsHidden = false;
      _queueScrollDistance = 0;
    });
  }

  bool _onQueueScroll(ScrollNotification notification) {
    if (_view != PlayerView.queue || notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollStartNotification && notification.dragDetails != null) {
      _queueScrollDistance = 0;
    } else if (notification is ScrollUpdateNotification && notification.dragDetails != null) {
      final delta = notification.scrollDelta ?? 0;
      if (delta == 0) return false;
      if (_queueScrollDistance.sign != delta.sign) _queueScrollDistance = 0;
      _queueScrollDistance += delta;
      if ((!_queueControlsHidden && _queueScrollDistance >= 16) ||
          (_queueControlsHidden && _queueScrollDistance <= -6)) {
        setState(() => _queueControlsHidden = !_queueControlsHidden);
        _queueScrollDistance = 0;
      }
    } else if (notification is OverscrollNotification &&
        notification.dragDetails != null &&
        notification.overscroll < 0 &&
        _queueControlsHidden) {
      setState(() => _queueControlsHidden = false);
      _queueScrollDistance = 0;
    }
    return false;
  }

  // whole-screen drag: only when the lists are at the top
  void _startCloseDrag(DragStartDetails _) {
    playerSheet.prepareClose();
    _closeDragDistance = 0;
    _closeDragAllowed =
        (_view != PlayerView.queue || !_queueController.hasClients || _queueController.offset <= 0) &&
        (_view != PlayerView.lyrics || _lyricsScrollOffset <= 0);
  }

  // pill drag: always allowed, independent of list scroll state
  void _startPillDrag(DragStartDetails _) {
    playerSheet.prepareClose();
    _closeDragDistance = 0;
    _closeDragAllowed = true;
  }

  void _updateCloseDrag(DragUpdateDetails details) {
    if (!_closeDragAllowed) return;
    _closeDragDistance = (_closeDragDistance + (details.primaryDelta ?? 0)).clamp(0, double.infinity);
    playerSheet.dragTo(1 - _closeDragDistance / playerSheet.travel);
  }

  void _settleCloseDrag(DragEndDetails details) {
    if (!_closeDragAllowed) return;
    _closeDragAllowed = false;
    playerSheet.release(details.primaryVelocity ?? 0);
  }

  void _cancelCloseDrag() {
    if (!_closeDragAllowed) return;
    _closeDragAllowed = false;
    playerSheet.release(0);
  }

  bool _handleMainScrollNotification(ScrollNotification notification) {
    if (widget.preview || _view != PlayerView.player || notification.depth != 0) return false;
    if (notification is ScrollStartNotification && notification.dragDetails != null) {
      _mainCloseDragActive = false;
      _closeDragDistance = 0;
      return false;
    }
    if (notification is OverscrollNotification &&
        notification.dragDetails != null &&
        (_mainCloseDragActive ||
            (notification.overscroll < 0 && notification.metrics.pixels <= notification.metrics.minScrollExtent))) {
      _mainCloseDragActive = true;
      _closeDragDistance = (_closeDragDistance - notification.overscroll).clamp(0, double.infinity);
      playerSheet.dragTo(1 - _closeDragDistance / playerSheet.travel);
      return false;
    }
    if (notification is ScrollEndNotification && _mainCloseDragActive) {
      _mainCloseDragActive = false;
      playerSheet.release(notification.dragDetails?.primaryVelocity ?? 0);
    }
    return false;
  }

  Widget _lyricsPreview(SongDetail song, MyAudioHandler handler, {double scale = 1}) {
    final lyrics = ref.watch(selectedLyricsProvider(song.id)) ?? ref.watch(songLyricsProvider(song)).value;
    if (lyrics == null || lyrics.lines.isEmpty) return const SizedBox.shrink();
    return _LyricsPill(
      lyrics: lyrics,
      songId: song.id,
      positionStream: handler.positionStream,
      scale: scale,
      onTap: () => _setPlayerView(PlayerView.lyrics),
    );
  }

  Widget _lyricsContent(SongDetail song, MyAudioHandler handler) {
    final selected = ref.watch(selectedLyricsProvider(song.id));
    final lyrics = selected == null ? ref.watch(songLyricsProvider(song)) : AsyncData<Lyrics?>(selected);
    return lyrics.when(
      loading: () => const Center(child: CircularProgressIndicator(color: Colors.white70)),
      error: (_, __) => const Center(
        child: Text('Lyrics unavailable', style: TextStyle(color: Colors.white70)),
      ),
      data: (value) {
        if (value == null) {
          return const Center(
            child: Text('Lyrics unavailable', style: TextStyle(color: Colors.white70)),
          );
        }
        return Column(
          children: [
            if (!value.isSynced) const Text('Not synced', style: TextStyle(color: Colors.white70, fontSize: 12)),
            if (value.source == 'YouTube transcript')
              const Text('Captions may differ from lyrics', style: TextStyle(color: Colors.white70, fontSize: 12)),
            Expanded(
              child: Listener(
                onPointerDown: (_) => _lyricsPointerDown = true,
                onPointerUp: (_) => _lyricsPointerDown = false,
                onPointerCancel: (_) => _lyricsPointerDown = false,
                child: NotificationListener<ScrollNotification>(
                  onNotification: (notification) {
                    _lyricsScrollOffset = notification.metrics.pixels;
                    return false;
                  },
                  child: NotificationListener<UserScrollNotification>(
                    onNotification: (notification) {
                      if (!_lyricsPointerDown || notification.metrics.axis != Axis.vertical) {
                        return false;
                      }
                      final hide = notification.direction == ScrollDirection.reverse;
                      final show = notification.direction == ScrollDirection.forward;
                      if ((hide && !_lyricsControlsHidden) || (show && _lyricsControlsHidden)) {
                        setState(() => _lyricsControlsHidden = hide);
                      }
                      return false;
                    },
                    child: LyricsLines(
                      key: ValueKey(song.id),
                      songId: song.id,
                      lyrics: value,
                      positionStream: handler.positionStream,
                      glassStyle: true,
                      onSeek: (position) => _seekLyrics(song, handler, position),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _bottomBar(MyAudioHandler handler, {double scale = 1}) {
    final bluetoothDevice = ref.watch(connectedBluetoothDeviceProvider).asData?.value;
    final song = ref.watch(currentSongProvider);
    final outputControl = Tooltip(
      message: bluetoothDevice ?? 'Audio output: This phone',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => showOutputSwitcher(context, ref),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 4 * scale),
          child: bluetoothDevice == null
              ? Text(
                  'This phone',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 12 * scale),
                )
              : Icon(Icons.earbuds_rounded, color: Colors.white, size: 20 * scale),
        ),
      ),
    );
    return _GlassBottomBar(
      scale: scale,
      lyricsActive: _view == PlayerView.lyrics,
      queueActive: _view == PlayerView.queue,
      centerControl: switch (_view) {
        PlayerView.queue => _queueModeBar(handler, scale: scale, bluetoothDevice: bluetoothDevice),
        PlayerView.player => song == null ? outputControl : _playerQuickActions(song, scale: scale),
        PlayerView.lyrics => outputControl,
      },
      onLyrics: () => _setPlayerView(PlayerView.lyrics),
      onQueue: () => _setPlayerView(PlayerView.queue),
    );
  }

  Widget _playerQuickActions(SongDetail song, {double scale = 1}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SegmentedButtonSurface(
          position: _SegmentPosition.first,
          scale: scale,
          child: _downloadSong(song, scale: scale),
        ),
        SizedBox(width: 4 * scale),
        _SegmentedButtonSurface(
          position: _SegmentPosition.last,
          scale: scale,
          child: _ControlButton(
            icon: CupertinoIcons.share,
            tooltip: 'Share song',
            onTap: () => shareMediaItem(song, navigator: Navigator.of(context, rootNavigator: true)),
            size: 44 * scale,
            iconSize: 24 * scale,
          ),
        ),
      ],
    );
  }

  Widget _queueModeBar(MyAudioHandler handler, {double scale = 1, String? bluetoothDevice}) {
    final shuffle = ref.watch(shuffleProvider);
    final repeat = ref.watch(repeatModeProvider);
    return _QueueModeBar(
      shuffle: shuffle,
      repeat: repeat,
      onShuffle: () {
        HapticFeedback.selectionClick();
        handler.toggleShuffle();
      },
      onRepeat: () {
        HapticFeedback.selectionClick();
        handler.toggleRepeatMode();
      },
      onOutput: () => showOutputSwitcher(context, ref),
      bluetoothDevice: bluetoothDevice,
      scale: scale,
    );
  }

  void _syncArtworkPage(MyAudioHandler handler) {
    final index = handler.currentIndex;
    if (!_pageController.hasClients ||
        _pageController.positions.length != 1 ||
        _artworkDragging ||
        _pendingArtworkIndex != null ||
        handler.isShuffleChanging ||
        index < 0 ||
        index >= handler.queueLength ||
        _pageController.page?.round() == index) {
      return;
    }
    _artworkSyncing = true;
    _pageController.jumpToPage(index);
    _artworkSyncing = false;
  }

  Future<void> _settleArtworkPage(MyAudioHandler handler, int index) async {
    if (index < 0 || index >= handler.queueLength || handler.isShuffleChanging) {
      _pendingArtworkIndex = null;
      return;
    }
    if (handler.currentIndex == index) {
      _pendingArtworkIndex = null;
      return;
    }
    final generation = ++_artworkRequestGeneration;
    _pendingArtworkIndex = index;
    try {
      await handler.skipToQueueItem(index);
    } finally {
      if (mounted && generation == _artworkRequestGeneration) {
        _pendingArtworkIndex = null;
        _syncArtworkPage(handler);
      }
    }
  }

  Widget _playerStage(BuildContext context, MyAudioHandler handler, SongDetail song, Size size, Size viewportSize) {
    final media = MediaQuery.of(context);
    final padding = media.viewPadding;
    final availableHeight = (viewportSize.height - padding.top - padding.bottom).clamp(0.0, viewportSize.height);
    final scale = availableHeight < 600
        ? (availableHeight / 874).clamp(.68, .82)
        : (availableHeight / 874).clamp(.82, 1.2);
    final landscape = viewportSize.width > viewportSize.height;
    final artworkRect = fullPlayerArtworkRect(viewportSize, padding);
    final panelWidth = landscape ? (viewportSize.width - artworkRect.right).clamp(0.0, 560.0) : artworkRect.width;
    final panelLeft = landscape
        ? artworkRect.right + (viewportSize.width - artworkRect.right - panelWidth) / 2
        : artworkRect.left;
    final compact = _view != PlayerView.player;
    final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 400);
    final titleDuration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 250);
    final artworkHeight = artworkRect.height;
    final compactTop = padding.top + 40;
    final fullTitleTop = (landscape ? padding.top : artworkHeight) + (landscape ? 4 : 46) * scale;
    final fullTitleRight = size.width - (panelLeft + panelWidth - 52 * scale - 80);
    final titleAllowance = (21 * 1.2 + 3 + 18 * 1.2) * scale * media.textScaler.scale(1);
    final fullButtonTop = fullTitleTop + (titleAllowance.clamp(44.0, double.infinity) - 40) / 2;
    final fullButtonRight = size.width - panelLeft - panelWidth + 36 * scale;
    final footerBottom = padding.bottom + (availableHeight < 600 ? 4.0 : 24.0);
    final playbackHeight = (availableHeight > 820 ? 104.0 : 96.0) * scale;
    final bottomBarHeight = 56 * scale;
    const queueModeHeight = 44.0;
    final queueModeGap = 8 * scale;
    final footerControlsHeight = playbackHeight + queueModeHeight + queueModeGap + bottomBarHeight;
    final seekHeight = 36 + media.textScaler.scale(13) * 1.5;
    final footerHeight = footerBottom + footerControlsHeight + seekHeight;
    final lyricsBylineHeight = 32 * scale;
    final footerLeft = landscape ? panelLeft + 20 * scale : 20 * scale;
    final footerRight = landscape ? size.width - panelLeft - panelWidth + 20 * scale : 20 * scale;
    final controlsHidden =
        (_view == PlayerView.lyrics && _lyricsControlsHidden) || (_view == PlayerView.queue && _queueControlsHidden);
    final controlsDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : Duration(milliseconds: _view == PlayerView.queue ? 200 : 300);
    final subtitle = playerSongSubtitle(song);
    final source = handler.queueSourceName;
    final isLiked = ref.watch(likedSongsProvider).contains(song.id);
    final lyrics = ref.watch(selectedLyricsProvider(song.id)) ?? ref.watch(songLyricsProvider(song)).value;
    final hasLyrics = !widget.preview && lyrics != null && lyrics.lines.isNotEmpty;
    final sourceArtworkUrl = song.images.isNotEmpty ? song.images.last.url : '';
    final playerArtworkUrl = fullPlayerArtworkUrl(sourceArtworkUrl);
    return Stack(
      clipBehavior: Clip.hardEdge,
      children: [
        IosArtworkPosition(
          key: _artworkPositionKey,
          rect: compact
              ? Rect.fromLTWH(20, compactTop, 56, 56)
              : Rect.fromLTWH(artworkRect.left, artworkRect.top, artworkRect.width, artworkHeight),
          radius: compact ? 8 : 0,
          bottomFade: compact ? 0 : 1,
          reduceMotion: MediaQuery.disableAnimationsOf(context),
          child: ValueListenableBuilder<double>(
            valueListenable: playerSheet.progress,
            builder: (context, sheetProgress, child) {
              // the flying artwork hands over to this one only when fully open
              final visible = !widget.preview && sheetProgress >= 1;
              return Opacity(opacity: visible ? 1 : 0, child: child);
            },
            child: StreamBuilder<PlayerState>(
              stream: handler.playerStateStream,
              builder: (context, state) => PlaybackArtwork(
                isPlaying: true,
                child: Opacity(
                  opacity: widget.preview ? 0 : 1,
                  child: Container(
                    key: const ValueKey('full-player-artwork'),
                    child: AnimatedSwitcher(
                      layoutBuilder: (currentChild, previousChildren) => Stack(
                        fit: StackFit.expand,
                        alignment: Alignment.center,
                        children: [...previousChildren, if (currentChild != null) currentChild],
                      ),
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 320),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: .96, end: 1).animate(animation),
                          child: child,
                        ),
                      ),
                      child: handler.currentIndex < 0 || handler.currentIndex >= handler.queueLength
                          ? HeroMode(
                              key: ValueKey('current-art-${song.id}'),
                              enabled: !widget.preview,
                              child: PlayerArtworkHero(
                                child: CacheNetWorkImg(
                                  url: playerArtworkUrl,
                                  fallbackUrl: song.images.isNotEmpty ? song.images.last.url : null,
                                  fit: BoxFit.cover,
                                  alignment: Alignment.topCenter,
                                  fadeInDuration: Duration.zero,
                                  fadeOutDuration: Duration.zero,
                                ),
                              ),
                            )
                          : NotificationListener<ScrollNotification>(
                              key: const ValueKey('queue-artwork-pages'),
                              onNotification: (notification) {
                                if (notification.depth != 0) return false;
                                if (notification is ScrollStartNotification && notification.dragDetails != null) {
                                  _artworkDragging = true;
                                  _artworkRequestGeneration++;
                                } else if (notification is ScrollEndNotification && _artworkDragging) {
                                  _artworkDragging = false;
                                  final index = _pageController.hasClients && _pageController.positions.length == 1
                                      ? _pageController.page?.round()
                                      : null;
                                  if (index != null) _settleArtworkPage(handler, index);
                                }
                                return false;
                              },
                              child: PageView.builder(
                                controller: _pageController,
                                physics: compact ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
                                itemCount: handler.queueLength,
                                onPageChanged: (index) {
                                  if (_artworkSyncing) return;
                                  if (_artworkDragging) _pendingArtworkIndex = index;
                                },
                                itemBuilder: (context, index) {
                                  final images = handler.queueSongs[index].images;
                                  final artwork = images.isNotEmpty ? images.last.url : '';
                                  return HeroMode(
                                    enabled: !widget.preview && index == handler.currentIndex,
                                    child: PlayerArtworkHero(
                                      child: CacheNetWorkImg(
                                        url: fullPlayerArtworkUrl(artwork),
                                        fallbackUrl: artwork,
                                        fit: BoxFit.cover,
                                        alignment: Alignment.topCenter,
                                        fadeInDuration: Duration.zero,
                                        fadeOutDuration: Duration.zero,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (!compact)
          Positioned(
            top: artworkRect.top,
            left: artworkRect.left,
            width: artworkRect.width,
            height: (padding.top + 90).clamp(0.0, artworkHeight),
            child: const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x73000000), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
        Positioned(
          top: compact ? padding.top + 3 : artworkRect.top + (landscape ? 3 : padding.top + 3),
          left: compact ? 0 : artworkRect.left,
          width: compact ? size.width : artworkRect.width,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: playerSheet.close,
            onVerticalDragStart: _startPillDrag,
            onVerticalDragUpdate: _updateCloseDrag,
            onVerticalDragEnd: _settleCloseDrag,
            onVerticalDragCancel: _cancelCloseDrag,
            child: Column(
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(color: Colors.white70, borderRadius: BorderRadius.circular(3)),
                ),
                const SizedBox(height: 7),
                if (!compact && source != null && source.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24 * scale),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        'Playing $source',
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          shadows: [Shadow(color: Color(0x66000000), blurRadius: 6)],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 24), // taller grab area for the pill
              ],
            ),
          ),
        ),
        AnimatedPositioned(
          duration: titleDuration,
          curve: Curves.easeOutCubic,
          top: compact ? compactTop + 6 : fullButtonTop,
          right: (compact ? 20 + 8 * scale : fullButtonRight) + 40 + 8 * scale,
          child: PlayerEntrance(
            begin: .48,
            end: .78,
            child: IgnorePointer(
              ignoring: compact,
              child: AnimatedOpacity(
                opacity: compact ? 0 : 1,
                duration: titleDuration,
                child: _GlassButton(
                  icon: isLiked ? CupertinoIcons.star_fill : CupertinoIcons.star,
                  iconColor: isLiked ? spotifyGreen : Colors.white,
                  tooltip: isLiked ? 'Remove from liked songs' : 'Add to liked songs',
                  onTap: () => ref.read(likedSongsProvider.notifier).toggle(song.id),
                  size: 40,
                  iconSize: 20,
                ),
              ),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: titleDuration,
          curve: Curves.easeOutCubic,
          top: compact ? compactTop + 6 : fullButtonTop,
          right: compact ? 20 + 8 * scale : fullButtonRight,
          child: PlayerEntrance(
            begin: .48,
            end: .78,
            child: _GlassButton(
              icon: CupertinoIcons.ellipsis,
              tooltip: 'Song options',
              onTap: () => showMediaItemMenu(context, song),
              size: 40,
              iconSize: 20,
            ),
          ),
        ),
        if (compact)
          AnimatedPositioned(
            duration: controlsDuration,
            curve: Curves.easeOutCubic,
            top: compactTop + (_view == PlayerView.queue ? 64 : 66),
            bottom: controlsHidden
                ? padding.bottom + 4
                : footerHeight + (_view == PlayerView.lyrics && lyrics != null ? lyricsBylineHeight : 0),
            left: 20 * scale,
            right: 20 * scale,
            child: AnimatedSwitcher(
              duration: duration,
              layoutBuilder: (currentChild, previousChildren) => currentChild ?? const SizedBox.shrink(),
              child: _view == PlayerView.lyrics
                  ? KeyedSubtree(key: const ValueKey('inline-lyrics'), child: _lyricsContent(song, handler))
                  : KeyedSubtree(
                      key: const ValueKey('inline-queue'),
                      child: NotificationListener<ScrollNotification>(
                        onNotification: _onQueueScroll,
                        child: QueueList(
                          scrollController: _queueController,
                          showCurrentSong: false,
                          header: const SizedBox.shrink(),
                        ),
                      ),
                    ),
            ),
          ),
        if (compact && _view == PlayerView.lyrics && !controlsHidden && lyrics != null)
          Positioned(
            left: 20 * scale,
            right: 20 * scale,
            bottom: footerHeight + lyricsBylineHeight,
            height: 48 * scale,
            child: const IgnorePointer(child: PlayerArtworkEdge()),
          ),
        if (compact && _view == PlayerView.lyrics && !controlsHidden && lyrics != null)
          Positioned(
            left: 0,
            bottom: footerHeight,
            width: 64 * scale,
            height: 64 * scale,
            child: const IgnorePointer(child: PlayerArtworkEdge(key: ValueKey('lyrics-left-edge-blur'))),
          ),
        if (compact && _view == PlayerView.lyrics && !controlsHidden && lyrics != null)
          Positioned(
            right: 0,
            bottom: footerHeight,
            width: 64 * scale,
            height: 64 * scale,
            child: const IgnorePointer(child: PlayerArtworkEdge(key: ValueKey('lyrics-right-edge-blur'))),
          ),
        if (compact && _view == PlayerView.lyrics && !controlsHidden && lyrics != null)
          Positioned(
            left: 20 * scale,
            right: 20 * scale,
            bottom: footerHeight,
            height: lyricsBylineHeight,
            child: Padding(
              padding: EdgeInsets.only(left: 20 * scale, right: 12 * scale),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Lyrics by ${lyrics.source}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Change lyrics provider',
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints.tightFor(width: 36 * scale, height: 32 * scale),
                    onPressed: () => _showLyricsProviders(song, lyrics),
                    icon: Icon(LucideIcons.captions, color: Colors.white70, size: 20 * scale),
                  ),
                ],
              ),
            ),
          ),
        AnimatedPositioned(
          duration: titleDuration,
          curve: Curves.easeOutCubic,
          top: compact ? compactTop + 6 : fullTitleTop,
          left: compact ? 88 + 8 * scale : panelLeft + 36 * scale,
          right: compact ? 78 + 8 * scale : fullTitleRight,
          child: PlayerEntrance(
            begin: .34,
            end: .68,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 21 * scale, end: compact ? 14 : 21 * scale),
              duration: titleDuration,
              curve: Curves.easeOutCubic,
              builder: (context, titleFontSize, _) => TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 18 * scale, end: compact ? 13 : 18 * scale),
                duration: titleDuration,
                curve: Curves.easeOutCubic,
                builder: (context, subtitleFontSize, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _marqueeText(
                      trimAfterParamText(song.title),
                      fontSize: titleFontSize,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -.4,
                    ),
                    if (subtitle.isNotEmpty) ...[
                      SizedBox(height: 3 * scale),
                      _marqueeText(
                        subtitle,
                        fontSize: subtitleFontSize,
                        color: Colors.white70,
                        fontWeight: FontWeight.w400,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
        if (!compact && hasLyrics)
          Positioned(
            left: landscape ? panelLeft + 20 * scale : 20 * scale,
            width: landscape ? (panelWidth - 40 * scale).clamp(0.0, panelWidth).toDouble() : null,
            right: landscape ? null : 20 * scale,
            bottom: footerBottom + footerControlsHeight + seekHeight - 7,
            height: 36 * scale,
            child: PlayerEntrance(begin: .55, end: .82, child: _lyricsPreview(song, handler, scale: scale)),
          ),
        Positioned(
          left: landscape ? panelLeft + 20 * scale : 20 * scale,
          width: landscape ? (panelWidth - 40 * scale).clamp(0.0, panelWidth).toDouble() : null,
          right: landscape ? null : 20 * scale,
          bottom: footerBottom + footerControlsHeight,
          child: PlayerEntrance(
            begin: .63,
            end: .88,
            child: IgnorePointer(
              ignoring: controlsHidden,
              child: AnimatedSlide(
                offset: controlsHidden ? const Offset(0, 1) : Offset.zero,
                duration: controlsDuration,
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: controlsHidden ? 0 : 1,
                  duration: controlsDuration,
                  curve: Curves.easeOutCubic,
                  child: _streamProgressBar(),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: footerLeft,
          right: footerRight,
          bottom: footerBottom,
          height: footerControlsHeight,
          child: IgnorePointer(
            ignoring: controlsHidden,
            child: AnimatedSlide(
              offset: controlsHidden ? const Offset(0, 1) : Offset.zero,
              duration: controlsDuration,
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: controlsHidden ? 0 : 1,
                duration: controlsDuration,
                curve: Curves.easeOutCubic,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 24 * scale,
                      height: bottomBarHeight,
                      child: PlayerEntrance(begin: .8, end: 1, child: _bottomBar(handler, scale: scale)),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: bottomBarHeight + queueModeGap + queueModeHeight,
                      height: playbackHeight,
                      child: PlayerEntrance(
                        begin: .7,
                        end: .93,
                        child: _playBackControl(scale: scale, tall: availableHeight > 820),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _seekLyrics(SongDetail song, MyAudioHandler handler, Duration position) {
    if (ref.read(currentSongProvider)?.id != song.id) return;
    final media = handler.mediaItem.value;
    final total = media?.id == song.id ? media?.duration : null;
    handler.seek(total != null && position > total ? total : position);
  }

  void _showLyricsProviders(SongDetail song, Lyrics lyrics) {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => LyricsProviderSheet(song: song, currentLyrics: lyrics),
    );
  }

  void openQueueBottomSheet() {
    final song = ref.watch(currentSongProvider);
    final size = MediaQuery.of(context).size;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.01,
        maxChildSize: .95,
        expand: false,
        snap: true,
        builder: (_, scrollController) => ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: SheetSurface(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: size.height, maxWidth: size.width),
              child: QueueList(
                scrollController: scrollController,
                header: Column(
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
                            borderRadius: BorderRadius.all(Radius.circular(2)),
                          ),
                        ),
                      ),
                    ),

                    // Header
                    Align(
                      alignment: Alignment.topLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Queue",
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text(
                                  "Playing ",
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white60),
                                ),
                                Expanded(
                                  child: Text(
                                    song?.album ?? 'Now',
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.white54),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
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
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
          ),
          TextSpan(
            text: " $label",
            style: const TextStyle(color: Colors.white54, fontWeight: FontWeight.w400),
          ),
        ],
      ),
    );
  }

  Widget _artistInfoWidget() {
    final imageUrl = _artistDetails!.images.where((image) => image.url.trim().isNotEmpty).lastOrNull?.url ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          final artistId = _artistDetails!.id;
          if (artistId.isEmpty) return;
          final navigator = ref.read(playerNavProvider.notifier);
          final tabIndex = ref.read(tabIndexProvider);
          playerSheet.close();
          navigator.navigate(PlayerNavCommand(type: PlayerNavType.artist, id: artistId, tabIndex: tabIndex));
        },
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
                if (imageUrl.isNotEmpty)
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
                            url: fullPlayerArtworkUrl(imageUrl),
                            fallbackUrl: imageUrl,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),

                      Container(
                        height: 200,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.black.withAlpha(150), Colors.transparent],
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
                            shadows: [Shadow(blurRadius: 10.0, color: Colors.black, offset: Offset(2.0, 2.0))],
                          ),
                        ),
                      ),
                    ],
                  ),

                const SizedBox(height: 12),
                // --- Stats Section ---
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                            const Icon(Icons.verified, color: Colors.blueAccent, size: 20),
                        ],
                      ),
                      if (_artistDetails!.followerCount != null)
                        _buildStatItem("subscribers", followersFormatter(_artistDetails!.followerCount ?? 0)),
                      if (_artistDetails!.dominantLanguage.isNotEmpty)
                        _buildStatItem("language", _artistDetails!.dominantLanguage),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                if (_artistDetails!.bio.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: ValueListenableBuilder<bool>(
                      valueListenable: _isBioExpanded,
                      builder: (context, expanded, _) {
                        final fullBio = _artistDetails!.bio.map((bio) => sanitizeBio(bio)).join("\n\n");

                        final displayBio = expanded
                            ? fullBio
                            : (fullBio.length > 180 ? '${fullBio.substring(0, 180)}...' : fullBio);

                        return GestureDetector(
                          onTap: () => _isBioExpanded.value = !expanded,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayBio,
                                style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                expanded ? "Show less" : "Read more",
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: spotifyGreen),
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
      ),
    );
  }

  Widget _playBackControl({double scale = 1, bool tall = false}) {
    return FutureBuilder<MyAudioHandler>(
      future: ref.read(audioHandlerProvider.future),
      builder: (context, snapshot) {
        final handler = snapshot.data;
        final playSize = (tall ? 104.0 : 96.0) * scale;
        final skipSize = (tall ? 70.0 : 64.0) * scale;
        if (handler == null) return SizedBox(height: playSize);
        return StreamBuilder<PlayerState>(
          stream: handler.playerStateStream,
          builder: (context, state) {
            final playing = state.data?.playing ?? handler.playbackState.value.playing;
            final processing = state.data?.processingState;
            final loading = processing == ProcessingState.loading || processing == ProcessingState.buffering;
            return LayoutBuilder(
              builder: (context, constraints) {
                final fit = (constraints.maxWidth / (playSize + 2 * skipSize)).clamp(0.0, 1.0);
                final actualPlay = playSize * fit;
                final actualSkip = skipSize * fit;
                return SizedBox(
                  height: playSize,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: ((constraints.maxWidth - actualPlay - 2 * actualSkip) / 2).clamp(0.0, 40 * scale),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _ControlButton(
                          icon: CupertinoIcons.backward_fill,
                          tooltip: 'Previous',
                          enabled: handler.hasPrevious,
                          onTap: handler.hasPrevious ? handler.skipToPrevious : null,
                          size: actualSkip,
                          iconSize: 50 * scale * fit,
                        ),
                        if (loading)
                          SizedBox(
                            width: actualPlay,
                            height: actualPlay,
                            child: const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            ),
                          )
                        else
                          _ControlButton(
                            tooltip: playing ? 'Pause' : 'Play',
                            enabled: true,
                            onTap: () => playing ? handler.pause() : handler.play(),
                            size: actualPlay,
                            iconWidget: AnimatedSwitcher(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 180),
                              transitionBuilder: (child, animation) => ScaleTransition(
                                scale: Tween<double>(begin: .8, end: 1).animate(animation),
                                child: FadeTransition(opacity: animation, child: child),
                              ),
                              child: Icon(
                                playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
                                key: ValueKey(playing),
                                color: Colors.white,
                                size: 56 * scale * fit,
                              ),
                            ),
                          ),
                        _ControlButton(
                          icon: CupertinoIcons.forward_fill,
                          tooltip: 'Next',
                          enabled: handler.hasNext,
                          onTap: handler.hasNext ? handler.skipToNext : null,
                          size: actualSkip,
                          iconSize: 50 * scale * fit,
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _streamProgressBar() {
    return FutureBuilder<MyAudioHandler>(
      future: ref.read(audioHandlerProvider.future),
      builder: (context, snapshot) {
        final audioHandler = snapshot.data;
        if (audioHandler == null) {
          return const SizedBox(height: 50);
        }

        // Watch current song so UI updates when song changes
        final song = ref.watch(currentSongProvider);
        return StreamBuilder<Duration>(
          stream: audioHandler.positionStream,
          builder: (context, posSnapshot) {
            return StreamBuilder<MediaItem?>(
              stream: audioHandler.mediaItem,
              initialData: audioHandler.mediaItem.value,
              builder: (context, mediaSnapshot) {
                final item = mediaSnapshot.data;
                final pos = item?.id == song?.id ? posSnapshot.data ?? Duration.zero : Duration.zero;
                final total =
                    (item?.id == song?.id ? item?.duration : null) ??
                    Duration(seconds: int.tryParse(song?.duration ?? '0') ?? 0);

                return PlayerSeekBar(
                  key: ValueKey(song?.id),
                  position: pos,
                  duration: total,
                  playerStateStream: audioHandler.playerStateStream,
                  onSeek: (position) async {
                    if (song != null && ref.read(currentSongProvider)?.id == song.id) {
                      await audioHandler.seek(position);
                    }
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _downloadSong(SongDetail song, {double scale = 1}) {
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
                width: 32 * scale,
                height: 32 * scale,
                color: spotifyGreen,
              );
              onTap = () async => await offlineManager.deleteSong(song.id);
            } else if (status == DownloadStatus.downloading) {
              iconWidget = SizedBox(
                width: 32 * scale,
                height: 32 * scale,
                child: Padding(
                  padding: EdgeInsets.all(6 * scale),
                  child: CircularProgressIndicator(
                    value: progress / 100,
                    color: spotifyGreen,
                    strokeWidth: 2.2 * scale,
                    backgroundColor: Colors.grey.shade800,
                  ),
                ),
              );
            } else {
              iconWidget = Image.asset(
                'assets/icons/download.png',
                width: 32 * scale,
                height: 32 * scale,
                color: Colors.white,
              );
              onTap = () async {
                offlineManager.updateStatus(song.id, DownloadStatus.downloading);
                offlineManager.updateProgress(song.id, 0.0);
                offlineManager.requestSongDownload(
                  song.id,
                  song: song,
                  onProgress: (p) => offlineManager.updateProgress(song.id, p),
                );
              };
            }

            return _ControlButton(
              iconWidget: iconWidget,
              tooltip: switch (status) {
                DownloadStatus.completed => 'Remove downloaded song',
                DownloadStatus.downloading => 'Downloading song',
                _ => 'Download song',
              },
              onTap: onTap,
              enabled: onTap != null,
              size: 44 * scale,
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(currentSongProvider);
    if (song == null) return const SizedBox.shrink();
    ref.listen<SongDetail?>(currentSongProvider, (prev, next) {
      if (widget.preview) return;
      if (next != null) {
        if (next.id != prev?.id) _updateBgColor();
        if (prev == null || songArtistLookupKey(next) != songArtistLookupKey(prev)) {
          if (_initialArtistRequested) {
            _fetchArtistDetails();
          } else {
            _scheduleInitialArtistFetch();
          }
        }
      } else if (prev != null) {
        _artistRequestGeneration++;
      }
    });
    final handlerAsync = ref.watch(audioHandlerProvider);
    final media = MediaQuery.of(context);
    return MediaQuery(
      data: media.copyWith(textScaler: media.textScaler.clamp(maxScaleFactor: 1.15)),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: widget.preview ? null : _startCloseDrag,
        onVerticalDragUpdate: widget.preview ? null : _updateCloseDrag,
        onVerticalDragEnd: widget.preview ? null : _settleCloseDrag,
        onVerticalDragCancel: widget.preview ? null : _cancelCloseDrag,
        child: PlayerGlassBackground(
          color: ref.watch(playerColourProvider),
          artworkUrl: song.images.isNotEmpty ? fullPlayerArtworkUrl(song.images.last.url) : null,
          tintArtwork: true,
          child: handlerAsync.when(
            data: (handler) {
              ref.watch(queueStreamProvider(handler));
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _syncArtworkPage(handler);
              });
              return LayoutBuilder(
                builder: (context, constraints) {
                  final viewport = Size(constraints.maxWidth, constraints.maxHeight);
                  final viewPadding = MediaQuery.viewPaddingOf(context);
                  final h = (viewport.height - viewPadding.top - viewPadding.bottom).clamp(0.0, viewport.height);
                  final scale = h < 600 ? (h / 874).clamp(.68, .82) : (h / 874).clamp(.82, 1.2);
                  final landscape = viewport.width > viewport.height;
                  final artwork = fullPlayerArtworkRect(viewport, viewPadding);
                  final titleAllowance = (23 * 1.2 + 3 + 18 * 1.2) * scale * MediaQuery.textScalerOf(context).scale(1);
                  final lyricsGap = (h < 640 ? 12 : 28) * scale;
                  final seekHeight = 36 + MediaQuery.textScalerOf(context).scale(13) * 1.5;
                  final contentHeight =
                      46 * scale +
                      titleAllowance.clamp(44.0, double.infinity) +
                      lyricsGap +
                      36 * scale +
                      4 * scale +
                      seekHeight +
                      viewPadding.bottom +
                      (h < 600 ? 8 : 28);
                  final minimumHeight = _view == PlayerView.player
                      ? (landscape ? viewport.height : artwork.height + contentHeight)
                      : 560.0;
                  final stageSize = Size(viewport.width, viewport.height.clamp(minimumHeight, double.infinity));
                  return NotificationListener<ScrollNotification>(
                    onNotification: _handleMainScrollNotification,
                    child: CustomScrollView(
                      controller: widget.scrollController,
                      physics: _view == PlayerView.player && !landscape || constraints.maxHeight < 560 && !landscape
                          ? _PlayerSheetScrollPhysics(
                              isSheetDragging: () => _mainCloseDragActive,
                              parent: const ClampingScrollPhysics(),
                            )
                          : const NeverScrollableScrollPhysics(),
                      slivers: [
                        SliverToBoxAdapter(
                          child: SizedBox(
                            width: stageSize.width,
                            height: stageSize.height,
                            child: _playerStage(context, handler, song, stageSize, viewport),
                          ),
                        ),
                        if (_view == PlayerView.player && !widget.preview && !landscape) ...[
                          if (_artistDetails != null)
                            SliverToBoxAdapter(
                              child: Center(
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 560),
                                  child: _artistInfoWidget(),
                                ),
                              ),
                            ),
                          SliverToBoxAdapter(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 560),
                                child: SongCredits(
                                  song: song,
                                  onArtistTap: (artistId) {
                                    final navigator = ref.read(playerNavProvider.notifier);
                                    final tabIndex = ref.read(tabIndexProvider);
                                    playerSheet.close();
                                    navigator.navigate(
                                      PlayerNavCommand(type: PlayerNavType.artist, id: artistId, tabIndex: tabIndex),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const EmptyStatePage(
              state: EmptyState(
                icon: LucideIcons.circleAlert,
                title: 'Player unavailable',
                subtitle: 'The player could not be loaded. Please try again.',
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PressScale extends StatefulWidget {
  const _PressScale({required this.child, this.onTap, this.tooltip});
  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;
  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _pressed = false;
  @override
  Widget build(BuildContext context) {
    final child = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _pressed = true),
      onTapCancel: () {
        if (_pressed) setState(() => _pressed = false);
      },
      onTapUp: (_) {
        if (_pressed) setState(() => _pressed = false);
      },
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? .92 : 1,
        duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 160),
        curve: Curves.easeOutBack,
        child: AnimatedOpacity(
          opacity: _pressed ? .72 : 1,
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 120),
          child: widget.child,
        ),
      ),
    );
    if (widget.tooltip == null) return child;
    return Semantics(
      container: true,
      button: true,
      enabled: widget.onTap != null,
      label: widget.tooltip,
      onTap: widget.onTap,
      child: ExcludeSemantics(child: child),
    );
  }
}

class _GlassButton extends StatelessWidget {
  const _GlassButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.size = 44,
    this.iconSize = 22,
    this.iconColor,
  });
  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  final double size;
  final double iconSize;
  final Color? iconColor;
  @override
  Widget build(BuildContext context) => _PressScale(
    tooltip: tooltip,
    onTap: onTap,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(size / 2),
            border: Border.all(color: Colors.white.withValues(alpha: .2), width: .5),
          ),
          child: Icon(
            icon,
            color: iconColor ?? (onTap == null ? Colors.white.withValues(alpha: .35) : Colors.white),
            size: iconSize,
          ),
        ),
      ),
    ),
  );
}

class _LyricsPill extends ConsumerWidget {
  const _LyricsPill({
    required this.lyrics,
    required this.songId,
    required this.positionStream,
    required this.onTap,
    this.scale = 1,
  });
  final Lyrics lyrics;
  final String songId;
  final Stream<Duration> positionStream;
  final VoidCallback onTap;
  final double scale;
  @override
  Widget build(BuildContext context, WidgetRef ref) => ValueListenableBuilder<int>(
    valueListenable: ref.watch(lyricsOffsetProvider(songId)),
    builder: (context, offset, _) => StreamBuilder<Duration>(
      stream: positionStream,
      builder: (context, snapshot) {
        final index = lyrics.indexAt((snapshot.data ?? Duration.zero) - Duration(milliseconds: offset));
        final text = lyrics.lines[index < 0 ? 0 : index].text;
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: 20 * scale),
          child: _PressScale(
            onTap: onTap,
            tooltip: 'Open lyrics',
            child: SizedBox(
              height: 36 * scale,
              child: Row(
                children: [
                  Expanded(
                    child: ShaderMask(
                      blendMode: BlendMode.srcIn,
                      shaderCallback: (bounds) => LinearGradient(
                        colors: [Colors.white, Colors.white.withValues(alpha: .35)],
                      ).createShader(bounds),
                      child: Text(
                        text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'SpotifyMix',
                          color: Colors.white,
                          fontSize: 19 * scale,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: Colors.white70, size: 18 * scale),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

enum _SegmentPosition { first, middle, last }

class _SegmentedButtonSurface extends StatelessWidget {
  const _SegmentedButtonSurface({required this.position, required this.child, this.scale = 1});

  final _SegmentPosition position;
  final Widget child;
  final double scale;

  @override
  Widget build(BuildContext context) {
    const baseSize = 44.0;
    final horizontalInset = 4 * scale;
    final verticalInset = 1 * scale;
    final outerRadius = (baseSize * scale + verticalInset * 2) / 2;
    final innerRadius = 7 * scale;
    final leftRadius = position == _SegmentPosition.first ? outerRadius : innerRadius;
    final rightRadius = position == _SegmentPosition.last ? outerRadius : innerRadius;
    final borderRadius = BorderRadius.horizontal(
      left: Radius.circular(leftRadius),
      right: Radius.circular(rightRadius),
    );

    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        width: baseSize * scale + horizontalInset * 2,
        height: baseSize * scale + verticalInset * 2,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white.withValues(alpha: .14), Colors.white.withValues(alpha: .07)],
          ),
          borderRadius: borderRadius,
          border: Border.all(color: Colors.white.withValues(alpha: .24), width: .5),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalInset, vertical: verticalInset),
          child: child,
        ),
      ),
    );
  }
}

class _PlayerModeButton extends StatelessWidget {
  const _PlayerModeButton({
    required this.icon,
    required this.tooltip,
    required this.active,
    required this.onTap,
    this.scale = 1,
  });
  final IconData icon;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;
  final double scale;

  @override
  Widget build(BuildContext context) => _PressScale(
    tooltip: tooltip,
    onTap: onTap,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(14 * scale),
      child: BackdropFilter(
        enabled: active,
        filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 200),
          width: 44 * scale,
          height: 44 * scale,
          decoration: BoxDecoration(
            color: active ? Colors.white.withValues(alpha: .18) : Colors.white.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(14 * scale),
          ),
          child: Icon(icon, color: Colors.white, size: 28 * scale),
        ),
      ),
    ),
  );
}

class _GlassBottomBar extends StatelessWidget {
  const _GlassBottomBar({
    required this.lyricsActive,
    required this.queueActive,
    required this.onLyrics,
    required this.onQueue,
    required this.centerControl,
    this.scale = 1,
  });
  final double scale;
  final bool lyricsActive, queueActive;
  final VoidCallback onLyrics, onQueue;
  final Widget centerControl;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 56 * scale,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 20 * scale),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _PlayerModeButton(
            icon: lyricsActive ? CupertinoIcons.quote_bubble_fill : CupertinoIcons.quote_bubble,
            tooltip: 'Lyrics',
            onTap: onLyrics,
            active: lyricsActive,
            scale: scale,
          ),
          centerControl,
          _PlayerModeButton(
            icon: CupertinoIcons.list_bullet,
            tooltip: queueActive ? 'Close queue' : 'Queue',
            onTap: onQueue,
            active: queueActive,
            scale: scale,
          ),
        ],
      ),
    ),
  );
}

class _QueueModeBar extends StatelessWidget {
  const _QueueModeBar({
    required this.shuffle,
    required this.repeat,
    required this.onShuffle,
    required this.onRepeat,
    required this.onOutput,
    this.bluetoothDevice,
    this.scale = 1,
  });
  final bool shuffle;
  final RepeatMode repeat;
  final VoidCallback onShuffle, onRepeat, onOutput;
  final String? bluetoothDevice;
  final double scale;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      _SegmentedButtonSurface(
        position: _SegmentPosition.first,
        scale: scale,
        child: _ControlButton(
          icon: CupertinoIcons.shuffle,
          tooltip: 'Shuffle',
          onTap: onShuffle,
          active: shuffle,
          size: 44 * scale,
          iconSize: 24 * scale,
        ),
      ),
      SizedBox(width: 4 * scale),
      _SegmentedButtonSurface(
        position: _SegmentPosition.middle,
        scale: scale,
        child: _ControlButton(
          icon: repeat == RepeatMode.one ? CupertinoIcons.repeat_1 : CupertinoIcons.repeat,
          tooltip: 'Repeat',
          onTap: onRepeat,
          active: repeat != RepeatMode.none,
          size: 44 * scale,
          iconSize: 24 * scale,
        ),
      ),
      SizedBox(width: 4 * scale),
      _SegmentedButtonSurface(
        position: _SegmentPosition.last,
        scale: scale,
        child: _ControlButton(
          iconWidget: Icon(
            bluetoothDevice == null ? LucideIcons.volume2 : LucideIcons.headphones,
            color: Colors.white,
            size: 24 * scale,
          ),
          tooltip: bluetoothDevice ?? 'Audio output and volume',
          onTap: onOutput,
          size: 44 * scale,
        ),
      ),
    ],
  );
}

// control button
class _ControlButton extends StatelessWidget {
  final IconData? icon;
  final String? tooltip;
  final Widget? iconWidget;
  final VoidCallback? onTap;
  final bool enabled;
  final bool active;
  final double size;
  final double? iconSize;

  const _ControlButton({
    this.icon,
    this.tooltip,
    this.iconWidget,
    this.onTap,
    this.enabled = true,
    this.active = false,
    this.size = 40,
    this.iconSize,
  }) : assert(icon != null || iconWidget != null, "Either icon or iconWidget must be provided");

  @override
  Widget build(BuildContext context) {
    return _PressScale(
      onTap: enabled ? onTap : null,
      tooltip: tooltip,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? Colors.white.withValues(alpha: .18) : Colors.transparent,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child:
                  iconWidget ??
                  Icon(
                    icon,
                    color: enabled ? Colors.white : Colors.white.withValues(alpha: .35),
                    size: iconSize ?? size * 0.6,
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

  return Builder(
    builder: (context) => SizedBox(
      height: MediaQuery.textScalerOf(context).scale(fontSize) * height,
      child: MediaQuery.disableAnimationsOf(context)
          ? Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: fontSize, fontWeight: fontWeight, letterSpacing: letterSpacing),
            )
          : _DelayedMarquee(
              text: text,
              style: TextStyle(color: color, fontSize: fontSize, fontWeight: fontWeight, letterSpacing: letterSpacing),
            ),
    ),
  );
}

class _DelayedMarquee extends StatefulWidget {
  const _DelayedMarquee({required this.text, required this.style});
  final String text;
  final TextStyle style;

  @override
  State<_DelayedMarquee> createState() => _DelayedMarqueeState();
}

class _DelayedMarqueeState extends State<_DelayedMarquee> {
  bool _allowFade = false;
  bool _requestedFade = false;
  bool _fadeUpdateScheduled = false;

  @override
  void didUpdateWidget(covariant _DelayedMarquee oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _allowFade = false;
      _requestedFade = false;
    }
  }

  void _setScrolling(bool scrolling) {
    _requestedFade = scrolling;
    if (_fadeUpdateScheduled) return;
    _fadeUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fadeUpdateScheduled = false;
      if (mounted && _allowFade != _requestedFade) setState(() => _allowFade = _requestedFade);
    });
  }

  @override
  Widget build(BuildContext context) => NotificationListener<ScrollNotification>(
    onNotification: (notification) {
      if (notification.metrics.axis == Axis.horizontal) {
        if (notification is ScrollUpdateNotification && (notification.scrollDelta ?? 0) != 0) {
          _setScrolling(true);
        } else if (notification is ScrollEndNotification) {
          _setScrolling(false);
        }
      }
      return false;
    },
    child: Marquee(
      key: ValueKey(widget.text),
      text: widget.text,
      style: widget.style,
      velocity: 20,
      blankSpace: 50,
      startPadding: 0,
      showFadingOnlyWhenScrolling: true,
      fadingEdgeStartFraction: _allowFade ? .08 : 0,
      fadingEdgeEndFraction: _allowFade ? .08 : 0,
      startAfter: const Duration(seconds: 2),
      pauseAfterRound: const Duration(seconds: 2),
    ),
  );
}

/// Previews a position while dragging and seeks once when the gesture ends.
class PlayerSeekBar extends StatefulWidget {
  const PlayerSeekBar({
    super.key,
    required this.position,
    required this.duration,
    required this.playerStateStream,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final Stream<PlayerState> playerStateStream;
  final Future<void> Function(Duration) onSeek;

  @override
  State<PlayerSeekBar> createState() => _PlayerSeekBarState();
}

class _PlayerSeekBarState extends State<PlayerSeekBar> {
  double? _dragValue;
  double? _tapValue;
  bool _dragging = false;
  int _gestureGeneration = 0;
  Duration? _seekTarget;
  bool _seekFinished = false;
  Timer? _seekTimer;

  void _clearPendingSeek() {
    _seekTimer?.cancel();
    _seekTimer = null;
    _seekTarget = null;
    _seekFinished = false;
  }

  bool _positionReached(Duration target) => (widget.position - target).abs() <= const Duration(milliseconds: 500);

  @override
  void didUpdateWidget(covariant PlayerSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final target = _seekTarget;
    if (!_dragging && _seekFinished && target != null && _positionReached(target)) {
      _clearPendingSeek();
      _dragValue = null;
    }
  }

  @override
  void dispose() {
    _seekTimer?.cancel();
    super.dispose();
  }

  String _format(Duration duration) => '${duration.inMinutes}:${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

  double _valueAt(double x, double width) => width <= 0 ? 0 : (x / width).clamp(0.0, 1.0);

  Future<void> _commit(double value, int generation) async {
    final target = Duration(milliseconds: (value * widget.duration.inMilliseconds).round());
    _seekTarget = target;
    _seekFinished = false;
    try {
      await widget.onSeek(target);
    } catch (_) {
      if (mounted && generation == _gestureGeneration) {
        _clearPendingSeek();
        setState(() => _dragValue = null);
      }
      rethrow;
    }
    if (!mounted || generation != _gestureGeneration) return;
    _seekFinished = true;
    if (_positionReached(target)) {
      _clearPendingSeek();
      setState(() => _dragValue = null);
    } else {
      _seekTimer = Timer(const Duration(seconds: 1), () {
        if (!mounted || generation != _gestureGeneration) return;
        _clearPendingSeek();
        setState(() => _dragValue = null);
      });
    }
  }

  void _seekTo(double value) {
    final generation = ++_gestureGeneration;
    _clearPendingSeek();
    setState(() => _dragValue = value.clamp(0.0, 1.0));
    _commit(_dragValue!, generation);
  }

  @override
  Widget build(BuildContext context) {
    final totalMs = widget.duration.inMilliseconds;
    String fmtAt(double v) => _format(Duration(milliseconds: (v.clamp(0.0, 1.0) * totalMs).round()));
    final canSeek = totalMs > 0;
    final progress = canSeek ? (widget.position.inMilliseconds / totalMs).clamp(0.0, 1.0) : 0.0;
    final value = _dragValue ?? progress;
    final elapsed = Duration(milliseconds: (value * totalMs).round());
    final remaining = Duration(milliseconds: (totalMs - elapsed.inMilliseconds).clamp(0, totalMs > 0 ? totalMs : 0));
    final animationDuration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    final labelStyle = TextStyle(
      fontFamily: 'SpotifyMix',
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: Colors.white.withValues(alpha: .6),
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: AnimatedScale(
        scale: _dragging ? 1.03 : 1,
        duration: animationDuration,
        curve: _dragging ? Curves.easeOut : Curves.easeOutBack,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              container: true,
              excludeSemantics: true,
              label: 'Playback position',
              value: '${_format(elapsed)} of ${_format(widget.duration)}',
              increasedValue: '${fmtAt(value + .05)} of ${_format(widget.duration)}',
              decreasedValue: '${fmtAt(value - .05)} of ${_format(widget.duration)}',
              slider: true,
              onIncrease: canSeek ? () => _seekTo(value + .05) : null,
              onDecrease: canSeek ? () => _seekTo(value - .05) : null,
              child: PlayerProgressTrack(
                height: 32,
                playerStateStream: widget.playerStateStream,
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    height: 32,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth;
                        return GestureDetector(
                          excludeFromSemantics: true,
                          key: const ValueKey('player-seek-track'),
                          behavior: HitTestBehavior.opaque,
                          onTapDown: canSeek
                              ? (details) => _tapValue = _valueAt(details.localPosition.dx, width)
                              : null,
                          onTap: canSeek
                              ? () {
                                  final target = _tapValue;
                                  _tapValue = null;
                                  if (target == null) return;
                                  _seekTo(target);
                                }
                              : null,
                          onTapCancel: () => _tapValue = null,
                          onHorizontalDragStart: canSeek
                              ? (details) {
                                  HapticFeedback.selectionClick();
                                  _gestureGeneration++;
                                  _clearPendingSeek();
                                  setState(() {
                                    _dragging = true;
                                    _dragValue = _valueAt(details.localPosition.dx, width);
                                  });
                                }
                              : null,
                          onHorizontalDragUpdate: canSeek
                              ? (details) {
                                  setState(() => _dragValue = _valueAt(details.localPosition.dx, width));
                                }
                              : null,
                          onHorizontalDragEnd: canSeek
                              ? (_) {
                                  final target = _dragValue;
                                  final generation = _gestureGeneration;
                                  setState(() => _dragging = false);
                                  if (target != null) _commit(target, generation);
                                }
                              : null,
                          onHorizontalDragCancel: () {
                            _gestureGeneration++;
                            _clearPendingSeek();
                            setState(() {
                              _dragging = false;
                              _dragValue = null;
                            });
                          },
                          child: Center(
                            child: AnimatedContainer(
                              duration: animationDuration,
                              curve: Curves.easeOut,
                              height: _dragging ? 12 : 6,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .25),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: FractionallySizedBox(
                                    key: const ValueKey('player-seek-fill'),
                                    widthFactor: value,
                                    heightFactor: 1,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(alpha: .9),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            IgnorePointer(
              child: Transform.translate(
                offset: const Offset(0, -12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(_format(elapsed), style: labelStyle),
                    Text('-${_format(remaining)}', style: labelStyle),
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

enum PlayerNavType { album, artist, playlist }

class PlayerNavCommand {
  final PlayerNavType type;
  final String id;
  final int tabIndex;

  const PlayerNavCommand({required this.type, required this.id, required this.tabIndex});
}

final playerNavProvider = NotifierProvider<PlayerNavNotifier, PlayerNavCommand?>(PlayerNavNotifier.new);

class PlayerNavNotifier extends Notifier<PlayerNavCommand?> {
  @override
  PlayerNavCommand? build() => null;

  void navigate(PlayerNavCommand command) {
    state = command;
  }

  void clear() {
    state = null;
  }
}
