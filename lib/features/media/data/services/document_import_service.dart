import 'dart:io';

import 'package:uuid/uuid.dart';

import 'package:submersion/features/media/data/repositories/media_repository.dart';
import 'package:submersion/features/media/data/services/local_bookmark_storage.dart';
import 'package:submersion/features/media/data/services/local_media_platform.dart';
import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media/domain/entities/media_source_type.dart';

/// Links picked document files (PDFs and common formats) to a dive or a
/// site by reference: security-scoped bookmark on iOS/macOS, persisted SAF
/// URI on Android, plain path on Windows/Linux. Never copies bytes; the
/// media store upload (enqueued via [onMediaCreated]) is the durability
/// path. Mirrors FilesTabNotifier's per-platform persist logic.
class DocumentImportService {
  DocumentImportService({
    required this.mediaRepository,
    required this.platform,
    required this.bookmarkStorage,
    this.onMediaCreated,
  });

  final MediaRepository mediaRepository;
  final LocalMediaPlatform platform;
  final LocalBookmarkStorage bookmarkStorage;

  /// Invoked after every successful createMedia so the media store can
  /// enqueue an upload. Null when no store is configured.
  final void Function(String mediaId)? onMediaCreated;

  final _uuid = const Uuid();

  /// Formats offered by the document picker. `pdf` renders in-app; the
  /// rest are opaque attachments that open externally.
  static const List<String> allowedExtensions = [
    'pdf',
    'doc',
    'docx',
    'txt',
    'gpx',
  ];

  /// Persists each picked file as a `document` media row linked to exactly
  /// one of [diveId] / [siteId]. Returns the created rows.
  Future<List<MediaItem>> importDocuments({
    required List<({String path, String filename})> picked,
    String? diveId,
    String? siteId,
  }) async {
    assert(
      (diveId == null) != (siteId == null),
      'exactly one of diveId/siteId must be set',
    );
    final created = <MediaItem>[];
    for (final file in picked) {
      String? localPath;
      String? bookmarkRef;

      if (Platform.isIOS || Platform.isMacOS) {
        final blob = await platform.createBookmark(file.path);
        bookmarkRef = _uuid.v4();
        await bookmarkStorage.write(bookmarkRef, blob);
        if (Platform.isMacOS) {
          // Desktop UX needs the path for "Show in Finder"; the bookmark
          // stays the source of truth for resolution. iOS keeps localPath
          // null because the picker path is sandbox-scoped.
          localPath = file.path;
        }
      }
      // coverage:ignore-start
      // Android branch can only be exercised on an Android host (test suite
      // runs on macOS / Linux). Desktop fallback is exercised by Linux CI.
      else if (Platform.isAndroid) {
        // file.path on Android may already be a content URI from
        // file_picker. takePersistableUri makes it durable across reboots.
        bookmarkRef = await platform.takePersistableUri(file.path);
      } else {
        localPath = file.path;
      }
      // coverage:ignore-end

      final now = DateTime.now();
      final item = MediaItem(
        // Empty id triggers UUID generation in MediaRepository.createMedia.
        id: '',
        diveId: diveId,
        siteId: siteId,
        mediaType: MediaType.document,
        sourceType: MediaSourceType.localFile,
        originalFilename: file.filename,
        localPath: localPath,
        bookmarkRef: bookmarkRef,
        takenAt: now,
        createdAt: now,
        updatedAt: now,
      );
      final saved = await mediaRepository.createMedia(item);
      onMediaCreated?.call(saved.id);
      created.add(saved);
    }
    return created;
  }
}
