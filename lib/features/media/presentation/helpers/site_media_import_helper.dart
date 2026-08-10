import 'package:flutter/material.dart';

import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/media/presentation/pages/photo_picker_page.dart';
import 'package:submersion/features/media/presentation/providers/media_providers.dart';
import 'package:submersion/features/media/presentation/providers/photo_picker_providers.dart';
import 'package:submersion/features/media/presentation/providers/site_media_providers.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// Helper for importing photos as direct site attachments.
///
/// Opens the photo picker without a dive time window (a site has no entry/
/// exit times), imports the selection, and refreshes the site providers.
class SiteMediaImportHelper {
  /// Opens the photo picker and imports the selection for [siteId].
  ///
  /// Returns true if anything was imported.
  static Future<bool> importPhotosForSite({
    required BuildContext context,
    required WidgetRef ref,
    required String siteId,
  }) async {
    final mediaRepo = ref.read(mediaRepositoryProvider);
    final alreadyLinkedIds = await mediaRepo.getLinkedAssetIdsForSite(siteId);
    if (!context.mounted) return false;

    // Sites have no dive window: open the picker over all time. buffer is
    // zeroed so showPhotoPicker does not widen the range further.
    // coverage:ignore-start
    // showPhotoPicker drives a full-screen page tied to photo_manager + the
    // platform photo library; not unit-testable from flutter_test.
    final selectedAssets = await showPhotoPicker(
      context: context,
      diveStartTime: DateTime.fromMillisecondsSinceEpoch(0),
      diveEndTime: DateTime.now().add(const Duration(days: 1)),
      buffer: Duration.zero,
      alreadyLinkedIds: alreadyLinkedIds,
    );
    // coverage:ignore-end
    if (selectedAssets == null || selectedAssets.isEmpty || !context.mounted) {
      return false;
    }

    try {
      final importService = ref.read(mediaImportServiceProvider);
      final result = await importService.importPhotosForSite(
        selectedAssets: selectedAssets,
        siteId: siteId,
      );

      ref.invalidate(mediaForSiteProvider(siteId));
      ref.invalidate(mediaCountForSiteProvider(siteId));

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.media_import_importedPhotos(result.imported.length),
            ),
          ),
        );
      }
      return result.imported.isNotEmpty;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.media_import_failedToImportError(e.toString()),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return false;
    }
  }
}
