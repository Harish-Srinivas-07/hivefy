import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:drag_and_drop_lists/drag_and_drop_lists.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../components/shimmers.dart';
import '../services/audiohandler.dart';

final queueStreamProvider = StreamProvider.autoDispose
    .family<List<MediaItem>, MyAudioHandler>((ref, handler) => handler.queue);

class QueueList extends ConsumerWidget {
  final ScrollController scrollController;

  const QueueList({required this.scrollController, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handlerAsync = ref.watch(audioHandlerProvider);

    return handlerAsync.when(
      data: (handler) {
        final queueItemsAsync = ref.watch(queueStreamProvider(handler));

        return queueItemsAsync.when(
          data: (queueItems) {
            final currentIndex = handler.currentIndex;

            if (currentIndex < 0 || currentIndex >= queueItems.length) {
              return const SizedBox.shrink();
            }

            final currentSong = handler.queueSongs[currentIndex];

            // Only upcoming songs
            final upcomingSongs = handler.queueSongs.sublist(currentIndex + 1);

            final items = List.generate(upcomingSongs.length, (index) {
              final song = upcomingSongs[index];

              return DragAndDropItem(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 3,
                    horizontal: 16,
                  ),
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
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.normal,
                                color: Colors.white,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              song.contributors.all.first.title,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
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

            return Column(
              children: [
                // CURRENTLY PLAYING SONG
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 16,
                  ),
                  color: Colors.black26,
                  child: Row(
                    children: [
                      CacheNetWorkImg(
                        url:
                            currentSong.images.isNotEmpty
                                ? currentSong.images.last.url
                                : '',
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
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.greenAccent,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              currentSong.contributors.all.first.title,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.white70,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: Image.asset(
                          'assets/player.gif',
                          height: 18,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ],
                  ),
                ),

                // UPCOMING SONGS LIST
                Expanded(
                  child: DragAndDropLists(
                    scrollController: scrollController,
                    children: [DragAndDropList(children: items)],
                    onItemReorder: (
                      oldItemIndex,
                      oldListIndex,
                      newItemIndex,
                      newListIndex,
                    ) {
                      // Offset by currentIndex + 1 to match full queue
                      handler.reorderQueue(
                        oldItemIndex + currentIndex + 1,
                        newItemIndex + currentIndex + 1,
                      );
                    },
                    onListReorder: (oldListIndex, newListIndex) {
                      // No list reordering needed
                    },
                    listPadding: const EdgeInsets.symmetric(
                      horizontal: 0,
                      vertical: 8,
                    ),
                    itemDecorationWhileDragging: BoxDecoration(
                      color: Colors.black87,
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 4),
                      ],
                    ),
                    itemDivider: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Divider(thickness: .8, color: Colors.white12),
                    ),
                    listInnerDecoration: const BoxDecoration(
                      color: Colors.transparent,
                    ),
                    itemGhostOpacity: 0.2,
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error:
              (_, __) => Center(
                child: Text(
                  'Error loading queue',
                  style: TextStyle(color: Colors.white),
                ),
              ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error:
          (_, __) => Center(
            child: Text(
              'Error loading handler',
              style: TextStyle(color: Colors.white),
            ),
          ),
    );
  }
}
