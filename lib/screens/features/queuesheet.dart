import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:drag_and_drop_lists/drag_and_drop_lists.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../components/empty_state.dart';
import '../../components/shimmers.dart';
import '../../models/datamodel.dart';
import '../../services/audiohandler.dart';
import '../../shared/constants.dart';
import '../../utils/theme.dart';

final queueStreamProvider = StreamProvider.autoDispose.family<List<MediaItem>, MyAudioHandler>(
  (ref, handler) => handler.queue,
);

class QueueList extends ConsumerWidget {
  final ScrollController scrollController;
  final Widget header;
  final bool showCurrentSong;

  const QueueList({required this.scrollController, required this.header, this.showCurrentSong = true, super.key});

  String _artistName(SongDetail song) {
    final names = song.contributors.all.map((a) => a.title).where((name) => name.isNotEmpty).toSet();
    return names.isNotEmpty ? names.join(', ') : song.primaryArtists;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(currentSongProvider);
    final handlerAsync = ref.watch(audioHandlerProvider);

    return handlerAsync.when(
      data: (handler) {
        final queueItemsAsync = ref.watch(queueStreamProvider(handler));

        return queueItemsAsync.when(
          data: (queueItems) {
            final currentIndex = handler.currentIndex;
            final songs = handler.queueSongs;

            if (currentIndex < 0 || currentIndex >= songs.length || currentIndex >= queueItems.length) {
              return ListView(
                controller: scrollController,
                children: [
                  header,
                  const EmptyState(
                    icon: LucideIcons.listMusic,
                    title: 'Queue is empty',
                    subtitle: 'Play a song to start your queue.',
                    compact: true,
                  ),
                ],
              );
            }

            final currentSong = songs[currentIndex];

            // Only upcoming songs
            final upcomingSongs = songs.sublist(currentIndex + 1);

            final items = List.generate(upcomingSongs.length, (index) {
              final song = upcomingSongs[index];

              return DragAndDropItem(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            final currentQueue = handler.queueSongs;
                            var selectedIndex = currentQueue.indexWhere((item) => identical(item, song));
                            if (selectedIndex < 0) {
                              selectedIndex = currentQueue.indexWhere(
                                (item) => item.id == song.id,
                                handler.currentIndex + 1,
                              );
                            }
                            if (selectedIndex > handler.currentIndex) handler.skipToQueueItem(selectedIndex);
                          },
                          child: Row(
                            children: [
                              CacheNetWorkImg(
                                url: song.images.isNotEmpty ? song.images.last.url : '',
                                width: 50,
                                height: 50,
                                fit: BoxFit.cover,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      song.title,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.normal,
                                        color: Colors.white,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      _artistName(song),
                                      style: const TextStyle(fontSize: 14, color: Colors.white70),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const DragHandle(
                        verticalAlignment: DragHandleVerticalAlignment.center,
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8.0),
                          child: Icon(Icons.drag_handle, color: Colors.white54),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            });

            return QueueSheetScroll(
              scrollController: scrollController,
              header: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  header,
                  // CURRENTLY PLAYING SONG
                  if (showCurrentSong)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                      color: Colors.transparent,
                      child: Row(
                        children: [
                          CacheNetWorkImg(
                            url: currentSong.images.isNotEmpty ? currentSong.images.last.url : '',
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                            borderRadius: BorderRadius.circular(6),
                          ),

                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  currentSong.title,
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: spotifyGreen),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  _artistName(currentSong),
                                  style: TextStyle(fontSize: 14, color: Colors.white70),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: Image.asset('assets/icons/player.gif', height: 18, fit: BoxFit.contain),
                          ),
                        ],
                      ),
                    ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Up next',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: upcomingSongs.length < 2
                              ? null
                              : () => handler.reshuffleUpcomingSongs(expectedCurrentId: currentSong.id),
                          icon: const Icon(LucideIcons.shuffle, size: 18),
                          label: const Text('Reshuffle'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white70,
                            disabledForegroundColor: Colors.white24,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(thickness: 1, color: Colors.white24),
                ],
              ),
              items: items,
              onReorder: (oldIndex, newIndex) {
                handler.reorderUpcomingSongs(oldIndex, newIndex, expectedCurrentId: currentSong.id);
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => ListView(
            controller: scrollController,
            children: [
              header,
              const EmptyState(
                icon: LucideIcons.circleAlert,
                title: 'Queue unavailable',
                subtitle: 'The queue could not be loaded. Please try again.',
                compact: true,
              ),
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => ListView(
        controller: scrollController,
        children: [
          header,
          const EmptyState(
            icon: LucideIcons.circleAlert,
            title: 'Queue unavailable',
            subtitle: 'The queue could not be loaded. Please try again.',
            compact: true,
          ),
        ],
      ),
    );
  }
}

class QueueSheetScroll extends StatelessWidget {
  final ScrollController scrollController;
  final Widget header;
  final List<DragAndDropItem> items;
  final void Function(int oldIndex, int newIndex) onReorder;

  const QueueSheetScroll({
    super.key,
    required this.scrollController,
    required this.header,
    required this.items,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) => DragAndDropLists(
    scrollController: scrollController,
    removeTopPadding: true,
    children: [
      DragAndDropList(
        canDrag: false,
        horizontalAlignment: MainAxisAlignment.start,
        verticalAlignment: CrossAxisAlignment.start,
        header: header,
        children: items,
        contentsWhenEmpty: const _QueueEmptyState(),
      ),
    ],
    onItemReorder: (oldIndex, oldList, newIndex, newList) => onReorder(oldIndex, newIndex),
    onListReorder: (_, __) {},
    listPadding: EdgeInsets.zero,
    itemDecorationWhileDragging: const BoxDecoration(
      color: Colors.black87,
      boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
    ),
    itemDivider: const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Divider(thickness: .8, color: Colors.white10),
    ),
    listInnerDecoration: const BoxDecoration(color: Colors.transparent),
    itemGhostOpacity: 0.2,
  );
}

class _QueueEmptyState extends StatelessWidget {
  const _QueueEmptyState();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(color: spotifyGreen.withValues(alpha: 0.10), shape: BoxShape.circle),
          child: const Icon(LucideIcons.listMusic, color: spotifyGreen, size: 25),
        ),
        const SizedBox(height: 12),
        const Text(
          'Nothing up next',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 16),
        ),
        const SizedBox(height: 6),
        const Text(
          'Add songs to your queue to keep listening.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
        ),
      ],
    ),
  );
}
