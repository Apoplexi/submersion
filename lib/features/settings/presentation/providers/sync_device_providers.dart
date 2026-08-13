import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:submersion/core/services/sync/sync_cleanup_outcome.dart';
import 'package:submersion/core/services/sync/sync_device_footprint.dart';
import 'package:submersion/core/services/sync/sync_device_footprints.dart';
import 'package:submersion/features/settings/presentation/providers/sync_providers.dart';

final syncDeviceFootprintsProvider = Provider<SyncDeviceFootprints>(
  (ref) => SyncDeviceFootprints(),
);

/// Every device's footprint on the active backend.
///
/// A network read, so it is a FutureProvider the page can refresh explicitly
/// rather than anything the app polls -- a user opens this once to work out
/// where their cloud space went (issue #1032), not continuously.
final syncDeviceFootprintListProvider =
    FutureProvider.autoDispose<List<SyncDeviceFootprint>>((ref) async {
      final provider = ref.watch(cloudStorageProviderProvider);
      // Null in custom-folder mode and when no backend is chosen. An empty list
      // reads correctly in the UI as "nothing to show".
      if (provider == null) return const [];
      final repo = ref.watch(syncRepositoryProvider);
      return ref
          .watch(syncDeviceFootprintsProvider)
          .list(
            provider: provider,
            selfDeviceId: await repo.getDeviceId(),
            currentEpochId: await repo.getLastAcceptedEpochId(),
          );
    });

/// Retire one peer and delete its files, then refresh the listing.
///
/// Returns a null outcome when no backend is configured, which the caller
/// reports rather than treating as success.
Future<SyncCleanupOutcome?> retireSyncPeer(
  WidgetRef ref,
  String deviceId, {
  SyncCleanupProgress? onProgress,
}) async {
  final provider = ref.read(cloudStorageProviderProvider);
  if (provider == null) return null;
  final repo = ref.read(syncRepositoryProvider);
  final outcome = await ref
      .read(syncDeviceFootprintsProvider)
      .retirePeer(
        provider: provider,
        deviceId: deviceId,
        selfDeviceId: await repo.getDeviceId(),
        onProgress: onProgress,
      );
  ref.invalidate(syncDeviceFootprintListProvider);
  return outcome;
}
