// Uint8List comes from drift's re-export; a dart:typed_data import here is
// flagged as unnecessary, and infos are fatal in CI.
import 'package:drift/drift.dart';

import 'package:submersion/core/database/local_cache_database.dart';
import 'package:submersion/core/services/local_cache_database_service.dart';
import 'package:submersion/features/gps_log/domain/entities/gps_track.dart';
import 'package:submersion/features/gps_log/domain/track_point_codec.dart';

/// Level of detail for simplified track geometry.
enum TrackLod {
  /// Row thumbnails and unselected tracks on the overview map.
  thumbnail,

  /// Selected track on the overview map, detail page zoomed out.
  overview,

  /// Detail page at high zoom.
  detail;

  /// Douglas-Peucker tolerance in metres. Expressed in metres rather than
  /// pixels so simplification is independent of screen density.
  double get toleranceMeters => switch (this) {
    TrackLod.thumbnail => 50.0,
    TrackLod.overview => 10.0,
    TrackLod.detail => 2.0,
  };
}

/// Reads and writes simplified geometry in the local (unsynced) cache.
///
/// Constructed with no arguments and resolving the database through
/// [LocalCacheDatabaseService.instance], matching GpsTrackRepository's
/// convention of `AppDatabase get _db => DatabaseService.instance.database`.
class TrackGeometryCacheRepository {
  LocalCacheDatabase get _db => LocalCacheDatabaseService.instance.database;

  /// Cached geometry, or null on a cache miss.
  ///
  /// An empty list is a real answer (the track has no drawable points) and
  /// is distinct from null (nothing cached yet).
  Future<List<GpsTrackPoint>?> read(String trackId, TrackLod lod) async {
    final row =
        await (_db.select(_db.gpsTrackGeometryCache)
              ..where((t) => t.trackId.equals(trackId))
              ..where((t) => t.lodLevel.equals(lod.name)))
            .getSingleOrNull();
    if (row == null) return null;
    if (row.status != 'ok') return const [];
    final blob = row.points;
    if (blob == null) return const [];
    return decodeTrackPoints(Uint8List.fromList(blob));
  }

  Future<void> write(
    String trackId,
    TrackLod lod,
    List<GpsTrackPoint> points,
  ) async {
    await _db
        .into(_db.gpsTrackGeometryCache)
        .insertOnConflictUpdate(
          GpsTrackGeometryCacheCompanion.insert(
            trackId: trackId,
            lodLevel: lod.name,
            status: points.isEmpty ? 'empty' : 'ok',
            createdAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            points: points.isEmpty
                ? const Value.absent()
                : Value(encodeTrackPoints(points)),
          ),
        );
  }

  /// Drops every cached LOD for [trackId]. Called after a trim or split
  /// changes which points the track represents.
  Future<void> invalidate(String trackId) async {
    await (_db.delete(
      _db.gpsTrackGeometryCache,
    )..where((t) => t.trackId.equals(trackId))).go();
  }
}
