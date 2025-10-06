import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:page_transition/page_transition.dart';

import '../models/dailyfetches.dart';
import '../models/database.dart';
import '../models/datamodel.dart';
import 'albumviewer.dart';
import 'artistviewer.dart';
import 'playlistviewer.dart';
import 'songsviewer.dart';

class Dashboard extends ConsumerStatefulWidget {
  const Dashboard({super.key});

  @override
  ConsumerState<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends ConsumerState<Dashboard> {
  bool loading = true;
  List<Playlist> playlists = [];
  List<ArtistDetails> artists = [];
  List<Album> albums = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await Dailyfetches.refreshAllDaily();
    playlists = await Dailyfetches.getPlaylistsFromCache();
    artists = await Dailyfetches.getArtistsAsListFromCache();

    if (!mounted) return;
    albums = (ref.watch(frequentAlbumsProvider)).take(5).toList();

    loading = false;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: _buildHeader(),
      ),
      body:
          loading
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionGrid("Featured Playlists", playlists),
                    _sectionList("Jump Back In", playlists),
                    _sectionAlbumList("Albums", albums),
                    _sectionArtistList("Artists", artists),
                    _sectionList("Today's Hits", playlists),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const CircleAvatar(
          radius: 18,
          backgroundImage: AssetImage('assets/logo.png'),
        ),
        const SizedBox(width: 15),
        Text(
          'Hivefy',
          style: GoogleFonts.figtree(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _sectionGrid(String title, List<Playlist> playlists) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (playlists.isEmpty) return const SizedBox.shrink();

    final combined = [
      Playlist(
        id: 'liked',
        title: 'Liked Songs',
        type: 'custom',
        url: '',
        images: [],
      ),
      Playlist(
        id: 'all',
        title: 'All Songs',
        type: 'custom',
        url: '',
        images: [],
      ),
      ...playlists,
    ];

    // Only take first 5 for the grid
    final displayList = combined.take(10).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(title),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: displayList.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 3.5,
            ),
            itemBuilder: (context, index) {
              final p = displayList[index];
              return _gridCard(p);
            },
          ),
        ],
      ),
    );
  }

  Widget _gridCard(Playlist p) {
    final isSpecial = p.id == 'liked' || p.id == 'all';
    final img = p.images.isNotEmpty ? p.images.first.url : '';

    return GestureDetector(
      onTap: () {
        if (p.id == 'liked') {
          Navigator.of(context).push(
            PageTransition(
              type: PageTransitionType.rightToLeft,
              duration: const Duration(milliseconds: 300),
              child: SongsViewer(showLikedSongs: true),
            ),
          );
        } else if (p.id == 'all') {
          Navigator.of(context).push(
            PageTransition(
              type: PageTransitionType.rightToLeft,
              duration: const Duration(milliseconds: 300),
              child: SongsViewer(showLikedSongs: false),
            ),
          );
        } else {
          Navigator.of(context).push(
            PageTransition(
              type: PageTransitionType.rightToLeft,
              duration: const Duration(milliseconds: 300),
              child: PlaylistViewer(playlistId: p.id),
            ),
          );
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                bottomLeft: Radius.circular(8),
              ),
              child:
                  isSpecial
                      ? Container(
                        height: double.infinity,
                        width: 60,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors:
                                p.id == 'liked'
                                    ? [Colors.purpleAccent, Colors.deepPurple]
                                    : [Colors.greenAccent, Colors.teal],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Icon(
                          p.id == 'liked'
                              ? Icons.favorite
                              : Icons.library_music,
                          color: Colors.white,
                        ),
                      )
                      : (img.isNotEmpty
                          ? Image.network(
                            img,
                            width: 60,
                            height: double.infinity,
                            fit: BoxFit.cover,
                          )
                          : Container(
                            width: 60,
                            color: Colors.grey[800],
                            child: const Icon(Icons.album, color: Colors.white),
                          )),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                p.title,
                style: GoogleFonts.figtree(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- LIST SECTION (refined)
  Widget _sectionList(String title, List<Playlist> list) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (list.isEmpty) return const SizedBox.shrink();

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
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          height: 200,
          child: PageView.builder(
            controller: PageController(viewportFraction: 0.45),
            padEnds: false,
            physics: const BouncingScrollPhysics(),
            itemCount: list.length,
            itemBuilder: (context, index) {
              final playlist = list[index];
              return Padding(
                padding: const EdgeInsets.only(right: 20),
                child: _playlistCard(playlist),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _playlistCard(Playlist playlist) {
    final imageUrl =
        playlist.images.isNotEmpty ? playlist.images.first.url : '';
    final subtitle =
        playlist.artists.isNotEmpty
            ? playlist.artists.first.title
            : (playlist.songCount != null ? '${playlist.songCount} songs' : '');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (playlist.id == 'liked') {
          Navigator.of(context).push(
            PageTransition(
              type: PageTransitionType.rightToLeft,
              duration: const Duration(milliseconds: 300),
              child: SongsViewer(showLikedSongs: true),
            ),
          );
        } else if (playlist.id == 'all') {
          Navigator.of(context).push(
            PageTransition(
              type: PageTransitionType.rightToLeft,
              duration: const Duration(milliseconds: 300),
              child: SongsViewer(showLikedSongs: false),
            ),
          );
        } else {
          Navigator.of(context).push(
            PageTransition(
              type: PageTransitionType.rightToLeft,
              duration: const Duration(milliseconds: 300),
              child: PlaylistViewer(playlistId: playlist.id),
            ),
          );
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child:
                  imageUrl.isNotEmpty
                      ? Image.network(imageUrl, fit: BoxFit.cover)
                      : Container(
                        color: Colors.grey.shade800,
                        child: const Icon(
                          Icons.album,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
            ),
          ),
          const SizedBox(height: 6),
          Flexible(
            child: Text(
              playlist.title,
              style: GoogleFonts.figtree(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          if (subtitle.isNotEmpty)
            Flexible(
              child: Text(
                subtitle,
                style: GoogleFonts.figtree(color: Colors.white54, fontSize: 12),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionArtistList(String title, List<ArtistDetails> artists) {
    if (artists.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(title),
        const SizedBox(height: 8),
        SizedBox(
          height: 160,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: artists.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.only(right: 16),
                child: _artistCard(artists[index]),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _artistCard(ArtistDetails artist) {
    final imageUrl = artist.images.isNotEmpty ? artist.images.last.url : '';

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          PageTransition(
            type: PageTransitionType.rightToLeft,
            duration: const Duration(milliseconds: 300),
            child: ArtistViewer(artistId: artist.id),
          ),
        );
      },
      child: Column(
        children: [
          CircleAvatar(
            radius: 50,
            backgroundImage:
                imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
            backgroundColor: Colors.grey.shade800,
            child:
                imageUrl.isEmpty
                    ? const Icon(Icons.person, color: Colors.white, size: 30)
                    : null,
          ),
          const SizedBox(height: 6),
          Text(
            artist.title,
            style: GoogleFonts.figtree(color: Colors.white, fontSize: 14),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  Widget _sectionAlbumList(String title, List<Album> albums) {
    if (albums.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(title),
          const SizedBox(height: 8),
          SizedBox(
            height: 200,
            child: PageView.builder(
              controller: PageController(viewportFraction: 0.45),
              padEnds: false,
              physics: const BouncingScrollPhysics(),
              itemCount: albums.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(left: 16, right: 20),
                  child: _albumCard(albums[index]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _albumCard(Album album) {
    final imageUrl = album.images.isNotEmpty ? album.images.last.url : '';

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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child:
                  imageUrl.isNotEmpty
                      ? Image.network(imageUrl, fit: BoxFit.cover)
                      : Container(
                        color: Colors.grey.shade800,
                        child: const Icon(
                          Icons.album,
                          color: Colors.white,
                          size: 30,
                        ),
                      ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            album.title,
            style: GoogleFonts.figtree(
              color: Colors.white,
              fontWeight: FontWeight.w500,
              fontSize: 14,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        title,
        style: GoogleFonts.figtree(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}
