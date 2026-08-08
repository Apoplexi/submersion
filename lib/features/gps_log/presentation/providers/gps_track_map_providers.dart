import 'package:flutter/foundation.dart';

import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/gps_log/data/repositories/track_geometry_cache_repository.dart';
import 'package:submersion/features/gps_log/domain/entities/gps_track.dart';
import 'package:submersion/features/gps_log/domain/track_colorization.dart';
import 'package:submersion/features/gps_log/domain/track_geometry.dart';
import 'package:submersion/features/gps_log/presentation/providers/gps_log_providers.dart';

/// Argument bundle for the isolate. compute() takes exactly one argument.
class _SimplifyRequest {
  final List<GpsTrackPoint> points;
  final double toleranceMeters;

  const _SimplifyRequest(this.points, this.toleranceMeters);
}

/// Top-level so it can run in an isolate.
List<GpsTrackPoint> _simplifyInIsolate(_SimplifyRequest request) =>
    simplifyTrack(request.points, request.toleranceMeters);

final trackGeometryCacheRepositoryProvider =
    Provider<TrackGeometryCacheRepository>(
      (ref) => TrackGeometryCacheRepository(),
    );

/// A single hydrated track, points blob decoded. This is the expensive step
/// and it happens once per track.
final gpsTrackDetailProvider = FutureProvider.family<GpsTrack?, String>((
  ref,
  trackId,
) async {
  return ref
      .watch(gpsTrackRepositoryProvider)
      .getTrack(trackId, includePoints: true);
});

/// Simplified geometry at a given level of detail, cached across launches.
final gpsTrackGeometryProvider =
    FutureProvider.family<List<GpsTrackPoint>, (String, TrackLod)>((
      ref,
      key,
    ) async {
      final (trackId, lod) = key;
      final cache = ref.watch(trackGeometryCacheRepositoryProvider);

      final cached = await cache.read(trackId, lod);
      if (cached != null) return cached;

      final track = await ref.watch(gpsTrackDetailProvider(trackId).future);
      if (track == null) return const [];

      // Read through effectivePoints so trim bounds are honoured before
      // simplification rather than after.
      final simplified = await compute(
        _simplifyInIsolate,
        _SimplifyRequest(track.effectivePoints, lod.toleranceMeters),
      );
      await cache.write(trackId, lod, simplified);
      return simplified;
    });

/// Active colorization mode on the track detail map.
///
/// Held outside the geometry providers on purpose: changing it must re-run
/// bucketizeTrack only, never the decode or the simplify.
final trackColorModeProvider = StateProvider<TrackColorMode>(
  (ref) => TrackColorMode.uniform,
);
