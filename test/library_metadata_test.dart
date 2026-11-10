import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/models/datamodel.dart';
import 'package:hivefy/utils/library_metadata.dart';

void main() {
  Album album({String artist = '', List<Artist> artists = const [], List<SongDetail> songs = const []}) => Album(
    id: 'id',
    title: 'Album',
    type: 'album',
    url: '',
    images: [],
    artist: artist,
    artists: artists,
    songs: songs,
  );

  test('uses the album artist field when no artist list is present', () {
    expect(albumArtistName(album(artist: 'Coldplay')), 'Coldplay');
    expect(albumArtistName(album(artist: 'Album')), isEmpty);
  });

  test('uses a shared song artist and avoids guessing for compilations', () {
    SongDetail song(String id, String artist) =>
        SongDetail(id: id, title: id, type: 'song', url: '', images: [], primaryArtists: artist);
    expect(albumArtistName(album(songs: [song('1', 'Coldplay'), song('2', 'Coldplay')])), 'Coldplay');
    expect(albumArtistName(album(songs: [song('1', 'Coldplay'), song('2', 'Other')])), isEmpty);
  });

  test('uses available playlist metadata instead of an unknown artist', () {
    final playlist = Playlist(
      id: 'p',
      title: 'Mix',
      type: 'playlist',
      url: '',
      images: [],
      description: 'YouTube Music • 45 songs',
    );
    expect(playlistLibrarySubtitle(playlist), '45 songs');
    expect(playlistLibrarySubtitle(Playlist(id: 'p', title: 'Mix', type: 'playlist', url: '', images: [])), 'Playlist');
  });
}
