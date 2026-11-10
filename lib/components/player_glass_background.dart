import 'dart:ui';

import 'package:flutter/material.dart';

import 'package:cached_network_image/cached_network_image.dart';

import 'liquid_glass.dart';

class PlayerGlassBackground extends StatelessWidget {
  const PlayerGlassBackground({
    super.key,
    required this.color,
    required this.child,
    this.artworkUrl,
    this.tintArtwork = false,
    this.blurSigma = 30,
    this.glassy = false,
  });

  final Color color;
  final Widget child;
  final String? artworkUrl;
  final bool tintArtwork;
  final double blurSigma;
  final bool glassy;

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        children: [
          if (artworkUrl != null && artworkUrl!.isNotEmpty)
            Positioned.fill(
              child: RepaintBoundary(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma, tileMode: TileMode.decal),
                  child: CachedNetworkImage(
                    key: ValueKey(artworkUrl),
                    imageUrl: artworkUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          LiquidGlass(
            // The artwork underneath is already blurred. A second full-screen
            // backdrop blur adds substantial raster work, especially under sheets.
            blurSigma: 0,
            tint: const Color(0x22121212),
            exponent: 16,
            shadow: false,
            rim: false,
            child: AnimatedContainer(
              duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 400),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    artworkUrl?.isNotEmpty == true
                        ? (glassy
                              ? color.withValues(alpha: 0.34)
                              : (tintArtwork ? color : Colors.black).withValues(alpha: 0.55))
                        : Color.lerp(color, Colors.white, 0.06)!.withValues(alpha: 0.93),
                    artworkUrl?.isNotEmpty == true
                        ? (glassy
                              ? Color.lerp(color, Colors.black, 0.35)!.withValues(alpha: 0.45)
                              : (tintArtwork ? Color.lerp(color, Colors.black, 0.65)! : Colors.black).withValues(
                                  alpha: 0.75,
                                ))
                        : Color.lerp(color, Colors.black, 0.58)!.withValues(alpha: 0.95),
                    glassy ? const Color(0x7a121212) : const Color(0xf5121212),
                  ],
                  stops: const [0, 0.5, 1],
                ),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.8, -1),
                    radius: 1.25,
                    colors: [
                      Colors.white.withValues(alpha: glassy ? 0.09 : 0.045),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
