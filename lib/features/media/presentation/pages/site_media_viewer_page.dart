import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:share_plus/share_plus.dart';

import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/media/data/services/media_share_temp_file.dart';
import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media/presentation/providers/resolved_asset_providers.dart';
import 'package:submersion/features/media/presentation/providers/site_media_providers.dart';
import 'package:submersion/features/media/presentation/widgets/media_item_view.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// Which list of site-related media backs the viewer's pager.
enum SiteViewerScope {
  /// Media directly attached to the site (maps, entry points, parking).
  attachments,

  /// Photos aggregated from dives logged at the site.
  divePhotos,
}

/// Full-screen photo/video viewer for a site's media.
///
/// Modeled on TripPhotoViewerPage without the dive-context overlays: site
/// attachments have no dive profile to position against. Documents never
/// enter the pager (they open in DocumentViewerPage), so the backing list
/// is filtered here as a final guard.
class SiteMediaViewerPage extends ConsumerStatefulWidget {
  final String siteId;
  final String initialMediaId;
  final SiteViewerScope scope;

  const SiteMediaViewerPage({
    super.key,
    required this.siteId,
    required this.initialMediaId,
    required this.scope,
  });

  @override
  ConsumerState<SiteMediaViewerPage> createState() =>
      _SiteMediaViewerPageState();
}

class _SiteMediaViewerPageState extends ConsumerState<SiteMediaViewerPage> {
  late PageController _pageController;
  int _currentIndex = 0;
  bool _showOverlay = true;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    // Set immersive mode for full-screen experience
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.immersiveSticky,
      overlays: [],
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    // Restore system UI
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
      overlays: SystemUiOverlay.values,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sourceAsync = widget.scope == SiteViewerScope.attachments
        ? ref.watch(mediaForSiteProvider(widget.siteId))
        : ref.watch(flatMediaFromDivesAtSiteProvider(widget.siteId));
    final mediaAsync = sourceAsync.whenData(
      (list) => list.where((m) => !m.isDocument).toList(),
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: mediaAsync.when(
        data: (mediaList) {
          if (mediaList.isEmpty) {
            return Center(
              child: Text(
                context.l10n.media_photoViewer_noPhotosAvailable,
                style: const TextStyle(color: Colors.white),
              ),
            );
          }

          // Find initial index
          final initialIndex = mediaList.indexWhere(
            (m) => m.id == widget.initialMediaId,
          );
          if (initialIndex != -1 && _pageController.hasClients == false) {
            _currentIndex = initialIndex;
            // hasClients == false means no PageView is attached, so the
            // outgoing controller is safe to dispose; without this the one
            // built in initState leaks.
            _pageController.dispose();
            _pageController = PageController(initialPage: initialIndex);
          }

          final currentItem = mediaList[_currentIndex];

          return GestureDetector(
            // Swipe down to close (common pattern for fullscreen viewers)
            onVerticalDragEnd: (details) {
              if (details.primaryVelocity != null &&
                  details.primaryVelocity! > 300) {
                Navigator.of(context).pop();
              }
            },
            child: Stack(
              children: [
                _MediaGalleryPager(
                  mediaList: mediaList,
                  pageController: _pageController,
                  onPageChanged: (index) {
                    setState(() => _currentIndex = index);
                  },
                ),

                // Transparent tap target to toggle overlays
                Positioned.fill(
                  child: Semantics(
                    label: context.l10n.media_photoViewer_toggleOverlayLabel,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => setState(() => _showOverlay = !_showOverlay),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),

                if (_showOverlay) ...[
                  _TopOverlay(
                    currentIndex: _currentIndex,
                    totalCount: mediaList.length,
                    onClose: () => Navigator.of(context).pop(),
                    onShare: () => _shareCurrentItem(currentItem),
                  ),
                  _BottomMetadataOverlay(item: currentItem),
                ],
              ],
            ),
          );
        },
        loading: () =>
            const Center(child: CircularProgressIndicator(color: Colors.white)),
        error: (error, stack) => Center(
          child: Text(
            context.l10n.media_photoViewer_errorLoadingPhotos(error.toString()),
            style: const TextStyle(color: Colors.white),
          ),
        ),
      ),
    );
  }

  Future<void> _shareCurrentItem(MediaItem item) async {
    final l10n = context.l10n;

    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const Center(child: CircularProgressIndicator(color: Colors.white)),
    );

    try {
      final resolvedResult = await ref.read(
        resolvedFullResolutionProvider(item).future,
      );

      if (resolvedResult.isUnavailable || resolvedResult.bytes == null) {
        if (mounted) Navigator.of(context, rootNavigator: true).pop();
        _showError(l10n.media_photoViewer_cannotShare);
        return;
      }

      final file = await writeShareTempFile(item, resolvedResult.bytes!);

      // Dismiss loading - use rootNavigator to match where showDialog placed it
      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path, mimeType: item.shareMimeType)]),
      );
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      _showError(l10n.media_photoViewer_failedToShare(e.toString()));
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }
}

/// The gallery pager using PhotoView for zoom support.
class _MediaGalleryPager extends StatelessWidget {
  final List<MediaItem> mediaList;
  final PageController pageController;
  final ValueChanged<int> onPageChanged;

  const _MediaGalleryPager({
    required this.mediaList,
    required this.pageController,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return PhotoViewGallery.builder(
      scrollPhysics: const BouncingScrollPhysics(),
      pageController: pageController,
      itemCount: mediaList.length,
      onPageChanged: onPageChanged,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      builder: (context, index) {
        final item = mediaList[index];
        return PhotoViewGalleryPageOptions.customChild(
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3.0,
          child: MediaItemView(item: item, fit: BoxFit.contain),
        );
      },
      loadingBuilder: (context, event) =>
          const Center(child: CircularProgressIndicator(color: Colors.white54)),
    );
  }
}

/// Top overlay with close button, page indicator, and share button.
class _TopOverlay extends StatelessWidget {
  final int currentIndex;
  final int totalCount;
  final VoidCallback onClose;
  final VoidCallback onShare;

  const _TopOverlay({
    required this.currentIndex,
    required this.totalCount,
    required this.onClose,
    required this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.7), Colors.transparent],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: context.l10n.media_photoViewer_closeTooltip,
                  onPressed: onClose,
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      context.l10n.media_photoViewer_pageIndicator(
                        currentIndex + 1,
                        totalCount,
                      ),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.share, color: Colors.white),
                  tooltip: context.l10n.media_photoViewer_shareTooltip,
                  onPressed: onShare,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom overlay showing capture time and caption for the current item.
class _BottomMetadataOverlay extends StatelessWidget {
  final MediaItem item;

  const _BottomMetadataOverlay({required this.item});

  @override
  Widget build(BuildContext context) {
    final timeFormat = DateFormat.jm();
    final dateFormat = DateFormat.yMMMd();

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 32, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.caption != null && item.caption!.isNotEmpty) ...[
                  Text(
                    item.caption!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  '${dateFormat.format(item.takenAt)} at ${timeFormat.format(item.takenAt)}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.8),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
