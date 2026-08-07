import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import 'package:submersion/core/services/logger_service.dart';
import 'package:submersion/features/media/data/repositories/media_repository.dart';
import 'package:submersion/features/media/data/services/repair/folder_candidate_source.dart';
import 'package:submersion/features/media/domain/entities/media_source_type.dart';
import 'package:submersion/features/media/domain/services/media_repair_types.dart';
import 'package:submersion/features/media_store/data/media_transfer_queue_repository.dart';

/// One accepted proposal's DB write, prepared by Stage A.
class RepairWrite {
  const RepairWrite({
    required this.mediaId,
    this.newLocalPath,
    this.newBookmarkRef,
    this.newPlatformAssetId,
    this.newSourceType = MediaSourceType.localFile,
  });

  final String mediaId;
  final String? newLocalPath;
  final String? newBookmarkRef;
  final String? newPlatformAssetId;

  /// The source type the repaired row RESOLVES as, which the repair always
  /// restates rather than inherits: a candidate file on disk means
  /// [MediaSourceType.localFile] even when the row arrived as a gallery
  /// asset, and [MediaSourceType.platformGallery] pairs with
  /// [newPlatformAssetId].
  final MediaSourceType newSourceType;
}

/// Outcome counts of one apply pass, in wizard-summary terms.
class RepairApplyReport {
  const RepairApplyReport({
    required this.relinked,
    required this.cloudBacked,
    required this.reuploadsQueued,
    required this.failed,
    required this.skipped,
  });

  final int relinked;
  final int cloudBacked;
  final int reuploadsQueued;
  final int failed;
  final int skipped;
}

/// Staged repair apply (design spec section 6).
///
/// Stage A runs the fallible per-row I/O -- hash verification (promoting
/// probable to exact or demoting it to changed-on-disk) and bookmark
/// regeneration -- collecting failures without poisoning the batch.
/// Stage B commits every surviving write in one repository transaction.
/// Stage C performs the store side effects: edited rows re-stamp content
/// identity, clear their remote stamps, and enqueue a re-upload (the store
/// must never serve stale bytes); store proposals convert to cloud-backed.
class MediaRepairService {
  MediaRepairService({
    required this.repository,
    required this.queue,
    required this.createBookmark,
    required this.writeBookmark,
  });

  final MediaRepository repository;
  final MediaTransferQueueRepository queue;

  /// Platform bookmark hooks (macOS/iOS); null elsewhere.
  final Future<Uint8List> Function(String path)? createBookmark;
  final Future<void> Function(String ref, Uint8List blob)? writeBookmark;

  static const _log = LoggerService('MediaRepairService');
  static const _uuid = Uuid();

  Future<RepairApplyReport> apply(List<RepairProposal> accepted) async {
    var failed = 0;
    var skipped = 0;
    var reuploadsQueued = 0;
    var cloudBacked = 0;

    final writes = <RepairWrite>[];
    final editedStamps = <({String mediaId, String hash, int sizeBytes})>[];
    final storeIds = <String>[];

    // Stage A: per-row I/O.
    for (final proposal in accepted) {
      final candidate = proposal.candidate;
      if (candidate == null) continue;

      try {
        if (candidate.isStore) {
          storeIds.add(proposal.item.id);
          continue;
        }

        if (candidate.isGallery) {
          writes.add(
            RepairWrite(
              mediaId: proposal.item.id,
              newPlatformAssetId: candidate.assetId,
              newSourceType: MediaSourceType.platformGallery,
            ),
          );
          continue;
        }

        // File candidate: verify bytes against the row's content identity.
        final hashed = candidate.hash != null
            ? candidate
            : await FolderCandidateSource.withHash(candidate);
        final rowHash = proposal.item.contentHash;
        final matches = rowHash == null || hashed.hash == rowHash;

        if (!matches && proposal.confidence != RepairConfidence.edited) {
          // A probable match whose bytes changed on disk: never silently
          // relink different content -- report it for another review pass.
          skipped++;
          continue;
        }

        String? newRef;
        final create = createBookmark;
        final write = writeBookmark;
        if (create != null && write != null) {
          final blob = await create(candidate.path!);
          newRef = proposal.item.bookmarkRef ?? _uuid.v4();
          await write(newRef, blob);
        }

        writes.add(
          RepairWrite(
            mediaId: proposal.item.id,
            newLocalPath: candidate.path,
            newBookmarkRef: newRef,
            // A file on disk resolves through LocalFileResolver whatever
            // the row used to be.
            newSourceType: MediaSourceType.localFile,
          ),
        );
        if (!matches) {
          editedStamps.add((
            mediaId: proposal.item.id,
            hash: hashed.hash!,
            sizeBytes: hashed.sizeBytes ?? 0,
          ));
        }
      } on Exception catch (e) {
        _log.warning('Repair failed for ${proposal.item.id}: $e');
        failed++;
      }
    }

    // Stage B: one transaction for every surviving write.
    await repository.applyRepairWrites(writes);

    // Stage C: store side effects.
    for (final stamp in editedStamps) {
      await repository.stampContentIdentity(
        stamp.mediaId,
        contentHash: stamp.hash,
        sizeBytes: stamp.sizeBytes,
      );
      await repository.clearRemoteUploaded(stamp.mediaId);
      await repository.clearRemoteThumbUploaded(stamp.mediaId);
      await repository.clearRemoteCompressed(stamp.mediaId);
      await queue.enqueueUpload(mediaId: stamp.mediaId);
      reuploadsQueued++;
    }
    if (storeIds.isNotEmpty) {
      await repository.convertToCloudBacked(storeIds);
      cloudBacked = storeIds.length;
    }

    return RepairApplyReport(
      relinked: writes.length,
      cloudBacked: cloudBacked,
      reuploadsQueued: reuploadsQueued,
      failed: failed,
      skipped: skipped,
    );
  }
}
