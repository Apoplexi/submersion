import 'package:submersion/core/providers/provider.dart';

import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media/presentation/providers/media_providers.dart';

/// Newest dive photos for the dashboard ribbon.
///
/// Self-invalidates on the media-table change tick so the ribbon reflects
/// deletions, imports and syncs without a pull-to-refresh. A photo deleted
/// from the dive gallery, the files tab, or a dive-deletion cascade removes
/// its `media` row directly, and none of those paths knows about this
/// dashboard provider; before the tick subscription the ribbon kept rendering
/// the deleted photo as a dead tile until the app restarted.
final recentPhotosProvider = FutureProvider<List<MediaItem>>((ref) async {
  final repository = ref.watch(mediaRepositoryProvider);
  ref.invalidateSelfWhen(repository.watchMediaChanges());
  return repository.getRecentPhotos(limit: 12);
});
