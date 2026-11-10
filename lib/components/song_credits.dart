import 'package:flutter/material.dart';

import '../models/datamodel.dart';

class SongCredits extends StatelessWidget {
  const SongCredits({super.key, required this.song, this.onArtistTap});

  final SongDetail song;
  final ValueChanged<String>? onArtistTap;

  @override
  Widget build(BuildContext context) {
    final credits = _creditsForSong(song);
    if (credits.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 36),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.grey[900], borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Credits',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            for (var i = 0; i < credits.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              InkWell(
                onTap: credits[i].artistId.isNotEmpty && onArtistTap != null
                    ? () => onArtistTap!(credits[i].artistId)
                    : null,
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            credits[i].name,
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 3),
                          Text(credits[i].role, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                        ],
                      ),
                    ),
                    if (credits[i].artistId.isNotEmpty && onArtistTap != null)
                      const Icon(Icons.chevron_right, color: Colors.white54),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Credit {
  const _Credit(this.name, this.role, this.artistId);
  final String name;
  final String role;
  final String artistId;
}

List<_Credit> _creditsForSong(SongDetail song) {
  final credits = <_Credit>[];
  final seen = <String, int>{};

  void add(String name, String role, [String artistId = '']) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final key = trimmed.toLowerCase();
    final existing = seen[key];
    if (existing == null) {
      seen[key] = credits.length;
      credits.add(_Credit(trimmed, role, artistId.trim()));
    } else if (credits[existing].artistId.isEmpty && artistId.trim().isNotEmpty) {
      credits[existing] = _Credit(credits[existing].name, credits[existing].role, artistId.trim());
    }
  }

  for (final artist in song.contributors.primary) {
    add(artist.title, 'Primary artist', artist.id);
  }
  for (final artist in song.contributors.featured) {
    add(artist.title, 'Featured artist', artist.id);
  }
  for (final artist in song.contributors.all) {
    add(artist.title, 'Artist', artist.id);
  }
  if (credits.isEmpty) {
    add(song.primaryArtists, 'Artist');
    if (song.singers.trim().toLowerCase() != song.primaryArtists.trim().toLowerCase()) {
      add(song.singers, 'Artist');
    }
  }
  return credits;
}
