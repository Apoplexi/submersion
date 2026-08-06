import 'package:flutter/material.dart';

import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media/domain/entities/media_library_filter.dart';
import 'package:submersion/features/media/presentation/providers/media_library_providers.dart';
import 'package:submersion/features/media/presentation/widgets/media_library_grid.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// The Library section content: type filter chips over the active view mode.
/// The by-dive and timeline presentations reuse the same paged state.
class MediaLibraryView extends ConsumerWidget {
  const MediaLibraryView({super.key});

  void _setTypeFilter(WidgetRef ref, MediaType? type) {
    final notifier = ref.read(mediaLibraryFilterProvider.notifier);
    notifier.state = notifier.state.copyWith(mediaType: type);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(mediaLibraryNotifierProvider);
    final filter = ref.watch(mediaLibraryFilterProvider);
    final mode = ref.watch(mediaLibraryViewModeProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      FilterChip(
                        label: Text(context.l10n.media_library_filter_all),
                        selected: filter.mediaType == null,
                        onSelected: (_) => _setTypeFilter(ref, null),
                      ),
                      const SizedBox(width: 6),
                      FilterChip(
                        label: Text(context.l10n.media_library_filter_photos),
                        selected: filter.mediaType == MediaType.photo,
                        onSelected: (_) => _setTypeFilter(ref, MediaType.photo),
                      ),
                      const SizedBox(width: 6),
                      FilterChip(
                        label: Text(context.l10n.media_library_filter_videos),
                        selected: filter.mediaType == MediaType.video,
                        onSelected: (_) => _setTypeFilter(ref, MediaType.video),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody(context, ref, state, mode)),
      ],
    );
  }

  Widget _buildBody(
    BuildContext context,
    WidgetRef ref,
    MediaLibraryState state,
    MediaLibraryViewMode mode,
  ) {
    if (state.isLoading && state.entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.entries.isEmpty) {
      return Center(child: Text(context.l10n.media_library_empty));
    }
    // The by-dive and timeline groupers land with the view-mode switcher;
    // until then every mode renders the flat grid.
    return MediaLibraryGrid(
      entries: state.entries,
      hasMore: state.hasMore,
      onLoadMore: () =>
          ref.read(mediaLibraryNotifierProvider.notifier).loadMore(),
      onTileTap: (entry, index) {},
    );
  }
}
