import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

Widget buildAlbumShimmer() {
  return ListView(
    padding: const EdgeInsets.all(16),
    children: [
      // Album cover shimmer
      Shimmer.fromColors(
        baseColor: Colors.grey[800]!,
        highlightColor: Colors.grey[600]!,
        child: Container(
          height: 350,
          width: 350,
          decoration: BoxDecoration(
            color: Colors.grey[800],
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      const SizedBox(height: 16),

      // Album title shimmer
      Shimmer.fromColors(
        baseColor: Colors.grey[800]!,
        highlightColor: Colors.grey[600]!,
        child: Container(
          height: 22,
          width: 200,
          decoration: BoxDecoration(
            color: Colors.grey[800],
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
      const SizedBox(height: 8),

      // Album artist shimmer
      Shimmer.fromColors(
        baseColor: Colors.grey[800]!,
        highlightColor: Colors.grey[600]!,
        child: Container(
          height: 14,
          width: 150,
          decoration: BoxDecoration(
            color: Colors.grey[800],
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
      const SizedBox(height: 24),

      // Controls shimmer row (shuffle + play buttons)
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: List.generate(2, (index) {
          return Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Shimmer.fromColors(
              baseColor: Colors.grey[800]!,
              highlightColor: Colors.grey[600]!,
              child: Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(
                  color: Colors.grey[800],
                  shape: BoxShape.circle,
                ),
              ),
            ),
          );
        }),
      ),
      const SizedBox(height: 24),

      // Song list shimmer
      ...List.generate(
        6,
        (i) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Shimmer.fromColors(
            baseColor: Colors.grey[800]!,
            highlightColor: Colors.grey[600]!,
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: Colors.grey[800],
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 70), // match bottom padding in album viewer
    ],
  );
}
