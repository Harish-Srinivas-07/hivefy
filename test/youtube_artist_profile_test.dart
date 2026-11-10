import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/services/youtube.dart';

void main() {
  test('reads artist biography and subscriber count from the browse header', () {
    final profile = YoutubeAPI().parseArtistProfileForTesting({
      'header': {
        'musicImmersiveHeaderRenderer': {
          'description': {
            'runs': [
              {'text': 'A band.'},
              {'text': ' More.'},
            ],
          },
          'subscriptionButton': {
            'subscribeButtonRenderer': {
              'subscriberCountText': {
                'runs': [
                  {'text': '28.7M'},
                ],
              },
            },
          },
        },
      },
    });
    expect(profile.biography, 'A band. More.');
    expect(profile.subscribers, 28700000);
  });

  test('uses the about shelf if the header has no biography', () {
    final profile = YoutubeAPI().parseArtistProfileForTesting({
      'contents': [
        {
          'musicDescriptionShelfRenderer': {
            'description': {
              'runs': [
                {'text': 'Biography'},
              ],
            },
          },
        },
      ],
    });
    expect(profile.biography, 'Biography');
    expect(profile.subscribers, isNull);
  });
}
