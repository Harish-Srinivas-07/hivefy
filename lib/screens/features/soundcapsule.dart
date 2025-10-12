import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hivefy/utils/format.dart';
import 'package:intl/intl.dart';
import 'package:page_transition/page_transition.dart';
import '../../models/database.dart';
import '../../models/datamodel.dart';
import '../../utils/theme.dart';
import '../views/albumviewer.dart';
import '../views/artistviewer.dart';

class SoundCapsule extends ConsumerStatefulWidget {
  const SoundCapsule({super.key});

  @override
  ConsumerState<SoundCapsule> createState() => _SoundCapsuleState();
}

class _SoundCapsuleState extends ConsumerState<SoundCapsule> {
  int monthlyMinutes = 0;
  bool _loading = true;
  bool _isTitleCollapsed = false;
  late ScrollController _scrollController;

  String monthYear = '';
  String month = '';
  int visitAlbumCount = 0;
  List<ArtistDetails> topArtists = [];
  List<Album> topalbums = [];

  @override
  void initState() {
    super.initState();
    // Scroll controller for collapsing appbar
    _scrollController =
        ScrollController()..addListener(() {
          final offset = _scrollController.offset;
          if (offset > 120 && !_isTitleCollapsed) {
            setState(() => _isTitleCollapsed = true);
          } else if (offset <= 120 && _isTitleCollapsed) {
            setState(() => _isTitleCollapsed = false);
          }
        });

    _init();
  }

  Future<void> _init() async {
    // Calculate month string
    final now = DateTime.now();
    month = capitalize(DateFormat('MMMM').format(now));
    monthYear = "$month ${now.year}";

    // Load artists & listening minutes
    if (!mounted) return;
    topArtists = (ref.read(frequentArtistsProvider)).take(2).toList();
    if (!mounted) return;
    topalbums = (ref.read(frequentAlbumsProvider)).take(5).toList();

    if (topalbums.isNotEmpty) {
      visitAlbumCount = AlbumCache().getUsageCount(topalbums[0].id);
    }

    await _loadCapsule();
  }

  Future<void> _loadCapsule() async {
    final minutes = await AppDatabase.getMonthlyListeningHours();
    monthlyMinutes = minutes.toInt();
    _loading = false;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: spotifyBgColor,
      body:
          _loading
              ? const Center(
                child: CircularProgressIndicator(color: Colors.white),
              )
              : CustomScrollView(
                controller: _scrollController,
                slivers: [
                  // --- Spotify-style AppBar ---
                  SliverAppBar(
                    pinned: true,
                    expandedHeight: 160,
                    elevation: 0,
                    backgroundColor: getDominantDarker(spotifyBgColor),
                    leading: const BackButton(color: Colors.white),
                    flexibleSpace: LayoutBuilder(
                      builder: (context, constraints) {
                        final rawCollapse =
                            (constraints.maxHeight - kToolbarHeight) / 80.0;
                        final collapsePercent = rawCollapse.clamp(0.0, 1.0);

                        return FlexibleSpaceBar(
                          centerTitle: false,
                          titlePadding: EdgeInsets.only(
                            left: _isTitleCollapsed ? 72 : 16,
                            bottom: 16,
                            right: 16,
                          ),
                          title: AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: _isTitleCollapsed ? 1.0 : 0.0,
                            child: const Text(
                              "Sound Capsule",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                                letterSpacing: 0.3,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          background: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  getDominantDarker(spotifyBgColor),
                                  spotifyBgColor,
                                ],
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.only(
                                left: 24,
                                bottom: 32,
                              ),
                              child: Align(
                                alignment: Alignment.bottomLeft,
                                child: Opacity(
                                  opacity: 0.95 * collapsePercent,
                                  child: const Text(
                                    "Sound Capsule",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 28,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // --- Listening Summary ---
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            monthYear,
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            "You've listened to music for",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w500,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(
                                "$monthlyMinutes",
                                style: TextStyle(
                                  color: spotifyGreen,
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                "minutes this month",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w500,
                                  height: 1.2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Center(
                            child: Container(
                              height: 1,
                              width: 120,
                              color: Colors.white12,
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),

                  // --- Top Artists Row ---
                  if (topArtists.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Text(
                        "Your top artists, based on your listen\nalbum & searches",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          height: 1.5,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: 20,
                          horizontal: 16,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children:
                              topArtists.map((artist) {
                                final imageUrl =
                                    artist.images.isNotEmpty
                                        ? artist.images.last.url
                                        : '';
                                final visitCount = ArtistCache().getUsageCount(
                                  artist.id,
                                ); // get visit count

                                return Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: GestureDetector(
                                    onTap: () {
                                      Navigator.of(context).push(
                                        PageTransition(
                                          type: PageTransitionType.rightToLeft,
                                          duration: const Duration(
                                            milliseconds: 300,
                                          ),
                                          child: ArtistViewer(
                                            artistId: artist.id,
                                          ),
                                        ),
                                      );
                                    },
                                    child: Column(
                                      children: [
                                        Container(
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: spotifyGreen,
                                              width: 2,
                                            ),
                                          ),
                                          child: CircleAvatar(
                                            radius: 50,
                                            backgroundImage:
                                                imageUrl.isNotEmpty
                                                    ? NetworkImage(imageUrl)
                                                    : null,
                                            backgroundColor:
                                                Colors.grey.shade800,
                                            child:
                                                imageUrl.isEmpty
                                                    ? const Icon(
                                                      Icons.person,
                                                      color: Colors.white,
                                                      size: 30,
                                                    )
                                                    : null,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        SizedBox(
                                          width: 130,
                                          child: Column(
                                            children: [
                                              Text(
                                                artist.title,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'Visited $visitCount ${visitCount == 1 ? "time" : "times"}',
                                                style: const TextStyle(
                                                  color: Colors.white54,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w400,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                capitalize(
                                                  artist.dominantLanguage,
                                                ),
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w400,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                                maxLines: 1,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                        ),
                      ),
                    ),
                  ],

                  // --- Top Albums Section ---
                  if (topalbums.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        child: Text(
                          "Your top Top albums,\nthis $month",
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                            fontWeight: FontWeight.w400,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    // --- First album: image left, details right ---
                    SliverToBoxAdapter(
                      child: GestureDetector(
                        onTap: () {
                          Navigator.of(context).push(
                            PageTransition(
                              type: PageTransitionType.rightToLeft,
                              duration: const Duration(milliseconds: 300),
                              child: AlbumViewer(albumId: topalbums[0].id),
                            ),
                          );
                        },
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          height: 140,
                          child: Row(
                            children: [
                              // Album image
                              Container(
                                width: MediaQuery.of(context).size.width * 0.5,
                                height: 140,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  image:
                                      topalbums[0].images.isNotEmpty
                                          ? DecorationImage(
                                            image: CachedNetworkImageProvider(
                                              topalbums[0].images.last.url,
                                            ),
                                            fit: BoxFit.cover,
                                          )
                                          : null,
                                  color: Colors.grey.shade800,
                                ),
                              ),

                              const SizedBox(width: 12),

                              // Album metadata
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      topalbums[0].title,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 2,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      topalbums[0].artist,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 13,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      topalbums[0].year,
                                      style: const TextStyle(
                                        color: Colors.white54,
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.library_music,
                                          size: 14,
                                          color: Colors.white54,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          "${topalbums[0].songs.length} songs",
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "You've listened ${topalbums[0].title} ",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                height: 1.2,
                              ),
                            ),
                            // const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        "$visitAlbumCount ",
                                        style: TextStyle(
                                          color: spotifyGreen,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          height: 1.2,
                                        ),
                                      ),
                                      // const SizedBox(width: 8),
                                      const Text(
                                        "times this month.",
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                          height: 1.2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8.0,
                                  ),
                                  child: Image.asset(
                                    'assets/icons/tick.png',
                                    width: 26,
                                    height: 26,
                                    fit: BoxFit.contain,
                                    color: spotifyGreen,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    // --- Remaining 4 topalbums: vertical list style ---
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        if (index + 1 >= topalbums.length) {
                          return null;
                        }
                        final album = topalbums[index + 1];
                        return GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              PageTransition(
                                type: PageTransitionType.rightToLeft,
                                duration: const Duration(milliseconds: 300),
                                child: AlbumViewer(albumId: album.id),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Album image square
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    image:
                                        album.images.isNotEmpty
                                            ? DecorationImage(
                                              image: CachedNetworkImageProvider(
                                                album.images.last.url,
                                              ),
                                              fit: BoxFit.cover,
                                            )
                                            : null,
                                    color: Colors.grey.shade800,
                                  ),
                                ),
                                const SizedBox(width: 12),

                                // Album details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        album.title,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                      Text(
                                        album.artist,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 12,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 1,
                                      ),
                                      Text(
                                        "${album.songs.length} songs • ${album.year}",
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }, childCount: topalbums.length - 1),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 100)),
                  ],
                ],
              ),
    );
  }
}
