import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/models/datamodel.dart';
import 'package:hivefy/screens/views/playlistviewer.dart';

void main() {
  testWidgets('similar playlists use two columns and flow onto the next row', (tester) async {
    final playlists = List.generate(
      3,
      (index) => Playlist(id: '$index', title: 'Playlist $index', type: 'playlist', url: '', images: []),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SimilarPlaylistsSection(
              playlists: playlists,
              cardBuilder: (playlist) => Text(playlist.title, key: ValueKey('card-${playlist.id}')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final first = tester.getTopLeft(find.byKey(const ValueKey('card-0')));
    final second = tester.getTopLeft(find.byKey(const ValueKey('card-1')));
    final third = tester.getTopLeft(find.byKey(const ValueKey('card-2')));
    expect(second.dy, first.dy);
    expect(second.dx, greaterThan(first.dx));
    expect(third.dx, first.dx);
    expect(third.dy, greaterThan(first.dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty recommendations do not show a heading', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SimilarPlaylistsSection(playlists: const [], cardBuilder: (_) => const SizedBox()),
      ),
    );
    expect(find.text('You might also like'), findsNothing);
  });
}
