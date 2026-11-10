import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/components/song_credits.dart';
import 'package:hivefy/models/datamodel.dart';

Artist artist(String name) => Artist(id: name, title: name, type: 'artist', url: '', images: []);

SongDetail song({Contributors contributors = const Contributors(), String primaryArtists = '', String singers = ''}) =>
    SongDetail(
      id: 'song',
      title: 'Song',
      type: 'song',
      url: '',
      images: [],
      contributors: contributors,
      primaryArtists: primaryArtists,
      singers: singers,
    );

void main() {
  testWidgets('shows all contributors once with their supplied roles', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongCredits(
            song: song(
              contributors: Contributors(
                primary: [artist('One')],
                featured: [artist('Two')],
                all: [artist('one'), artist('Two'), artist('Three')],
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('Credits'), findsOneWidget);
    expect(find.text('One'), findsOneWidget);
    expect(find.text('Two'), findsOneWidget);
    expect(find.text('Three'), findsOneWidget);
    expect(find.text('Primary artist'), findsOneWidget);
    expect(find.text('Featured artist'), findsOneWidget);
    expect(find.text('Artist'), findsOneWidget);
  });

  testWidgets('uses available artist text and hides empty credits', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongCredits(song: song(primaryArtists: 'An Artist')),
        ),
      ),
    );
    expect(find.text('An Artist'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SongCredits(song: song())),
      ),
    );
    expect(find.text('Credits'), findsNothing);
  });

  testWidgets('opens credits with artist IDs and keeps unavailable artists inactive', (tester) async {
    String? openedId;
    final missingId = Artist(id: '', title: 'One', type: 'artist', url: '', images: []);
    final unavailable = Artist(id: '', title: 'Unknown', type: 'artist', url: '', images: []);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SongCredits(
            song: song(
              contributors: Contributors(primary: [missingId, unavailable], all: [artist('One')]),
            ),
            onArtistTap: (id) => openedId = id,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Unknown'));
    expect(openedId, isNull);
    await tester.tap(find.text('One'));
    expect(openedId, 'One');
  });
}
