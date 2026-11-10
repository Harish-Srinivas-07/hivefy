import 'dart:io';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/services/chunk_downloader.dart';

void main() {
  test('downloads bounded ranges and refreshes an expired URL at the same offset', () async {
    final bytes = List<int>.generate(11, (i) => i);
    final ranges = <String>[];
    final agents = <String?>[];
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final dir = await Directory.systemTemp.createTemp('hivefy_range_test_');
    final dio = Dio();
    addTearDown(() async {
      dio.close();
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    server.listen((request) async {
      final range = request.headers.value('range')!;
      ranges.add(range);
      agents.add(request.headers.value('user-agent'));
      final match = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
      final start = int.parse(match.group(1)!);
      final end = math.min(int.parse(match.group(2)!), bytes.length - 1);
      if (request.uri.path == '/expired' && start == 4) {
        request.response.statusCode = 403;
      } else {
        request.response.statusCode = 206;
        request.response.headers.set('content-range', 'bytes $start-$end/${bytes.length}');
        request.response.add(bytes.sublist(start, end + 1));
      }
      await request.response.close();
    });
    final base = 'http://127.0.0.1:${server.port}';
    final progress = <int>[];
    final file = File('${dir.path}/audio.part');
    await ChunkDownloader(dio: dio, userAgent: 'vision-test', chunkSize: 4).download(
      source: AudioDownloadSource(url: '$base/expired', itag: 140, length: null, extension: 'm4a'),
      destination: file,
      refresh: (itag) async => AudioDownloadSource(url: '$base/fresh', itag: itag, length: 11, extension: 'm4a'),
      onProgress: (received, total) => progress.add(received),
    );
    expect(await file.readAsBytes(), bytes);
    expect(ranges, ['bytes=0-3', 'bytes=4-7', 'bytes=4-7', 'bytes=8-10']);
    expect(agents, everyElement('vision-test'));
    expect(progress, [4, 8, 11]);
  });

  test('rejects an error response instead of treating it as an audio file', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final dir = await Directory.systemTemp.createTemp('hivefy_range_test_');
    final dio = Dio();
    addTearDown(() async {
      dio.close();
      await server.close(force: true);
      await dir.delete(recursive: true);
    });
    server.listen((request) async {
      request.response.statusCode = 404;
      request.response.write('Not found');
      await request.response.close();
    });
    await expectLater(
      ChunkDownloader(dio: dio, userAgent: 'vision-test', chunkSize: 4).download(
        source: AudioDownloadSource(
          url: 'http://127.0.0.1:${server.port}/audio',
          itag: 140,
          length: 11,
          extension: 'm4a',
        ),
        destination: File('${dir.path}/audio.part'),
        refresh: (_) async => null,
      ),
      throwsStateError,
    );
  });
}
