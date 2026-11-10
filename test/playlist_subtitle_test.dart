import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/models/datamodel.dart';
import 'package:hivefy/utils/playlist_subtitle.dart';

void main() {
  test('removes YouTube Music while keeping other playlist details', () {
    expect(cleanPlaylistSubtitle('YouTube Music • 45 songs'), '45 songs');
    expect(cleanPlaylistSubtitle('45 songs • youtube music • 2026'), '45 songs • 2026');
    expect(cleanPlaylistSubtitle('YouTube Music'), isEmpty);
    expect(cleanPlaylistSubtitle('Other creator • 10 songs'), 'Other creator • 10 songs');
  });

  test('home playlist counts are readable and preserve available details', () {
    Playlist playlist({int? count, String summary = ''}) =>
        Playlist(id: 'id', title: 'Title', type: 'playlist', url: '', images: [], songCount: count, summary: summary);

    expect(songCountLabel(0), 'No songs');
    expect(songCountLabel(1), '1 song');
    expect(songCountLabel(2), '2 songs');
    expect(homePlaylistSubtitle(playlist(count: 0, summary: 'YouTube Music • 0 songs')), 'No songs');
    expect(homePlaylistSubtitle(playlist(summary: '0 songs')), 'No songs');
    expect(homePlaylistSubtitle(playlist(count: 1, summary: 'My mix • 1 song')), '1 song • My mix');
    expect(homePlaylistSubtitle(playlist(count: 25, summary: 'My mix')), '25 songs • My mix');
    expect(homePlaylistSubtitle(playlist()), 'Playlist');
  });
}
