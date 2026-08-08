import 'dart:math' as math;

import 'package:submersion/core/utils/geo_math.dart';
import 'package:submersion/features/dive_sites/domain/entities/dive_site.dart';
import 'package:submersion/features/gps_log/domain/entities/gps_track.dart';

/// Metres per degree of latitude (constant everywhere on a sphere).
const double _metersPerDegreeLatitude = 111194.93;

/// Projects [p] into a local flat east/north plane in metres, anchored at
/// [origin].
///
/// A dive-day track spans kilometres, so the flat-earth error over that span
/// is far below the tightest simplification tolerance (2 m). Working in this
/// plane makes perpendicular point-to-segment distance trivial, which is what
/// Douglas-Peucker needs.
({double east, double north}) projectLocal(
  GpsTrackPoint origin,
  GpsTrackPoint p,
) {
  final metersPerLon = metersPerDegreeLongitude(origin.latitude);
  return (
    east: (p.longitude - origin.longitude) * metersPerLon,
    north: (p.latitude - origin.latitude) * _metersPerDegreeLatitude,
  );
}

/// Perpendicular distance in metres from [point] to the segment [a]-[b].
double _perpendicularDistance(
  ({double east, double north}) point,
  ({double east, double north}) a,
  ({double east, double north}) b,
) {
  final dx = b.east - a.east;
  final dy = b.north - a.north;
  final lengthSquared = dx * dx + dy * dy;

  // Degenerate segment: fall back to straight point-to-point distance.
  if (lengthSquared == 0) {
    final px = point.east - a.east;
    final py = point.north - a.north;
    return math.sqrt(px * px + py * py);
  }

  // Project onto the segment, clamped to its extent.
  var t =
      ((point.east - a.east) * dx + (point.north - a.north) * dy) /
      lengthSquared;
  t = t.clamp(0.0, 1.0);

  final projectedX = a.east + t * dx;
  final projectedY = a.north + t * dy;
  final ex = point.east - projectedX;
  final ey = point.north - projectedY;
  return math.sqrt(ex * ex + ey * ey);
}

/// Reduces [points] to the subset whose maximum perpendicular deviation from
/// the retained polyline stays within [toleranceMeters] (Douglas-Peucker).
///
/// First and last points are always retained. Surviving points keep their
/// original timestamps and accuracy - this decimates, it never interpolates.
List<GpsTrackPoint> simplifyTrack(
  List<GpsTrackPoint> points,
  double toleranceMeters,
) {
  if (points.length < 3) return List.unmodifiable(points);

  final origin = points.first;
  final projected = [for (final p in points) projectLocal(origin, p)];
  final keep = List<bool>.filled(points.length, false);
  keep[0] = true;
  keep[points.length - 1] = true;

  // Iterative rather than recursive: a 21k-point track would risk a deep
  // recursion on pathological input.
  final stack = <({int start, int end})>[(start: 0, end: points.length - 1)];

  while (stack.isNotEmpty) {
    final segment = stack.removeLast();
    var maxDistance = 0.0;
    var maxIndex = -1;

    for (var i = segment.start + 1; i < segment.end; i++) {
      final distance = _perpendicularDistance(
        projected[i],
        projected[segment.start],
        projected[segment.end],
      );
      if (distance > maxDistance) {
        maxDistance = distance;
        maxIndex = i;
      }
    }

    if (maxIndex != -1 && maxDistance > toleranceMeters) {
      keep[maxIndex] = true;
      stack.add((start: segment.start, end: maxIndex));
      stack.add((start: maxIndex, end: segment.end));
    }
  }

  return List.unmodifiable([
    for (var i = 0; i < points.length; i++)
      if (keep[i]) points[i],
  ]);
}

/// Converts a track point to the [GeoPoint] the shared geo helpers take.
GeoPoint toGeoPoint(GpsTrackPoint p) => GeoPoint(p.latitude, p.longitude);
