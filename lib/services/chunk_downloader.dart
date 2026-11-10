import 'dart:io';
import 'dart:math' as math;
import 'package:dio/dio.dart';

class AudioDownloadSource {
  final String url;
  final int itag;
  final int? length;
  final String extension;
  const AudioDownloadSource({required this.url, required this.itag, required this.length, required this.extension});
}

/// Downloads one rendition in bounded ranges, validating each response before writing.
class ChunkDownloader {
  final Dio dio;
  final String userAgent;
  final int chunkSize;
  ChunkDownloader({required this.dio, required this.userAgent, this.chunkSize = 1024 * 1024});

  Future<void> download({
    required AudioDownloadSource source,
    required File destination,
    required Future<AudioDownloadSource?> Function(int itag) refresh,
    void Function(int received, int total)? onProgress,
  }) async {
    if (chunkSize <= 0) throw ArgumentError.value(chunkSize, 'chunkSize');
    var current = source;
    int? total = source.length;
    if (total != null && total <= 0) total = null;
    var offset = 0;
    var refreshes = 0;
    final output = await destination.open(mode: FileMode.write);
    try {
      while (total == null || offset < total) {
        final end = total == null ? offset + chunkSize - 1 : math.min(offset + chunkSize - 1, total - 1);
        final response = await dio.get<List<int>>(
          current.url,
          options: Options(
            responseType: ResponseType.bytes,
            headers: {'Range': 'bytes=$offset-$end', 'User-Agent': userAgent, 'Accept-Encoding': 'identity'},
            validateStatus: (_) => true,
            receiveTimeout: const Duration(seconds: 45),
          ),
        );
        if ((response.statusCode == 403 || response.statusCode == 401) && refreshes < 3) {
          final replacement = await refresh(source.itag);
          if (replacement == null ||
              replacement.itag != source.itag ||
              (total != null && replacement.length != null && replacement.length != total)) {
            throw StateError('Unable to refresh the same audio rendition');
          }
          current = replacement;
          refreshes++;
          continue;
        }
        final bytes = response.data ?? const <int>[];
        final range = response.headers.value('content-range');
        final match = range == null ? null : RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(range);
        if (response.statusCode == 206 && match != null) {
          final start = int.parse(match.group(1)!);
          final last = int.parse(match.group(2)!);
          final responseTotal = int.parse(match.group(3)!);
          if (start != offset ||
              last != math.min(end, responseTotal - 1) ||
              bytes.length != last - start + 1 ||
              (total != null && total != responseTotal)) {
            throw StateError('Invalid media range response');
          }
          total = responseTotal;
        } else if (response.statusCode == 200 &&
            offset == 0 &&
            total != null &&
            total <= chunkSize &&
            bytes.length == total) {
          // A server may return the complete file for a range covering all of it.
        } else {
          throw StateError('Media request failed or ignored the requested range (HTTP ${response.statusCode})');
        }
        await output.writeFrom(bytes);
        offset += bytes.length;
        onProgress?.call(offset, total);
      }
      await output.flush();
    } finally {
      await output.close();
    }
  }
}
