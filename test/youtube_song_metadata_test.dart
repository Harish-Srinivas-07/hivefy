import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/models/datamodel.dart';
import 'package:hivefy/services/youtube.dart';

void main() {
  test('retains artist and album metadata from a music search result', () {
    Map<String, dynamic> run(String text, String id) => {
      'text': text,
      'navigationEndpoint': {
        'browseEndpoint': {'browseId': id},
      },
    };
    Map<String, dynamic> column(List<Object> runs) => {
      'musicResponsiveListItemFlexColumnRenderer': {
        'text': {'runs': runs},
      },
    };
    final item = {
      'musicResponsiveListItemRenderer': {
        'playlistItemData': {'videoId': 'video123'},
        'flexColumns': [
          column([
            {'text': 'Yellow'},
          ]),
          column([
            run('Coldplay', 'UCartist'),
            {'text': ' • '},
            run('Parachutes', 'MPREb_album'),
            {'text': ' • '},
            {'text': '4:27'},
          ]),
        ],
      },
    };

    final song = YoutubeAPI().parseSongItemForTesting(item)!;
    expect(song.primaryArtists, 'Coldplay');
    expect(song.contributors.all.single.id, 'UCartist');
    expect(song.albumName, 'Parachutes');
    expect(song.albumId, 'MPREb_album');
    expect(song.duration, '267');

    final restored = SongDetail.fromJson(SongDetail.songDetailToJson(song));
    expect(restored.albumId, 'MPREb_album');
    expect(restored.contributors.all.single.title, 'Coldplay');
  });

  test('reads album metadata from a separate playlist track column', () {
    final song = YoutubeAPI().parseSongItemForTesting({
      'musicResponsiveListItemRenderer': {
        'playlistItemData': {'videoId': 'v'},
        'flexColumns': [
          {
            'musicResponsiveListItemFlexColumnRenderer': {
              'text': {
                'runs': [
                  {'text': 'Track'},
                ],
              },
            },
          },
          {
            'musicResponsiveListItemFlexColumnRenderer': {
              'text': {
                'runs': [
                  {
                    'text': 'Artist',
                    'navigationEndpoint': {
                      'browseEndpoint': {'browseId': 'UCartist'},
                    },
                  },
                ],
              },
            },
          },
          {
            'musicResponsiveListItemFlexColumnRenderer': {
              'text': {
                'runs': [
                  {
                    'text': 'Album name',
                    'navigationEndpoint': {
                      'browseEndpoint': {'browseId': 'MPREb_album'},
                    },
                  },
                ],
              },
            },
          },
        ],
      },
    })!;
    expect(song.primaryArtists, 'Artist');
    expect(song.albumName, 'Album name');
    expect(song.albumId, 'MPREb_album');
  });
}
