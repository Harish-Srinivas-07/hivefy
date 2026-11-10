import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:just_audio/just_audio.dart';

class PlayerProgressTrack extends StatelessWidget {
  const PlayerProgressTrack({super.key, required this.playerStateStream, required this.child, this.height = 48});

  final Stream<PlayerState> playerStateStream;
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: StreamBuilder<PlayerState>(
        stream: playerStateStream,
        builder: (context, snapshot) {
          final state = snapshot.data?.processingState;
          if (state == ProcessingState.loading || state == ProcessingState.buffering) {
            return const PlayerProgressLoading();
          }
          return child;
        },
      ),
    );
  }
}

/// A compact loading track for the full-screen player's seek bar.
class PlayerProgressLoading extends StatelessWidget {
  const PlayerProgressLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading song',
      child: SizedBox(
        height: 48,
        child: Center(
          child: Shimmer.fromColors(
            baseColor: Colors.white24,
            highlightColor: Colors.white70,
            enabled: !MediaQuery.disableAnimationsOf(context),
            period: const Duration(milliseconds: 1400),
            child: Container(
              height: 4,
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
            ),
          ),
        ),
      ),
    );
  }
}

Widget buildAlbumShimmer() {
  return ListView(
    padding: const EdgeInsets.all(16),
    children: [
      // Album cover shimmer
      Shimmer.fromColors(
        baseColor: Colors.grey[900]!,
        highlightColor: Colors.grey[800]!,
        child: Container(
          height: 350,
          width: 350,
          decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(16)),
        ),
      ),
      const SizedBox(height: 16),

      // Album title shimmer
      Shimmer.fromColors(
        baseColor: Colors.grey[900]!,
        highlightColor: Colors.grey[800]!,
        child: Container(
          height: 22,
          width: 200,
          decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(4)),
        ),
      ),
      const SizedBox(height: 8),

      // Album artist shimmer
      Shimmer.fromColors(
        baseColor: Colors.grey[900]!,
        highlightColor: Colors.grey[800]!,
        child: Container(
          height: 14,
          width: 150,
          decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(4)),
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
              baseColor: Colors.grey[900]!,
              highlightColor: Colors.grey[800]!,
              child: Container(
                height: 48,
                width: 48,
                decoration: BoxDecoration(color: Colors.grey[900], shape: BoxShape.circle),
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
            baseColor: Colors.grey[900]!,
            highlightColor: Colors.grey[800]!,
            child: Container(
              height: 50,
              decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ),
      ),
      const SizedBox(height: 70), // match bottom padding in album viewer
    ],
  );
}

Widget buildSearchShimmerSliver() {
  return SliverList(
    delegate: SliverChildBuilderDelegate(
      (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Shimmer.fromColors(
          baseColor: Colors.grey[800]!,
          highlightColor: Colors.grey[600]!,
          child: Row(
            children: [
              // Image placeholder
              Container(
                height: 60,
                width: 60,
                decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(8)),
              ),
              const SizedBox(width: 12),

              // Text placeholders
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 16,
                      width: double.infinity,
                      decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(4)),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      height: 14,
                      width: 100,
                      decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(4)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      childCount: 6,
    ),
  );
}

class CacheNetWorkImg extends StatelessWidget {
  final String url;
  final String? fallbackUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final BorderRadius? borderRadius;
  final Duration fadeInDuration;
  final Duration fadeOutDuration;

  const CacheNetWorkImg({
    super.key,
    required this.url,
    this.fallbackUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.borderRadius,
    this.fadeInDuration = const Duration(milliseconds: 500),
    this.fadeOutDuration = const Duration(milliseconds: 1000),
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: CachedNetworkImage(
        imageUrl: url,
        width: width,
        height: height,
        fit: fit,
        alignment: alignment,
        fadeInDuration: fadeInDuration,
        fadeOutDuration: fadeOutDuration,
        placeholder: (context, url) => Shimmer.fromColors(
          baseColor: Colors.grey.shade800,
          highlightColor: Colors.grey.shade700,
          child: Container(width: width, height: height, color: Colors.grey.shade800),
        ),
        errorWidget: (context, url, error) => fallbackUrl != null && fallbackUrl!.isNotEmpty && fallbackUrl != url
            ? CachedNetworkImage(
                imageUrl: fallbackUrl!,
                width: width,
                height: height,
                fit: fit,
                alignment: alignment,
                fadeInDuration: fadeInDuration,
                fadeOutDuration: fadeOutDuration,
                errorWidget: (context, url, error) => _errorPlaceholder(),
              )
            : _errorPlaceholder(),
      ),
    );
  }

  Widget _errorPlaceholder() => Container(
    width: width,
    height: height,
    color: Colors.grey.shade800,
    child: const Icon(Icons.broken_image, color: Colors.white),
  );
}

// PLaylist section & cards shimmer
Widget heroGridShimmer() {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Shimmer.fromColors(
      baseColor: Colors.grey[900]!,
      highlightColor: Colors.grey[800]!,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 8,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 3.5,
        ),
        itemBuilder: (context, index) {
          return Container(
            decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(color: Colors.grey, shape: BoxShape.circle),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 12,
                        width: double.infinity,
                        decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(4)),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        height: 10,
                        width: 60,
                        decoration: BoxDecoration(color: Colors.grey[800], borderRadius: BorderRadius.circular(4)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );
}

// Playlist section shimmer
Widget buildPlaylistSectionShimmer() {
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: SizedBox(
      height: 200,
      child: PageView.builder(
        controller: PageController(viewportFraction: 0.45),
        padEnds: false,
        physics: const BouncingScrollPhysics(),
        itemCount: 5,
        itemBuilder: (context, index) {
          return Padding(padding: EdgeInsets.only(left: 20), child: buildPlaylistCardShimmer());
        },
      ),
    ),
  );
}

// Playlist card shimmer
Widget buildPlaylistCardShimmer({double height = 200, double width = 150}) {
  return Shimmer.fromColors(
    baseColor: Colors.grey[900]!,
    highlightColor: Colors.grey[800]!,
    child: SizedBox(
      height: height,
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(color: Colors.grey[900]),
            ),
          ),
          const SizedBox(height: 6),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 14,
                  width: 100,
                  decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(4)),
                ),
                const SizedBox(height: 4),
                Container(
                  height: 12,
                  width: 80,
                  decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(4)),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
