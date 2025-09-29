import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LikedSongsNotifier extends StateNotifier<List<String>> {
  LikedSongsNotifier() : super([]) {
    _loadLikes();
  }

  Future<void> _loadLikes() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('likedSongs') ?? [];
    state = saved;
  }

  void _saveLikes() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList('likedSongs', state);
  }

  bool isLiked(String songId) => state.contains(songId);

  void like(String songId) {
    if (!state.contains(songId)) {
      state = [...state, songId];
      _saveLikes();
    }
  }

  void unlike(String songId) {
    state = state.where((id) => id != songId).toList();
    _saveLikes();
  }

  void toggle(String songId) {
    if (isLiked(songId)) {
      unlike(songId);
    } else {
      like(songId);
    }
  }
}
