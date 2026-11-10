import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/screens/library.dart';
import 'package:hivefy/screens/views/songsviewer.dart';
import 'package:hivefy/screens/search.dart';
import 'package:hivefy/models/datamodel.dart';
import 'package:hivefy/services/youtube.dart';
import 'package:hivefy/services/offlinemanager.dart';
import 'package:hivefy/utils/theme.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EmptySearchApi extends YoutubeAPI {
  @override
  Future<List<String>> getSearchBoxSuggestions({required String query}) async => [];
  @override
  Future<List<SongDetail>> searchSongs({required String query, int page = 0, int limit = 50}) async => [];
  @override
  Future<List<Album>> searchAlbums({required String query, int limit = 10}) async => [];
  @override
  Future<SearchArtistsResponse?> searchArtists({required String query, int page = 0, int limit = 10}) async => null;
  @override
  Future<SearchPlaylistsResponse?> searchPlaylists({required String query, int page = 0, int limit = 10}) async => null;
}

void main() {
  testWidgets('search shows a no-results state only after submitting an empty result', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(home: Search(searchApi: EmptySearchApi())),
      ),
    );
    await tester.pump();
    expect(find.text('Play what you love'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('search_input')), 'missing song');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();
    await tester.pump();
    expect(find.text('No results found'), findsOneWidget);
    expect(find.text('Try a different search or check your spelling.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('liked and downloaded empty pages show guidance and a back button', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await offlineManager.init();
    tester.view.physicalSize = const Size(320, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> show(SongsViewer viewer) async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(ProviderScope(child: MaterialApp(home: viewer)));
      await tester.pump();
      await tester.pump();
    }

    await show(const SongsViewer(showLikedSongs: true));
    expect(find.text('No liked songs yet'), findsOneWidget);
    expect(find.text('Songs you like will appear here.'), findsOneWidget);
    expect(find.byIcon(LucideIcons.heart), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    expect(tester.takeException(), isNull);

    await show(const SongsViewer(showDownloadedSongs: true));
    expect(find.text('No downloaded songs yet'), findsOneWidget);
    expect(find.text('Download songs to listen when you are offline.'), findsOneWidget);
    expect(find.byIcon(LucideIcons.download), findsOneWidget);
    expect(find.byType(BackButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('downloaded library artwork uses a larger icon on dark green', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LibraryCard(
            id: 'h_downloaded',
            title: 'Downloaded Songs',
            count: 0,
            fallbackColor: downloadedArtworkColor,
            type: LibraryItemType.downloadedSongs,
          ),
        ),
      ),
    );
    final icon = tester.widget<Icon>(find.byIcon(Icons.download_for_offline_rounded));
    expect(icon.size, 36);
    expect(icon.color, Colors.white);
    final box = tester.widget<Container>(
      find.ancestor(of: find.byIcon(Icons.download_for_offline_rounded), matching: find.byType(Container)).first,
    );
    expect((box.decoration! as BoxDecoration).color, downloadedArtworkColor);
  });
}
