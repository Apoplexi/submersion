import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show DateTimeRange;

import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/dive_log/presentation/providers/dive_providers.dart';
import 'package:submersion/features/gps_log/data/repositories/track_geometry_cache_repository.dart';
import 'package:submersion/features/gps_log/domain/entities/gps_track.dart';
import 'package:submersion/features/gps_log/domain/gps_track_matcher.dart';
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

/// Wall-clock-as-UTC epoch milliseconds for a dive's entry.
///
/// millisecondsSinceEpoch is absolute regardless of the DateTime's utc flag,
/// so this compares directly against gps_tracks.startTime, which stores the
/// same wall-clock-as-UTC value.
int _entryMillis(Dive dive) => dive.effectiveEntryTime.millisecondsSinceEpoch;

/// Dives whose entry falls inside [trackId]'s recording window.
///
/// Uses [GpsTrackMatcher.trackCovering] rather than a bare range test so the
/// markers show exactly the dives this track could have stamped - same
/// 30-minute tolerance the match sweep applies.
final divesOnTrackProvider = FutureProvider.family<List<Dive>, String>((
  ref,
  trackId,
) async {
  final track = await ref.watch(gpsTrackDetailProvider(trackId).future);
  // An in-progress track has no closed window to test dives against.
  if (track == null || track.endTime == null) return const [];

  final dives = await ref.watch(divesProvider.future);
  return [
    for (final dive in dives)
      if (GpsTrackMatcher.trackCovering([track], _entryMillis(dive)) != null)
        dive,
  ];
});

/// The track, if any, whose window covers [diveId].
final trackForDiveProvider = FutureProvider.family<GpsTrack?, String>((
  ref,
  diveId,
) async {
  final dive = await ref.watch(diveProvider(diveId).future);
  if (dive == null) return null;

  // Lean read first - never decode every blob just to find the match.
  final tracks = await ref
      .watch(gpsTrackRepositoryProvider)
      .getCompletedTracks(includePoints: false);
  final match = GpsTrackMatcher.trackCovering(tracks, _entryMillis(dive));
  if (match == null) return null;
  return ref.watch(gpsTrackDetailProvider(match.id).future);
});

/// Optional date bound on the overview map.
///
/// Null means unbounded. Track start times are wall-clock-as-UTC, so the
/// range's DateTime values compare against them directly with no conversion.
final trackDateFilterProvider = StateProvider<DateTimeRange?>((ref) => null);

/// Completed tracks narrowed by [trackDateFilterProvider].
///
/// "Every track ever" is the one query in this feature that grows without
/// bound, so the overview map reads through this rather than gpsTracksProvider.
final filteredTracksProvider = FutureProvider<List<GpsTrack>>((ref) async {
  final tracks = await ref.watch(gpsTracksProvider.future);
  final range = ref.watch(trackDateFilterProvider);
  if (range == null) return tracks;

  final from = range.start.millisecondsSinceEpoch;
  // Inclusive of the end date's full day.
  final to = range.end
      .add(const Duration(days: 1))
      .subtract(const Duration(milliseconds: 1))
      .millisecondsSinceEpoch;

  return [
    for (final track in tracks)
      if (track.startTime >= from && track.startTime <= to) track,
  ];
});

/// Active colorization mode on the track detail map.
///
/// Held outside the geometry providers on purpose: changing it must re-run
/// bucketizeTrack only, never the decode or the simplify.
final trackColorModeProvider = StateProvider<TrackColorMode>(
  (ref) => TrackColorMode.uniform,
);
