import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/models/database.dart';
import 'package:hivefy/models/datamodel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('stores YouTube song metadata before a stream URL is resolved', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    final song = SongDetail(
      id: 'video',
      title: 'Track',
      type: 'song',
      url: '',
      images: [],
      primaryArtists: 'Artist',
      ytVideoId: 'video',
    );
    await AppDatabase.saveSongDetail(song);
    final loaded = await AppDatabase.getSong('video');
    expect(loaded?.title, 'Track');
    expect(loaded?.primaryArtists, 'Artist');
    expect(loaded?.ytVideoId, 'video');
    expect(loaded?.downloadUrls, isEmpty);
  });
}
