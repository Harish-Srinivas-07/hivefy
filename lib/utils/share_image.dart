import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/datamodel.dart';
import 'theme.dart';

Future<Uint8List?> generateCustomShareImage(SongMediaItem item) async {
  try {
    final imageUrl = item.images.isNotEmpty ? item.images.last.url : null;
    if (imageUrl == null || imageUrl.isEmpty) return null;

    final provider = CachedNetworkImageProvider(imageUrl);
    final stream = provider.resolve(const ImageConfiguration());
    final completer = Completer<ImageInfo>();

    void listener(ImageInfo info, bool _) => completer.complete(info);
    stream.addListener(ImageStreamListener(listener));

    final info = await completer.future;
    final ui.Image albumArt = info.image;

    final ByteData logoData = await rootBundle.load('assets/icons/radio.png');
    final ui.Codec logoCodec = await ui.instantiateImageCodec(
      logoData.buffer.asUint8List(),
    );
    final ui.FrameInfo logoFrame = await logoCodec.getNextFrame();
    final ui.Image logoImage = logoFrame.image;

    final dominantColor = await getDominantColorFromImage(imageUrl);

    const double width = 1080;
    const double padding = 80;
    const double artSize = width - (padding * 2);

    String title = item.title;
    String artist = '';

    if (item is SongDetail) {
      final Set<String> artistsSet = item.contributors.all
          .map((a) => a.title)
          .toSet();
      if (item.primaryArtists.isNotEmpty) {
        artistsSet.addAll(item.primaryArtists.split(',').map((e) => e.trim()));
      }
      artist = artistsSet.join(', ');
    } else if (item is Album) {
      artist = item.artist;
    } else if (item is Playlist) {
      artist = item.artists.map((a) => a.title).toSet().join(', ');
    }

    final titleSpan = TextSpan(
      text: title,
      style: const TextStyle(
        fontFamily: 'SpotifyMix',
        color: Colors.white,
        fontSize: 72,
        fontWeight: FontWeight.w800,
        letterSpacing: -1.0,
      ),
    );
    final titlePainter = TextPainter(
      text: titleSpan,
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '...',
    );
    titlePainter.layout(maxWidth: artSize);

    final artistSpan = TextSpan(
      text: artist,
      style: const TextStyle(
        fontFamily: 'SpotifyMix',
        color: Colors.white70,
        fontSize: 44,
        fontWeight: FontWeight.w600,
      ),
    );
    final artistPainter = TextPainter(
      text: artistSpan,
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '...',
    );
    artistPainter.layout(maxWidth: artSize);

    const double logoHeight = 90;
    final double logoAspect = logoImage.width / logoImage.height;
    final double logoWidth = logoHeight * logoAspect;

    bool needLogoText = logoAspect < 1.5;
    TextPainter? brandPainter;
    if (needLogoText) {
      brandPainter = TextPainter(
        text: const TextSpan(
          text: 'Hivefy',
          style: TextStyle(
            fontFamily: 'SpotifyMix',
            color: Colors.white,
            fontSize: 64,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.0,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      brandPainter.layout();
    }

    final double titleY = padding + artSize + 80;
    final double artistY = titleY + titlePainter.height + 24;
    final double logoY = artistY + artistPainter.height + 80;
    final double height = logoY + logoHeight + padding;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width, height));

    final hsl = HSLColor.fromColor(dominantColor);
    final topColor = hsl.withLightness(0.20).withSaturation(0.6).toColor();
    final bottomColor = hsl.withLightness(0.04).withSaturation(0.4).toColor();

    final bgRect = RRect.fromRectAndCorners(
      Rect.fromLTWH(0, 0, width, height),
      topLeft: Radius.zero,
      topRight: Radius.zero,
      bottomLeft: const Radius.circular(50),
      bottomRight: const Radius.circular(50),
    );
    final bgPaint = Paint()
      ..shader = ui.Gradient.linear(const Offset(0, 0), Offset(0, height), [
        topColor,
        bottomColor,
      ]);

    // Ensure the entire canvas is strictly transparent to avoid weird black corner rendering
    canvas.drawColor(Colors.transparent, ui.BlendMode.clear);

    canvas.drawRRect(bgRect, bgPaint);

    final artRect = Rect.fromLTWH(padding, padding, artSize, artSize);
    final artRRect = RRect.fromRectAndCorners(
      artRect,
      topLeft: Radius.zero,
      topRight: Radius.zero,
      bottomLeft: const Radius.circular(30),
      bottomRight: const Radius.circular(30),
    );

    canvas.save();
    canvas.clipRRect(artRRect);
    paintImage(
      canvas: canvas,
      rect: artRect,
      image: albumArt,
      fit: BoxFit.cover,
    );
    canvas.restore();

    titlePainter.paint(canvas, Offset(padding, titleY));
    artistPainter.paint(canvas, Offset(padding, artistY));

    paintImage(
      canvas: canvas,
      rect: Rect.fromLTWH(padding, logoY, logoWidth, logoHeight),
      image: logoImage,
      fit: BoxFit.contain,
      colorFilter: const ColorFilter.mode(spotifyGreen, BlendMode.srcIn),
    );

    if (brandPainter != null) {
      brandPainter.paint(
        canvas,
        Offset(
          padding + logoWidth + 24,
          logoY + (logoHeight - brandPainter.height) / 2,
        ),
      );
    }

    final picture = recorder.endRecording();
    final img = await picture.toImage(width.toInt(), height.toInt());
    final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

    return byteData?.buffer.asUint8List();
  } catch (e) {
    debugPrint("⚠️ Failed to generate custom share image: $e");
    return null;
  }
}
