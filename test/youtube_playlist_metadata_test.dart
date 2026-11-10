import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/services/youtube.dart';
import 'package:hivefy/models/datamodel.dart';

void main() {
  test('keeps the playlist creator and count returned in search', () {
    final metadata = YoutubeAPI().parsePlaylistMetadataForTesting({
      'flexColumns': [
        {},
        {
          'musicResponsiveListItemFlexColumnRenderer': {
            'text': {
              'runs': [
                {'text': 'YouTube Music'},
                {'text': ' • '},
                {'text': '1,245 songs'},
              ],
            },
          },
        },
      ],
    });
    expect(metadata.subtitle, 'YouTube Music • 1,245 songs');
    expect(metadata.songCount, 1245);
  });

  test('does not invent a song count when one is absent', () {
    final metadata = YoutubeAPI().parsePlaylistMetadataForTesting({});
    expect(metadata.subtitle, isEmpty);
    expect(metadata.songCount, isNull);
  });

  test('uses the playlist header total instead of the number of loaded tracks', () {
    final metadata = YoutubeAPI().parsePlaylistHeaderForTesting({
      'straplineTextOne': {
        'runs': [
          {'text': 'YouTube Music'},
        ],
      },
      'subtitle': {
        'runs': [
          {'text': 'Playlist • 2026'},
        ],
      },
      'secondSubtitle': {
        'runs': [
          {'text': '43 songs • 3 hours'},
        ],
      },
      'description': {
        'musicDescriptionShelfRenderer': {
          'description': {
            'runs': [
              {'text': 'Essential tracks.'},
            ],
          },
        },
      },
    });
    expect(metadata.subtitle, 'YouTube Music • Playlist • 2026 • 43 songs • 3 hours');
    expect(metadata.songCount, 43);
    expect(metadata.description, 'Essential tracks.');
    final playlist = Playlist(
      id: 'p',
      title: 'Mix',
      type: 'playlist',
      url: '',
      images: [],
      summary: metadata.subtitle,
      description: metadata.description,
      songCount: metadata.songCount,
    );
    final restored = Playlist.fromJson(Playlist.playlistToJson(playlist));
    expect(restored.summary, metadata.subtitle);
    expect(restored.description, 'Essential tracks.');
  });
}
