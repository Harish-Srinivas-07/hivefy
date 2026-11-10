import 'package:flutter/material.dart';

import '../utils/theme.dart';
import 'shimmers.dart';

class HomeArtwork extends StatelessWidget {
  const HomeArtwork({super.key, required this.imageUrl});

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(HomeCardTheme.radius),
        child: imageUrl.isNotEmpty
            ? CacheNetWorkImg(url: imageUrl, fit: BoxFit.cover)
            : Container(
                color: Colors.grey.shade800,
                child: const Icon(Icons.album, color: Colors.white, size: 32),
              ),
      ),
    );
  }
}
