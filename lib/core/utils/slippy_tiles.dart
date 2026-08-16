import 'dart:math' as math;

/// Normalized Web Mercator world x for [lonDeg]: 0 at -180, 1 at +180.
double mercatorX(double lonDeg) => (lonDeg + 180.0) / 360.0;

/// Normalized Web Mercator world y for [latDeg]: 0 at the projection's
/// north edge (~85.05 N), 1 at its south edge.
double mercatorY(double latDeg) {
  final latRad = latDeg * math.pi / 180.0;
  return (1.0 - math.log(math.tan(latRad) + 1.0 / math.cos(latRad)) / math.pi) /
      2.0;
}

/// The slippy-map tile containing (lat, lon) at [zoom].
({int x, int y}) slippyTileOf(double lat, double lon, int zoom) {
  final n = 1 << zoom;
  return (x: (mercatorX(lon) * n).floor(), y: (mercatorY(lat) * n).floor());
}

/// The zoom where a box of [lonSpanDeg] spans about [targetTiles] tiles,
/// clamped to [minZoom]..[maxZoom]. Keeps terrain-drape mosaics at a
/// handful of fetches regardless of latitude or box size.
int imageryZoomFor({
  required double lonSpanDeg,
  required int maxZoom,
  int targetTiles = 4,
  int minZoom = 10,
}) {
  if (lonSpanDeg <= 0) return minZoom;
  final z = (math.log(targetTiles * 360.0 / lonSpanDeg) / math.ln2).round();
  return z.clamp(minZoom, maxZoom);
}
