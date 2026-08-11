import 'package:flutter/material.dart';
import 'package:submersion/core/providers/provider.dart';

import 'package:submersion/features/dashboard/presentation/providers/photo_providers.dart';
import 'package:submersion/features/media/presentation/pages/photo_viewer_page.dart';
import 'package:submersion/features/media/presentation/widgets/media_item_view.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// Horizontal ribbon of the newest dive photos.
class PhotoRibbonCard extends ConsumerWidget {
  const PhotoRibbonCard({super.key});

  /// Opens the full-screen viewer on the photo itself, with the rest of its
  /// dive's gallery swipeable alongside it. Pushed on the root navigator
  /// because the dashboard sits inside the shell route, whose bottom nav
  /// would otherwise render over the immersive viewer.
  void _openViewer(BuildContext context, String diveId, String mediaId) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) =>
            PhotoViewerPage(diveId: diveId, initialMediaId: mediaId),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photosAsync = ref.watch(recentPhotosProvider);
    final photos = photosAsync.valueOrNull ?? const [];
    if (photos.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.dashboard_photos_title,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final item = photos[index];
                  final diveId = item.diveId;
                  return InkWell(
                    onTap: diveId == null
                        ? null
                        : () => _openViewer(context, diveId, item.id),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        width: 128,
                        child: MediaItemView(item: item, thumbnail: true),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
