import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/models/datamodel.dart';
import 'package:hivefy/services/song_artist_resolver.dart';
import 'package:hivefy/services/youtube.dart';

class FakeArtistApi extends YoutubeAPI {
  final Map<String, ArtistDetails> details = {};
  List<Artist> searchResults = [];
  final List<String> fetchedIds = [];
  final List<String> searches = [];

  @override
  Future<ArtistDetails?> fetchArtistDetailsById({
    required String artistId,
    int page = 0,
    int songCount = 10,
    int albumCount = 10,
    String sortBy = 'popularity',
    String sortOrder = 'desc',
  }) async {
    fetchedIds.add(artistId);
    return details[artistId];
  }

  @override
  Future<SearchArtistsResponse?> searchArtists({required String query, int page = 0, int limit = 10}) async {
    searches.add(query);
    return SearchArtistsResponse(total: searchResults.length, start: 0, results: searchResults);
  }
}

Artist artist(String id, String name, {String? image}) => Artist(
  id: id,
  title: name,
  type: 'artist',
  url: '',
  images: image == null ? [] : [SourceUrl(quality: 'default', url: image)],
);

ArtistDetails details(String id, String name, {String? image}) => ArtistDetails(
  id: id,
  title: name,
  type: 'artist',
  url: '',
  images: image == null ? [] : [SourceUrl(quality: 'default', url: image)],
  bio: const ['Biography'],
  followerCount: 100,
);

SongDetail song({String name = '', Contributors contributors = const Contributors()}) => SongDetail(
  id: 'song',
  title: 'Track',
  type: 'song',
  url: '',
  images: [],
  primaryArtists: name,
  contributors: contributors,
);

void main() {
  test('uses the primary contributor instead of the first combined contributor', () async {
    final api = FakeArtistApi()..details['primary'] = details('primary', 'Main artist', image: 'main-image');
    final result = await resolveSongArtist(
      song(
        name: 'Main artist',
        contributors: Contributors(
          primary: [artist('primary', 'Main artist')],
          all: [artist('featured', 'Guest'), artist('primary', 'Main artist')],
        ),
      ),
      api,
    );
    expect(api.fetchedIds, ['primary']);
    expect(result?.images.single.url, 'main-image');
  });

  test('finds a matching primary name in a combined contributor list', () async {
    final api = FakeArtistApi()..details['main'] = details('main', 'Main artist', image: 'main-image');
    final result = await resolveSongArtist(
      song(
        name: 'Main artist, Guest',
        contributors: Contributors(all: [artist('guest', 'Guest'), artist('main', 'Main artist')]),
      ),
      api,
    );
    expect(result?.id, 'main');
    expect(api.fetchedIds, ['main']);
  });

  test('uses only an unambiguous exact artist search when an ID is missing', () async {
    final api = FakeArtistApi()
      ..details['main'] = details('main', 'Main artist', image: 'portrait')
      ..searchResults = [artist('other', 'Main artist cover'), artist('main', 'Main artist - Topic')];
    final result = await resolveSongArtist(song(name: 'Main artist'), api);
    expect(result?.id, 'main');
    expect(api.searches, ['Main artist']);
    api.searchResults = [artist('main', 'Main artist'), artist('other', 'Main artist')];
    expect(await resolveSongArtist(song(name: 'Main artist'), api), isNull);
  });

  test('uses a search image only when it belongs to the same artist ID', () async {
    final api = FakeArtistApi()
      ..details['main'] = details('main', 'Main artist')
      ..searchResults = [
        artist('other', 'Main artist', image: 'wrong'),
        artist('main', 'Main artist', image: 'correct'),
      ];
    final result = await resolveSongArtist(
      song(
        name: 'Main artist',
        contributors: Contributors(primary: [artist('main', 'Main artist')]),
      ),
      api,
    );
    expect(result?.images.single.url, 'correct');
    expect(result?.bio, ['Biography']);
    expect(result?.followerCount, 100);
  });

  test('ignores artist details whose name does not match the selected contributor', () async {
    final api = FakeArtistApi()..details['main'] = details('main', 'Someone else', image: 'wrong');
    expect(
      await resolveSongArtist(
        song(
          name: 'Main artist',
          contributors: Contributors(primary: [artist('main', 'Main artist')]),
        ),
        api,
      ),
      isNull,
    );
  });
}
