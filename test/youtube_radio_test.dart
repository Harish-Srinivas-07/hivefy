import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/services/youtube.dart';

void main() {
  test('radio queue preserves available song metadata and ignores malformed items', () {
    final item = {
      'videoId': 'video',
      'title': {
        'runs': [
          {'text': 'Song'},
        ],
      },
      'lengthText': {'simpleText': '3:12'},
      'longBylineText': {
        'runs': [
          {
            'text': 'Artist',
            'navigationEndpoint': {
              'browseEndpoint': {'browseId': 'UCartist'},
            },
          },
          {'text': ' • '},
          {
            'text': 'Album',
            'navigationEndpoint': {
              'browseEndpoint': {'browseId': 'MPREb_album'},
            },
          },
        ],
      },
      'thumbnail': {
        'thumbnails': [
          {'url': 'small'},
          {'url': 'large'},
        ],
      },
    };
    final songs = YoutubeAPI().parseRadioSongsForTesting({
      'contents': [
        {'playlistPanelVideoRenderer': item},
        {'playlistPanelVideoRenderer': item},
        {
          'playlistPanelVideoRenderer': {'videoId': 'missing-title'},
        },
      ],
    });
    expect(songs, hasLength(1));
    expect(songs.single.title, 'Song');
    expect(songs.single.primaryArtists, 'Artist');
    expect(songs.single.albumId, 'MPREb_album');
    expect(songs.single.duration, '192');
    expect(songs.single.images.single.url, 'large');
  });
}
