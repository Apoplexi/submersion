import 'dart:ui' show Size;

import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media/domain/entities/media_source_type.dart';
import 'package:submersion/features/media/domain/services/media_source_resolver.dart';
import 'package:submersion/features/media/domain/value_objects/media_source_data.dart';
import 'package:submersion/features/media/domain/value_objects/media_source_metadata.dart';
import 'package:submersion/features/media/domain/value_objects/verify_result.dart';

/// Test double for the localFile resolver: serves whatever
/// [MediaSourceData] the test assigns.
class FakeLocalFileResolver implements MediaSourceResolver {
  FakeLocalFileResolver([MediaSourceData? initial])
    : data = initial ?? const UnavailableData(kind: UnavailableKind.notFound);

  MediaSourceData data;

  /// When set, resolveThumbnail serves this instead of [data] (models the
  /// gallery resolver's pre-compressed poster bytes for videos).
  MediaSourceData? thumbnailData;

  @override
  MediaSourceType get sourceType => MediaSourceType.localFile;

  @override
  bool canResolveOnThisDevice(MediaItem item) => true;

  @override
  Future<MediaSourceData> resolve(MediaItem item) async => data;

  @override
  Future<MediaSourceData> resolveThumbnail(
    MediaItem item, {
    required Size target,
  }) async => thumbnailData ?? data;

  @override
  Future<MediaSourceMetadata?> extractMetadata(MediaItem item) async => null;

  @override
  Future<VerifyResult> verify(MediaItem item) async => VerifyResult.available;
}
