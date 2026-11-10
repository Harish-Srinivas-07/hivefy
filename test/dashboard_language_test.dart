import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/models/datamodel.dart';
import 'package:hivefy/screens/dashboard.dart';
import 'package:hivefy/screens/features/language.dart';
import 'package:hivefy/services/youtube.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DelayedRecommendations extends YoutubeAPI {
  final tamilRequests = Completer<void>();
  final queries = <String>[];
  Future<void> waitForQuery(String query) async {
    queries.add(query);
    if (query.startsWith('tamil')) await tamilRequests.future;
  }

  @override
  Future<SearchPlaylistsResponse?> searchPlaylists({required String query, int page = 0, int limit = 10}) async {
    await waitForQuery(query);
    return SearchPlaylistsResponse(
      total: 1,
      start: 0,
      results: [
        Playlist(id: 'VL$query', title: '$query playlist', type: 'playlist', url: '', images: [], summary: 'Playlist'),
      ],
    );
  }

  @override
  Future<List<Album>> searchAlbums({required String query, int limit = 10}) async {
    await waitForQuery(query);
    return [Album(id: 'MPREb_$query', title: '$query album', type: 'album', url: '', images: [])];
  }

  @override
  Future<SearchArtistsResponse?> searchArtists({required String query, int page = 0, int limit = 10}) async {
    await waitForQuery(query);
    return SearchArtistsResponse(total: 0, start: 0, results: []);
  }
}

void main() {
  testWidgets('home refreshes after language changes and ignores older results', (tester) async {
    SharedPreferences.setMockInitialValues({'app_language': 'tamil'});
    final api = DelayedRecommendations();
    final container = ProviderContainer(
      overrides: [
        dashboardApiProvider.overrideWithValue(api),
        dashboardConnectionProvider.overrideWithValue(const Stream<InternetStatus>.empty()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: Dashboard()),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(api.queries, contains('tamil music'));

    container.read(languageNotifierProvider).value = ['english'];
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('english music playlist'), findsWidgets);
    api.tamilRequests.complete();
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('english music playlist'), findsWidgets);
    expect(find.text('tamil music playlist'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 4));
  });
}
