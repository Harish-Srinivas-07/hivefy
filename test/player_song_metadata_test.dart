import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/models/datamodel.dart';
import 'package:hivefy/utils/song_metadata.dart';

void main() {
  test('player subtitle includes all unique contributors and the album', () {
    Artist artist(String name) => Artist(id: name, title: name, type: 'artist', url: '', images: []);
    final song = SongDetail(
      id: 'id',
      title: 'Track',
      type: 'song',
      url: '',
      images: [],
      contributors: Contributors(all: [artist('Artist A'), artist('Artist B'), artist('Artist A')]),
      albumName: 'Album',
    );
    expect(playerSongSubtitle(song), 'Artist A, Artist B • Album');
  });

  test('player subtitle uses available metadata without empty separators', () {
    final song = SongDetail(id: 'id', title: 'Track', type: 'song', url: '', images: [], primaryArtists: 'Artist');
    expect(playerSongSubtitle(song), 'Artist');
  });
}
