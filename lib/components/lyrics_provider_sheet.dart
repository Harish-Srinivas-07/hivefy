import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../models/datamodel.dart';
import '../services/lyrics.dart';
import '../shared/constants.dart';
import 'sheet_surface.dart';

class LyricsProviderSheet extends ConsumerStatefulWidget {
  const LyricsProviderSheet({super.key, required this.song, required this.currentLyrics});
  final SongDetail song;
  final Lyrics currentLyrics;

  @override
  ConsumerState<LyricsProviderSheet> createState() => _LyricsProviderSheetState();
}

class _LyricsProviderSheetState extends ConsumerState<LyricsProviderSheet> {
  LyricsProvider? _loading;
  final Set<LyricsProvider> _unavailable = {};
  bool _closing = false;

  Future<void> _select(LyricsProvider provider) async {
    if (_loading != null || _unavailable.contains(provider)) return;
    if (provider.label == widget.currentLyrics.source) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _loading = provider);
    final service = ref.read(lyricsServiceProvider);
    Lyrics? result;
    try {
      result = await service.fetch(widget.song, provider: provider);
    } catch (_) {
      result = null;
    }
    if (!mounted ||
        _closing ||
        ModalRoute.of(context)?.isCurrent != true ||
        ref.read(currentSongProvider)?.id != widget.song.id) {
      return;
    }
    if (result == null) {
      setState(() {
        _loading = null;
        _unavailable.add(provider);
      });
      return;
    }
    ref.read(selectedLyricsProvider(widget.song.id).notifier).state = result;
    try {
      await service.saveSelection(widget.song, result);
    } catch (_) {
      // The chosen lyrics still work for this session if storage is unavailable.
    }
    if (mounted && !_closing && ModalRoute.of(context)?.isCurrent == true) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<SongDetail?>(currentSongProvider, (previous, next) {
      if (next?.id != widget.song.id && !_closing) {
        _closing = true;
        Navigator.of(context).pop();
      }
    });
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: Stack(
        children: [
          Positioned.fill(child: const SheetSurface(child: SizedBox.expand())),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Center(
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
                  const SizedBox(height: 18),
                  const Text(
                    'Lyrics provider',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final provider in LyricsProvider.values)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            minVerticalPadding: 0,
                            visualDensity: const VisualDensity(vertical: -2),
                            titleAlignment: ListTileTitleAlignment.center,
                            enabled: _loading == null && !_unavailable.contains(provider),
                            onTap: () => _select(provider),
                            title: Text(
                              provider.label,
                              style: TextStyle(
                                color: _unavailable.contains(provider) ? Colors.white38 : Colors.white,
                                fontSize: 15,
                              ),
                            ),
                            subtitle: provider.label == widget.currentLyrics.source
                                ? const Text('Current provider', style: TextStyle(color: Colors.white70, fontSize: 12))
                                : _unavailable.contains(provider)
                                ? const Text('Not available', style: TextStyle(color: Colors.white38, fontSize: 12))
                                : null,
                            trailing: _loading == provider
                                ? Shimmer.fromColors(
                                    baseColor: Colors.white38,
                                    highlightColor: Colors.white,
                                    enabled: !MediaQuery.disableAnimationsOf(context),
                                    child: const Text('Checking…', style: TextStyle(color: Colors.white, fontSize: 13)),
                                  )
                                : provider.label == widget.currentLyrics.source
                                ? const Icon(Icons.check_circle, color: Colors.white)
                                : null,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
