import 'dart:math' as math;

import 'package:submersion/features/dive_3d/domain/spatial/seascape_appearance.dart';
import 'package:submersion/features/dive_3d/domain/spatial/seascape_axes.dart';

/// One contour level ready to march: meters for geometry, a display-unit
/// label for chrome, and an optional user color (custom mode).
class ResolvedContourLevel {
  final double depthMeters;
  final bool isMajor;
  final String label;
  final int? colorArgb;

  const ResolvedContourLevel({
    required this.depthMeters,
    required this.isMajor,
    required this.label,
    this.colorArgb,
  });
}

String _formatLevel(double displayValue, String depthSymbol) {
  final text = displayValue % 1 == 0
      ? displayValue.toStringAsFixed(0)
      : displayValue.toStringAsFixed(1);
  return '$text $depthSymbol';
}

/// Resolves the contour levels for a terrain of [maxDepthMeters]. Auto mode
/// picks the smallest nice step (1/2/5 x 10^n, in the DIVER'S display unit)
/// that yields at most 15 levels, floored at 1 display unit so flat sites
/// never get centimeter contours; majors every 5th; fewer than 2 fitting
/// levels means none (flat-site guard). Custom mode uses the user's list
/// (sorted, every level labeled and treated as major); an empty list falls
/// back to auto.
List<ResolvedContourLevel> resolvedContourLevels({
  required double maxDepthMeters,
  required double displayUnitInMeters,
  required String depthSymbol,
  required SeascapeAppearance appearance,
}) {
  if (appearance.contourMode == SeascapeContourMode.custom &&
      appearance.customLevels.isNotEmpty) {
    final sorted = [...appearance.customLevels]
      ..sort((a, b) => a.depthMeters.compareTo(b.depthMeters));
    return [
      for (final l in sorted)
        ResolvedContourLevel(
          depthMeters: l.depthMeters,
          isMajor: true,
          label: _formatLevel(l.depthMeters / displayUnitInMeters, depthSymbol),
          colorArgb: l.colorArgb,
        ),
    ];
  }

  if (maxDepthMeters <= 0 || displayUnitInMeters <= 0) return const [];
  final spanDisplay = maxDepthMeters / displayUnitInMeters;
  final step = math.max(niceStep(spanDisplay / 15), 1.0);
  if (step <= 0) return const [];
  final count = (spanDisplay / step + 1e-9).floor();
  if (count < 2) return const [];
  return [
    for (var k = 1; k <= count; k++)
      ResolvedContourLevel(
        depthMeters: k * step * displayUnitInMeters,
        isMajor: k % 5 == 0,
        label: _formatLevel(k * step, depthSymbol),
      ),
  ];
}

/// A joined isobath polyline in local east/north METERS (flat pairs).
class ContourPolyline {
  final List<double> pointsEastNorth;
  const ContourPolyline(this.pointsEastNorth);
}

/// Marching squares over a callback grid. A cell is skipped when ANY of its
/// four corners is null (nodata) or <= 0 (land): contours stop at the edge
/// of known wet data instead of interpolating fiction. Inside = depth >=
/// level. Ambiguous saddle cases (5, 10) are resolved by the cell-center
/// average. Segments are then chained into polylines by shared endpoints.
List<ContourPolyline> marchGrid({
  required int rows,
  required int cols,
  required double? Function(int r, int c) depthAt,
  required double Function(int c) eastOf,
  required double Function(int r) northOf,
  required double levelMeters,
}) {
  final segments = <List<double>>[]; // [e1, n1, e2, n2]

  for (var r = 0; r < rows - 1; r++) {
    for (var c = 0; c < cols - 1; c++) {
      final sw = depthAt(r, c);
      final se = depthAt(r, c + 1);
      final nw = depthAt(r + 1, c);
      final ne = depthAt(r + 1, c + 1);
      if (sw == null || se == null || nw == null || ne == null) continue;
      if (sw <= 0 || se <= 0 || nw <= 0 || ne <= 0) continue;

      final e0 = eastOf(c), e1 = eastOf(c + 1);
      final n0 = northOf(r), n1 = northOf(r + 1);
      final l = levelMeters;

      var idx = 0;
      if (sw >= l) idx |= 1;
      if (se >= l) idx |= 2;
      if (ne >= l) idx |= 4;
      if (nw >= l) idx |= 8;
      if (idx == 0 || idx == 15) continue;

      double frac(double a, double b) => (l - a) / (b - a);
      // Crossing points on the four cell edges.
      List<double> south() => [e0 + (e1 - e0) * frac(sw, se), n0];
      List<double> east() => [e1, n0 + (n1 - n0) * frac(se, ne)];
      List<double> north() => [e0 + (e1 - e0) * frac(nw, ne), n1];
      List<double> west() => [e0, n0 + (n1 - n0) * frac(sw, nw)];

      void seg(List<double> a, List<double> b) =>
          segments.add([a[0], a[1], b[0], b[1]]);

      switch (idx) {
        case 1 || 14:
          seg(west(), south());
        case 2 || 13:
          seg(south(), east());
        case 3 || 12:
          seg(west(), east());
        case 4 || 11:
          seg(east(), north());
        case 6 || 9:
          seg(south(), north());
        case 7 || 8:
          seg(west(), north());
        case 5:
          final centerInside = (sw + se + ne + nw) / 4 >= l;
          if (centerInside) {
            seg(west(), north());
            seg(south(), east());
          } else {
            seg(west(), south());
            seg(east(), north());
          }
        case 10:
          final centerInside = (sw + se + ne + nw) / 4 >= l;
          if (centerInside) {
            seg(south(), west());
            seg(north(), east());
          } else {
            seg(south(), east());
            seg(north(), west());
          }
      }
    }
  }
  return _joinSegments(segments);
}

/// Chains raw segments into polylines by matching endpoints (quantized to
/// a fine key so float noise never breaks a chain).
List<ContourPolyline> _joinSegments(List<List<double>> segments) {
  String key(double e, double n) => '${(e * 1e6).round()}:${(n * 1e6).round()}';

  final unused = List<bool>.filled(segments.length, true);
  final byEndpoint = <String, List<int>>{};
  for (var i = 0; i < segments.length; i++) {
    final s = segments[i];
    byEndpoint.putIfAbsent(key(s[0], s[1]), () => []).add(i);
    byEndpoint.putIfAbsent(key(s[2], s[3]), () => []).add(i);
  }

  int? takeAt(double e, double n) {
    final list = byEndpoint[key(e, n)];
    if (list == null) return null;
    for (final i in list) {
      if (unused[i]) return i;
    }
    return null;
  }

  final polylines = <ContourPolyline>[];
  for (var start = 0; start < segments.length; start++) {
    if (!unused[start]) continue;
    unused[start] = false;
    final s = segments[start];
    final pts = <double>[s[0], s[1], s[2], s[3]];
    // Extend forward from the tail.
    var extended = true;
    while (extended) {
      extended = false;
      final i = takeAt(pts[pts.length - 2], pts[pts.length - 1]);
      if (i != null) {
        unused[i] = false;
        final t = segments[i];
        final matchesHead =
            key(t[0], t[1]) == key(pts[pts.length - 2], pts[pts.length - 1]);
        pts.addAll(matchesHead ? [t[2], t[3]] : [t[0], t[1]]);
        extended = true;
      }
    }
    // Extend backward from the head.
    extended = true;
    while (extended) {
      extended = false;
      final i = takeAt(pts[0], pts[1]);
      if (i != null) {
        unused[i] = false;
        final t = segments[i];
        final matchesHead = key(t[0], t[1]) == key(pts[0], pts[1]);
        pts.insertAll(0, matchesHead ? [t[2], t[3]] : [t[0], t[1]]);
        extended = true;
      }
    }
    polylines.add(ContourPolyline(pts));
  }
  return polylines;
}
