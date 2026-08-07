import 'package:submersion/features/dive_sites/domain/entities/dive_site.dart';
import 'package:submersion/features/weather/data/services/elevation_service.dart';

/// Result of an altitude resolution.
///
/// [siteWriteBack] is non-null only when the altitude came from a lookup of
/// the site's own coordinates: the caller should persist it so future dives
/// at that site resolve locally without a network call.
class AltitudeResolution {
  const AltitudeResolution({this.altitudeMeters, this.siteWriteBack});

  final double? altitudeMeters;
  final DiveSite? siteWriteBack;
}

/// Encodes the altitude precedence rule from the 2026-08-06 conditions spec:
/// dive GPS lookup, then the site's stored altitude, then a site-coordinates
/// lookup with write-back. Auto-fill callers must only apply the result to an
/// empty field; manual entry always wins.
class AltitudeResolver {
  AltitudeResolver({
    required ElevationService elevationService,
    Map<String, double?>? cache,
  }) : _elevation = elevationService,
       _cache = cache;

  final ElevationService _elevation;

  /// Optional per-run lookup cache keyed by coordinates rounded to 4 decimal
  /// places (roughly 11 m) so a batch import at one location does one lookup.
  final Map<String, double?>? _cache;

  Future<AltitudeResolution> resolve({
    GeoPoint? entryLocation,
    GeoPoint? exitLocation,
    DiveSite? site,
  }) async {
    final divePoint = entryLocation ?? exitLocation;
    if (divePoint != null) {
      final meters = await _lookup(divePoint);
      if (meters != null) return AltitudeResolution(altitudeMeters: meters);
    }

    if (site == null) return const AltitudeResolution();
    if (site.altitude != null) {
      return AltitudeResolution(altitudeMeters: site.altitude);
    }

    final siteLocation = site.location;
    if (siteLocation != null) {
      final meters = await _lookup(siteLocation);
      if (meters != null) {
        return AltitudeResolution(
          altitudeMeters: meters,
          siteWriteBack: site.copyWith(altitude: meters),
        );
      }
    }
    return const AltitudeResolution();
  }

  Future<double?> _lookup(GeoPoint point) async {
    final cache = _cache;
    final key =
        '${point.latitude.toStringAsFixed(4)},'
        '${point.longitude.toStringAsFixed(4)}';
    if (cache != null && cache.containsKey(key)) return cache[key];
    final meters = await _elevation.fetchElevation(
      latitude: point.latitude,
      longitude: point.longitude,
    );
    cache?[key] = meters;
    return meters;
  }
}
