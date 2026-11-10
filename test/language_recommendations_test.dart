import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/models/datamodel.dart';
import 'package:hivefy/services/latest_music_fetcher.dart';
import 'package:hivefy/services/youtube.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeRecommendations extends YoutubeAPI {
  final queries = <String>[];
  bool fail = false;

  @override
  Future<SearchPlaylistsResponse?> searchPlaylists({required String query, int page = 0, int limit = 10}) async {
    queries.add('playlist:$query');
    if (fail) throw StateError('offline');
    return SearchPlaylistsResponse(
      total: 1,
      start: 0,
      results: [Playlist(id: 'VL$query', title: query, type: 'playlist', url: '', images: [])],
    );
  }

  @override
  Future<List<Album>> searchAlbums({required String query, int limit = 10}) async {
    queries.add('album:$query');
    return [Album(id: 'MPREb_$query', title: query, type: 'album', url: '', images: [])];
  }
}

void main() {
  test('fetches and caches recommendations separately for each language', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({'latest_tamil_playlists': '[{"id":"old"}]'});
    final api = FakeRecommendations();
    final tamil = await LatestMusicFetcher.getLatestPlaylists('tamil', api: api);
    final english = await LatestMusicFetcher.getLatestPlaylists('english', api: api);
    final albums = await LatestMusicFetcher.getLatestAlbums('english', api: api);
    final cached = await LatestMusicFetcher.getLatestPlaylists('tamil', api: api);
    expect(tamil.single.title, 'tamil music');
    expect(english.single.title, 'english music');
    expect(albums.single.title, 'english music');
    expect(cached.single.id, tamil.single.id);
    expect(api.queries, ['playlist:tamil music', 'playlist:english music', 'album:english music']);
  });

  test('uses cached recommendations for the same language when offline', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final api = FakeRecommendations();
    final original = await LatestMusicFetcher.getLatestPlaylists('tamil', api: api);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('yt_recommendations_v1_tamil_playlists_time', 0);
    api.fail = true;
    final fallback = await LatestMusicFetcher.getLatestPlaylists('tamil', api: api);
    expect(fallback.single.id, original.single.id);
  });
}
