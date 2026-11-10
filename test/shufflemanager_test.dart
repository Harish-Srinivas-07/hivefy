import 'package:flutter_test/flutter_test.dart';
import 'package:hivefy/models/datamodel.dart';
import 'package:hivefy/services/shufflemanager.dart';

SongDetail song(String id) => SongDetail(id: id, title: id, type: 'song', url: '', images: []);

void main() {
  test('shuffle retains recently played tracks and restores original order', () {
    final manager = ShuffleManager();
    final songs = [song('a'), song('b'), song('c')];
    manager.loadQueue(songs, currentIndex: 1);
    manager.registerPlay(songs.first);
    manager.toggleShuffle();
    expect(manager.currentSong?.id, 'b');
    expect(manager.currentQueue.map((s) => s.id).toSet(), {'a', 'b', 'c'});
    manager.toggleShuffle();
    expect(manager.currentQueue.map((s) => s.id), ['a', 'b', 'c']);
    expect(manager.currentSong?.id, 'b');
  });

  test('loading a new shuffled queue selects a song from that queue', () {
    final manager = ShuffleManager();
    manager.loadQueue([song('old')]);
    manager.toggleShuffle();
    manager.loadQueue([song('new1'), song('new2')], currentIndex: 1);
    expect(manager.currentSong?.id, 'new2');
    expect(manager.currentQueue.map((s) => s.id).toSet(), {'new1', 'new2'});
    manager.reset();
    expect(manager.isShuffling, false);
    expect(manager.currentQueue, isEmpty);
  });

  test('reordering upcoming songs preserves the current song', () {
    final manager = ShuffleManager();
    manager.loadQueue([song('a'), song('b'), song('c')]);
    manager.reorder(1, 2);
    expect(manager.currentQueue.map((s) => s.id), ['a', 'c', 'b']);
    expect(manager.currentSong?.id, 'a');
    manager.reset();
    manager.reorder(0, 0);
  });

  test('reshuffling preserves history and current track in both shuffle modes', () {
    for (final shuffle in [false, true]) {
      final manager = ShuffleManager();
      manager.loadQueue([song('a'), song('b'), song('c'), song('d'), song('e')], currentIndex: 1);
      if (shuffle) {
        manager.toggleShuffle();
        manager.updateCurrentIndex(1);
      }
      final before = manager.currentQueue.map((song) => song.id).toList();
      final index = manager.currentIndex;
      expect(manager.reshuffleUpcoming(), isTrue);
      final after = manager.currentQueue.map((song) => song.id).toList();
      expect(after.take(index + 1), before.take(index + 1));
      expect(after.skip(index + 1).toSet(), before.skip(index + 1).toSet());
      expect(after.skip(index + 1).toList(), isNot(before.skip(index + 1).toList()));
      expect(manager.isShuffling, shuffle);
    }
  });

  test('reshuffle does nothing with fewer than two upcoming songs', () {
    final manager = ShuffleManager();
    expect(manager.reshuffleUpcoming(), isFalse);
    manager.loadQueue([song('a'), song('b')]);
    expect(manager.reshuffleUpcoming(), isFalse);
  });
}
