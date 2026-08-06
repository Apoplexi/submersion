import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media/domain/entities/media_source_type.dart';

/// Library health facets: rows whose backing file is missing (persisted
/// orphan flag) or rows attached to neither a dive nor a site.
enum MediaHealthFilter { missing, unlinked }

/// Cross-dive library filter. Compiled to SQL by MediaLibraryRepository;
/// all fields combine with AND. Phase 5 serializes this for smart albums.
class MediaLibraryFilter {
  const MediaLibraryFilter({
    this.mediaType,
    this.siteId,
    this.tripId,
    this.diveId,
    this.fromDate,
    this.toDate,
    this.sourceType,
    this.health,
  });

  final MediaType? mediaType;
  final String? siteId;
  final String? tripId;
  final String? diveId;

  /// Inclusive bounds applied to the sort key (takenAt, falling back to
  /// createdAt).
  final DateTime? fromDate;
  final DateTime? toDate;

  final MediaSourceType? sourceType;
  final MediaHealthFilter? health;

  static const MediaLibraryFilter none = MediaLibraryFilter();

  bool get isEmpty =>
      mediaType == null &&
      siteId == null &&
      tripId == null &&
      diveId == null &&
      fromDate == null &&
      toDate == null &&
      sourceType == null &&
      health == null;

  /// Sentinel-based copyWith so callers can explicitly clear a field back to
  /// null (the plain `??` idiom cannot).
  MediaLibraryFilter copyWith({
    Object? mediaType = _undefined,
    Object? siteId = _undefined,
    Object? tripId = _undefined,
    Object? diveId = _undefined,
    Object? fromDate = _undefined,
    Object? toDate = _undefined,
    Object? sourceType = _undefined,
    Object? health = _undefined,
  }) {
    return MediaLibraryFilter(
      mediaType: mediaType == _undefined
          ? this.mediaType
          : mediaType as MediaType?,
      siteId: siteId == _undefined ? this.siteId : siteId as String?,
      tripId: tripId == _undefined ? this.tripId : tripId as String?,
      diveId: diveId == _undefined ? this.diveId : diveId as String?,
      fromDate: fromDate == _undefined ? this.fromDate : fromDate as DateTime?,
      toDate: toDate == _undefined ? this.toDate : toDate as DateTime?,
      sourceType: sourceType == _undefined
          ? this.sourceType
          : sourceType as MediaSourceType?,
      health: health == _undefined ? this.health : health as MediaHealthFilter?,
    );
  }

  static const Object _undefined = Object();

  @override
  bool operator ==(Object other) {
    return other is MediaLibraryFilter &&
        other.mediaType == mediaType &&
        other.siteId == siteId &&
        other.tripId == tripId &&
        other.diveId == diveId &&
        other.fromDate == fromDate &&
        other.toDate == toDate &&
        other.sourceType == sourceType &&
        other.health == health;
  }

  @override
  int get hashCode => Object.hash(
    mediaType,
    siteId,
    tripId,
    diveId,
    fromDate,
    toDate,
    sourceType,
    health,
  );
}

/// Keyset cursor: the sort key (epoch millis of COALESCE(taken_at,
/// created_at)) and row id of the last entry on the previous page.
class MediaLibraryCursor {
  const MediaLibraryCursor({required this.sortKey, required this.id});

  final int sortKey;
  final String id;
}

/// One library row: the media item plus denormalized dive header fields for
/// the by-dive and timeline groupers.
class MediaLibraryEntry {
  const MediaLibraryEntry({
    required this.item,
    this.diveNumber,
    this.diveDateTime,
    this.siteName,
  });

  final MediaItem item;
  final int? diveNumber;
  final DateTime? diveDateTime;
  final String? siteName;
}

/// One page of library results. [nextCursor] is null on the last page.
class MediaLibraryPageResult {
  const MediaLibraryPageResult({required this.entries, this.nextCursor});

  final List<MediaLibraryEntry> entries;
  final MediaLibraryCursor? nextCursor;
}
