import 'package:submersion/features/bathymetry/domain/bathymetry_grid.dart';
import 'package:submersion/features/bathymetry/domain/bathymetry_source.dart';
import 'package:submersion/features/dive_sites/domain/entities/dive_site.dart';

/// The outcome of walking the source tiers for one coordinate.
///
/// - `grid != null`: usable terrain (definitive).
/// - `grid == null && definitive`: fetched fine, genuinely no water here —
///   cacheable as a negative answer.
/// - `grid == null && !definitive`: transient failure — must NOT be cached.
class BathymetryResolution {
  final BathymetryGrid? grid;
  final bool definitive;

  const BathymetryResolution.ok(BathymetryGrid this.grid) : definitive = true;
  const BathymetryResolution.empty() : grid = null, definitive = true;
  const BathymetryResolution.transientFailure()
    : grid = null,
      definitive = false;
}

/// Best-source-wins: walks the ordered tiers and returns the first grid
/// with enough wet cells. No mosaicking — sources use different vertical
/// datums (EMODnet is LAT, GMRT/ETOPO MSL) and stitching them seams.
class BathymetryResolver {
  static const double minWetFraction = 0.10;
  static const double defaultSpanMeters = 4000;

  final List<BathymetrySource> sources;

  const BathymetryResolver({required this.sources});

  Future<BathymetryResolution> resolve(GeoPoint center) async {
    var globalSourceSaidDry = false;
    for (final source in sources) {
      if (!source.covers(center)) continue;
      try {
        final grid = await source.fetch(center, spanMeters: defaultSpanMeters);
        if (grid.wetFraction >= minWetFraction) {
          return BathymetryResolution.ok(grid);
        }
        // A dry answer only proves "no water here" if the source actually
        // covers everywhere; a regional edge cell proves nothing.
        if (source.global) globalSourceSaidDry = true;
      } on BathymetryFetchException {
        // Transient: fall through to the next tier.
      }
    }
    return globalSourceSaidDry
        ? const BathymetryResolution.empty()
        : const BathymetryResolution.transientFailure();
  }
}
