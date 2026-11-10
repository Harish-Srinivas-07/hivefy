import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../utils/theme.dart';
import 'shimmers.dart';

class SongRowArtwork extends StatelessWidget {
  const SongRowArtwork({super.key, required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return CacheNetWorkImg(
      url: imageUrl,
      width: 50,
      height: 50,
      fit: BoxFit.cover,
      borderRadius: BorderRadius.circular(8),
    );
  }
}

class SongRowTitle extends StatelessWidget {
  const SongRowTitle({super.key, required this.title, required this.isPlaying, this.maxLines, this.isLoading = false});

  final String title;
  final bool isPlaying;
  final int? maxLines;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final titleText = Text(
      title,
      style: TextStyle(color: isPlaying ? spotifyGreen : Colors.white, fontWeight: FontWeight.w500, fontSize: 16),
      overflow: TextOverflow.ellipsis,
      maxLines: maxLines,
    );

    return Row(
      children: [
        if (isPlaying)
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: Image(image: AssetImage('assets/icons/player.gif'), height: 18, fit: BoxFit.contain),
          ),
        Expanded(
          child: isLoading
              ? Shimmer.fromColors(
                  enabled: !MediaQuery.disableAnimationsOf(context),
                  baseColor: Colors.white54,
                  highlightColor: Colors.white,
                  child: titleText,
                )
              : titleText,
        ),
      ],
    );
  }
}
