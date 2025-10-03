import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_swipe_action_cell/core/cell.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hivefy/models/shimmers.dart';
import 'package:page_transition/page_transition.dart';
import 'package:readmore/readmore.dart';
import '../models/datamodel.dart';
import '../services/audiohandler.dart';
import '../services/jiosaavn.dart';
import '../shared/constants.dart';
import '../shared/player.dart';
import 'albumviewer.dart';

class ArtistViewer extends ConsumerStatefulWidget {
  final String artistId;

  const ArtistViewer({super.key, required this.artistId});

  @override
  ConsumerState<ArtistViewer> createState() => _ArtistViewerState();
}

class _ArtistViewerState extends ConsumerState<ArtistViewer> {
  ArtistDetails? _artist;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchArtist();
  }

  Future<void> _fetchArtist() async {
    setState(() => _loading = true);
    final details = await SaavnAPI().fetchArtistDetailsById(
      artistId: widget.artistId,
    );
    if (mounted) {
      setState(() {
        _artist = details;
        _loading = false;
      });
    }
  }

  Widget _buildHeader() {
    if (_artist == null) return const SizedBox.shrink();

    final imageUrl = _artist!.images.isNotEmpty ? _artist!.images.last.url : '';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: SizedBox(
              width: MediaQuery.of(context).size.width * 0.80,
              height: 300,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child:
                    imageUrl.isNotEmpty
                        ? Image.network(imageUrl, fit: BoxFit.contain)
                        : Container(
                          color: Colors.grey.shade800,
                          child: const Icon(
                            Icons.person,
                            size: 100,
                            color: Colors.white,
                          ),
                        ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text(
                _artist!.title,
                style: GoogleFonts.figtree(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              if (_artist!.isVerified == true) ...[
                const SizedBox(width: 10),
                const Icon(Icons.verified, size: 18, color: Colors.blueAccent),
              ],
            ],
          ),

          const SizedBox(height: 2),
          Text(
            '${_artist!.followerCount ?? 0} followers',
            style: GoogleFonts.figtree(color: Colors.white70, fontSize: 13),
          ),
          if (_artist!.bio.isNotEmpty)
            if (_artist!.bio.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: ReadMoreText(
                  _artist!.bio.join("\n\n"),
                  trimLines: 3,
                  trimMode: TrimMode.Line,
                  colorClickableText: Colors.greenAccent,
                  trimCollapsedText: " ...more",
                  trimExpandedText: " Show less",
                  style: GoogleFonts.figtree(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                  moreStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.greenAccent,
                  ),
                  lessStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.greenAccent,
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildSongList() {
    final songs = _artist?.topSongs ?? [];
    if (_loading) return buildAlbumShimmer();

    if (songs.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            "Top Songs",
            style: GoogleFonts.figtree(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...songs.map((song) => SongRow(song: song)),
      ],
    );
  }

  Widget _buildAlbumList(String title, List<Album> albums) {
    if (_loading) return buildAlbumShimmer();

    if (albums.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            title,
            style: GoogleFonts.figtree(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...albums.map((album) => AlbumRow(album: album)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ref.watch(playerColourProvider),
      appBar: AppBar(backgroundColor: Colors.transparent, elevation: 0),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [ref.watch(playerColourProvider), Colors.black],
          ),
        ),
        child:
            _loading && _artist == null
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 16),
                      _buildSongList(),
                      const SizedBox(height: 16),
                      _buildAlbumList("Top Albums", _artist?.topAlbums ?? []),
                      const SizedBox(height: 16),
                      _buildAlbumList("Singles", _artist?.singles ?? []),
                      const SizedBox(height: 70),
                    ],
                  ),
                ),
      ),
    );
  }
}

class SongRow extends ConsumerWidget {
  final SongDetail song;

  const SongRow({super.key, required this.song});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentSong = ref.watch(currentSongProvider);
    final isPlaying = currentSong?.id == song.id;
    final isLiked = ref.watch(likedSongsProvider).contains(song.id);

    return SwipeActionCell(
      backgroundColor: Colors.transparent,
      key: ValueKey(song.id),
      fullSwipeFactor: 0.3,
      editModeOffset: 10,
      trailingActions: [
        SwipeAction(
          color: Colors.greenAccent.shade700,
          icon: const Icon(Icons.playlist_add),
          performsFirstActionWithFullSwipe: true,
          onTap: (handler) async {
            final audioHandler = await ref.read(audioHandlerProvider.future);
            await audioHandler.playSongNow(song, insertNext: true);
            await handler(false);
          },
        ),
      ],
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () async {
          final audioHandler = await ref.read(audioHandlerProvider.future);
          await audioHandler.loadQueue([song], startIndex: 0);
          await audioHandler.play();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  song.images.isNotEmpty ? song.images.last.url : '',
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      style: GoogleFonts.figtree(
                        color: isPlaying ? Colors.greenAccent : Colors.white,
                        fontWeight: FontWeight.w500,
                        fontSize: 16,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      song.primaryArtists.isNotEmpty
                          ? song.primaryArtists
                          : song.album,
                      style: GoogleFonts.figtree(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isLiked) const Icon(Icons.check_circle, color: Colors.green),
              if (isPlaying) Image.asset('assets/player.gif', height: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class AlbumRow extends StatelessWidget {
  final Album album;

  const AlbumRow({super.key, required this.album});

  @override
  Widget build(BuildContext context) {
    final imageUrl = album.images.isNotEmpty ? album.images.last.url : '';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Navigator.of(context).push(
          PageTransition(
            type: PageTransitionType.rightToLeft,
            duration: const Duration(milliseconds: 300),
            child: AlbumViewer(albumId: album.id),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child:
                  imageUrl.isNotEmpty
                      ? Image.network(
                        imageUrl,
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                      )
                      : Container(
                        width: 50,
                        height: 50,
                        color: Colors.grey.shade800,
                        child: const Icon(
                          Icons.album,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.title,
                    style: GoogleFonts.figtree(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  if (album.artist.isNotEmpty)
                    Text(
                      album.artist,
                      style: GoogleFonts.figtree(
                        color: Colors.white54,
                        fontSize: 13,
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
  }
}
