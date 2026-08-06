import 'package:flutter/material.dart';

import 'package:submersion/features/media/domain/entities/media_library_filter.dart';
import 'package:submersion/features/media/presentation/widgets/media_item_view.dart';

/// Flat thumbnail grid over library entries with near-end load-more.
///
/// Purely presentational: paging state lives in the library notifier; this
/// widget only reports "the user is close to the bottom" via [onLoadMore].
class MediaLibraryGrid extends StatelessWidget {
  const MediaLibraryGrid({
    super.key,
    required this.entries,
    required this.hasMore,
    required this.onLoadMore,
    required this.onTileTap,
  });

  final List<MediaLibraryEntry> entries;
  final bool hasMore;
  final VoidCallback onLoadMore;
  final void Function(MediaLibraryEntry entry, int index) onTileTap;

  static const double _loadMoreThreshold = 400;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (hasMore &&
            notification.metrics.pixels >=
                notification.metrics.maxScrollExtent - _loadMoreThreshold) {
          onLoadMore();
        }
        return false;
      },
      child: GridView.builder(
        padding: const EdgeInsets.all(4),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 140,
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
        ),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          return GestureDetector(
            onTap: () => onTileTap(entry, index),
            child: MediaItemView(
              item: entry.item,
              thumbnail: true,
              targetSize: const Size(200, 200),
              fit: BoxFit.cover,
            ),
          );
        },
      ),
    );
  }
}
