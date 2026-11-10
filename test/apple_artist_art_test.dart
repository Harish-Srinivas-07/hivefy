import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/services/apple_artist_art.dart';

Dio _fakeApple({required String page, String track = 'Chaleya (From "Jawan")'}) {
  return Dio()..httpClientAdapter = _AppleAdapter(page: page, track: track);
}

class _AppleAdapter implements HttpClientAdapter {
  _AppleAdapter({required this.page, required this.track});
  final String page;
  final String track;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final Object data;
    if (options.path.contains('/search')) {
      data = {
        'results': [
          {
            'artistName': 'Anirudh Ravichander',
            'artistId': 480976476,
            'artistLinkUrl': 'https://music.apple.com/us/artist/anirudh-ravichander/480976476',
          },
        ],
      };
    } else if (options.path.contains('/lookup')) {
      data = {
        'results': [
          {'trackName': track},
        ],
      };
    } else {
      data = page;
    }
    return ResponseBody.fromString(
      data is String ? data : jsonEncode(data),
      200,
      headers: {
        Headers.contentTypeHeader: [data is String ? 'text/html; charset=utf-8' : 'text/javascript; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  test('uses the matched artist header and resolves its Apple artwork template', () async {
    final data = {
      'data': [
        {
          'data': {
            'sections': [
              {
                'itemKind': 'artistDetailHeader',
                'items': [
                  {
                    'id': '480976476',
                    'wideArtwork': {
                      'dictionary': {'url': 'https://is1-ssl.mzstatic.com/image/artist/{w}x{h}{c}.{f}'},
                    },
                    'artistLogo': {
                      'dictionary': {'url': 'https://is1-ssl.mzstatic.com/image/logo/{w}x{h}{c}.{f}'},
                    },
                  },
                ],
              },
            ],
          },
        },
      ],
    };
    final repo = AppleArtistArtRepository(
      dio: _fakeApple(page: '<script id="serialized-server-data" type="application/json">${jsonEncode(data)}</script>'),
    );
    final art = await repo.artFor(
      browseId: 'UCartist',
      artistName: 'Anirudh Ravichander',
      catalogueTitles: ['Chaleya'],
    );
    expect(art?.heroUrl, 'https://is1-ssl.mzstatic.com/image/artist/1200x1200bb.jpg');
    expect(art?.logoUrl, 'https://is1-ssl.mzstatic.com/image/logo/1000x1000bb.png');
  });

  test('uses public artist image metadata when structured header data is unavailable', () async {
    final repo = AppleArtistArtRepository(
      dio: _fakeApple(page: '<meta property="og:image" content="https://is1-ssl.mzstatic.com/image/artist.jpg">'),
    );
    final art = await repo.artFor(
      browseId: 'UCartist',
      artistName: 'Anirudh Ravichander',
      catalogueTitles: ['Chaleya'],
    );
    expect(art?.heroUrl, 'https://is1-ssl.mzstatic.com/image/artist.jpg');
  });

  test('does not use artwork when the catalogue does not match', () async {
    final repo = AppleArtistArtRepository(
      dio: _fakeApple(
        page: '<meta property="og:image" content="https://is1-ssl.mzstatic.com/image/artist.jpg">',
        track: 'Unrelated song',
      ),
    );
    final art = await repo.artFor(
      browseId: 'UCartist',
      artistName: 'Anirudh Ravichander',
      catalogueTitles: ['Chaleya'],
    );
    expect(art, isNull);
  });
}
