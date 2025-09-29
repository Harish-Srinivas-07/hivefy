import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/database.dart';
import '../shared/constants.dart';

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key});

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  int _allSongsCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAllSongsCount();
  }

  Future<void> _loadAllSongsCount() async {
    final allSongs = await AppDatabase.getAllSongs();
    if (mounted) {
      setState(() {
        _allSongsCount = allSongs.length;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final likedSongs = ref.watch(likedSongsProvider);

    final albumCache = AlbumCache();
    final artistCache = ArtistCache();

    final items = [
      LibraryCardData(
        title: 'Liked Songs',
        count: likedSongs.length,
        imageUrl: null,
        fallbackColor: Colors.redAccent,
      ),
      LibraryCardData(
        title: 'All Songs',
        count: _allSongsCount,
        imageUrl: null,
        fallbackColor: Colors.greenAccent,
      ),
      ...albumCache.getAll().map(
        (album) => LibraryCardData(
          title: album.title,
          count: album.songs.length,
          imageUrl: album.images.isNotEmpty ? album.images.last.url : null,
          fallbackColor: Colors.grey,
        ),
      ),
      ...artistCache.getAll().map(
        (artist) => LibraryCardData(
          title: artist.title,
          count: artist.topSongs.length,
          imageUrl: artist.images.isNotEmpty ? artist.images.last.url : null,
          fallbackColor: Colors.grey,
        ),
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Row(
          children: [
            const CircleAvatar(
              radius: 18,
              backgroundImage: AssetImage('assets/logo.png'),
            ),
            const SizedBox(width: 10),
            Text(
              'Your Library',
              style: GoogleFonts.figtree(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = items[index];
          return LibraryCard(
            title: item.title,
            count: item.count,
            imageUrl: item.imageUrl,
            fallbackColor: item.fallbackColor,
            onTap: () {}, // TODO: add navigation
          );
        },
      ),
    );
  }
}

class LibraryCardData {
  final String title;
  final int count;
  final String? imageUrl;
  final Color fallbackColor;

  LibraryCardData({
    required this.title,
    required this.count,
    this.imageUrl,
    required this.fallbackColor,
  });
}

class LibraryCard extends StatelessWidget {
  final String title;
  final int count;
  final String? imageUrl;
  final Color fallbackColor;
  final VoidCallback? onTap;

  const LibraryCard({
    super.key,
    required this.title,
    required this.count,
    this.imageUrl,
    required this.fallbackColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: imageUrl == null ? fallbackColor : null,
              borderRadius: BorderRadius.circular(8),
              image:
                  imageUrl != null
                      ? DecorationImage(
                        image: NetworkImage(imageUrl!),
                        fit: BoxFit.cover,
                      )
                      : null,
            ),
            child:
                imageUrl == null
                    ? const Icon(
                      Icons.music_note,
                      color: Colors.black54,
                      size: 24,
                    )
                    : null,
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.figtree(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
              Text(
                '$count ${count == 1 ? 'song' : 'songs'}',
                style: GoogleFonts.figtree(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
