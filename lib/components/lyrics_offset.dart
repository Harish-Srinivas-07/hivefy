import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/theme.dart';
import 'sheet_surface.dart';

void showLyricsOffsetSheet(BuildContext context, {required String songId}) {
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: SheetSurface(child: LyricsOffsetSheet(songId: songId)),
    ),
  );
}

final lyricsOffsetProvider = Provider.autoDispose.family<ValueNotifier<int>, String>((ref, songId) {
  final notifier = ValueNotifier<int>(0);
  var disposed = false;
  var edited = false;
  void markEdited() => edited = true;
  notifier.addListener(markEdited);
  SharedPreferences.getInstance().then((prefs) {
    if (!disposed && !edited) {
      notifier.removeListener(markEdited);
      notifier.value = prefs.getInt('lyrics_offset_$songId') ?? 0;
      notifier.addListener(markEdited);
    }
  });
  ref.onDispose(() {
    disposed = true;
    notifier.dispose();
  });
  return notifier;
});

class LyricsOffsetSheet extends ConsumerStatefulWidget {
  const LyricsOffsetSheet({super.key, required this.songId});
  final String songId;

  @override
  ConsumerState<LyricsOffsetSheet> createState() => _LyricsOffsetSheetState();
}

class _LyricsOffsetSheetState extends ConsumerState<LyricsOffsetSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String? _error;

  String _formatMilliseconds(int value) =>
      (value / 1000).toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');

  void _step(int fallback, int delta) {
    final entered = double.tryParse(_controller.text.trim());
    final current = entered != null && entered.isFinite && entered >= -60 && entered <= 60
        ? (entered * 1000).round()
        : fallback;
    _setOffset(current + delta);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _setOffset(int milliseconds) {
    final clamped = milliseconds.clamp(-60000, 60000);
    ref.read(lyricsOffsetProvider(widget.songId)).value = clamped;
    SharedPreferences.getInstance().then((prefs) => prefs.setInt('lyrics_offset_${widget.songId}', clamped));
    _controller.text = _formatMilliseconds(clamped);
    setState(() => _error = null);
  }

  void _save() {
    final seconds = double.tryParse(_controller.text.trim());
    if (seconds == null || !seconds.isFinite || seconds < -60 || seconds > 60) {
      setState(() => _error = 'Enter a value from -60 to 60 seconds');
      return;
    }
    _setOffset((seconds * 1000).round());
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.watch(lyricsOffsetProvider(widget.songId));
    return ValueListenableBuilder<int>(
      valueListenable: notifier,
      builder: (context, milliseconds, _) {
        if (!_focus.hasFocus) _controller.text = _formatMilliseconds(milliseconds);
        return AnimatedPadding(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Padding(
                        padding: EdgeInsets.only(top: 10, bottom: 16),
                        child: Center(
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
                      ),
                      const Text(
                        'Lyrics offset',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Positive values show lyrics later.',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton.filled(
                            tooltip: 'Decrease offset',
                            onPressed: () => _step(milliseconds, -500),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white12,
                              fixedSize: const Size(48, 48),
                              shape: const CircleBorder(),
                            ),
                            icon: const Icon(Icons.remove, color: Colors.white),
                          ),
                          const SizedBox(width: 16),
                          SizedBox(
                            width: 120,
                            child: TextField(
                              controller: _controller,
                              focusNode: _focus,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white),
                              keyboardType: const TextInputType.numberWithOptions(signed: true, decimal: true),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]'))],
                              decoration: const InputDecoration(
                                suffixText: 's',
                                suffixStyle: TextStyle(color: Colors.white70),
                              ),
                              onSubmitted: (_) => _save(),
                            ),
                          ),
                          const SizedBox(width: 16),
                          IconButton.filled(
                            tooltip: 'Increase offset',
                            onPressed: () => _step(milliseconds, 500),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.white12,
                              fixedSize: const Size(48, 48),
                              shape: const CircleBorder(),
                            ),
                            icon: const Icon(Icons.add, color: Colors.white),
                          ),
                        ],
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                        ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _save,
                          style: FilledButton.styleFrom(
                            backgroundColor: spotifyGreen,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Done'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
