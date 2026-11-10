import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/components/playback_artwork.dart';
import 'package:hivefy/components/player_glass_background.dart';

void main() {
  test('artwork transition target matches the full-bleed layout', () {
    final rect = fullPlayerArtworkRect(const Size(320, 700), const EdgeInsets.only(top: 24));
    expect(rect, const Rect.fromLTWH(0, 0, 320, 320));
  });

  testWidgets('loading player background follows the current artwork', (tester) async {
    Widget player(String artwork) => MaterialApp(
      home: PlayerGlassBackground(
        color: Colors.blueGrey,
        artworkUrl: artwork,
        child: const Center(child: CircularProgressIndicator()),
      ),
    );

    await tester.pumpWidget(player('https://example.com/first.jpg'));
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage)).imageUrl, endsWith('first.jpg'));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    await tester.pumpWidget(player('https://example.com/second.jpg'));
    expect(tester.widget<CachedNetworkImage>(find.byType(CachedNetworkImage)).imageUrl, endsWith('second.jpg'));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('lyrics edge uses a single clipped backdrop blur', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SizedBox(width: 64, height: 64, child: PlayerArtworkEdge())),
      ),
    );

    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(ClipRect), findsWidgets);
  });

  testWidgets('glass background fits a compact player with unbounded height', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              PlayerGlassBackground(
                color: Colors.black,
                artworkUrl: 'https://example.com/artwork.jpg',
                child: const SizedBox(key: ValueKey('mini-content'), height: 56, width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.getSize(find.byType(PlayerGlassBackground)).height, 56);
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('artwork grows for playback and shrinks when paused', (tester) async {
    Widget build(bool playing) => MaterialApp(
      home: Scaffold(
        body: PlaybackArtwork(isPlaying: playing, child: const SizedBox(width: 200, height: 200)),
      ),
    );
    await tester.pumpWidget(build(false));
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 0.85);
    await tester.pumpWidget(build(true));
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1.0);
    await tester.pumpAndSettle();
    await tester.pumpWidget(build(false));
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 0.85);
  });
}
