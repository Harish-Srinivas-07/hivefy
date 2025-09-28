import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

Widget buildAlbumShimmer() {
  return ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Shimmer.fromColors(
        baseColor: Colors.grey[800]!,
        highlightColor: Colors.grey[600]!,
        child: Container(
          height: 220,
          decoration: BoxDecoration(
            color: Colors.grey[800],
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Shimmer.fromColors(
        baseColor: Colors.grey[800]!,
        highlightColor: Colors.grey[600]!,
        child: Container(height: 22, width: 150, color: Colors.grey[800]),
      ),
      const SizedBox(height: 8),
      Shimmer.fromColors(
        baseColor: Colors.grey[800]!,
        highlightColor: Colors.grey[600]!,
        child: Container(height: 14, width: 200, color: Colors.grey[800]),
      ),
      const SizedBox(height: 24),
      ...List.generate(
        6,
        (i) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Shimmer.fromColors(
            baseColor: Colors.grey[800]!,
            highlightColor: Colors.grey[600]!,
            child: Container(height: 50, color: Colors.grey[800]),
          ),
        ),
      ),
    ],
  );
}
