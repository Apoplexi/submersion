import 'package:flutter/material.dart';

import 'package:submersion/features/gps_log/domain/entities/gps_track.dart';
import 'package:submersion/features/gps_log/domain/track_geometry.dart';

/// Draws a track's shape with no basemap, scaled to fill the canvas.
///
/// The offline fallback for row thumbnails. A GPS track is recorded on a boat,
/// where there is usually no signal to fetch tiles with, so this path runs
/// often enough to deserve being good rather than being a stub.
class TrackShapePainter extends CustomPainter {
  TrackShapePainter({required this.points, required this.color});

  final List<GpsTrackPoint> points;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;

    final bounds = trackBounds(points);
    if (bounds == null) return;

    final latSpan = bounds.maxLat - bounds.minLat;
    final lonSpan = bounds.maxLon - bounds.minLon;

    // A perfectly straight north-south or east-west track has a zero span on
    // one axis; substituting 1 collapses that axis to the canvas centre
    // instead of producing NaN.
    final safeLatSpan = latSpan == 0 ? 1.0 : latSpan;
    final safeLonSpan = lonSpan == 0 ? 1.0 : lonSpan;

    // Preserve aspect ratio: use the tighter scale on both axes, then centre.
    const padding = 6.0;
    final usableWidth = size.width - padding * 2;
    final usableHeight = size.height - padding * 2;
    final scale = (usableWidth / safeLonSpan) < (usableHeight / safeLatSpan)
        ? usableWidth / safeLonSpan
        : usableHeight / safeLatSpan;

    final drawnWidth = safeLonSpan * scale;
    final drawnHeight = safeLatSpan * scale;
    final offsetX = (size.width - drawnWidth) / 2;
    final offsetY = (size.height - drawnHeight) / 2;

    final path = Path();
    for (var i = 0; i < points.length; i++) {
      final x = offsetX + (points[i].longitude - bounds.minLon) * scale;
      // Screen y grows downward, latitude grows northward: invert.
      final y = offsetY + (bounds.maxLat - points[i].latitude) * scale;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..isAntiAlias = true,
    );
  }

  /// Compares point lists by identity, not element-wise.
  ///
  /// Every geometry list in this feature comes from a List.unmodifiable in
  /// simplifyTrack or the cache repository, so a changed track always yields
  /// a new instance. Deep-comparing thousands of points every frame would
  /// cost more than the repaint it avoids.
  @override
  bool shouldRepaint(TrackShapePainter oldDelegate) =>
      oldDelegate.color != color || !identical(oldDelegate.points, points);
}

/// A fixed-size tinted chip containing a [TrackShapePainter].
class TrackShapeChip extends StatelessWidget {
  const TrackShapeChip({
    super.key,
    required this.points,
    required this.width,
    required this.height,
  });

  final List<GpsTrackPoint> points;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: CustomPaint(
          painter: TrackShapePainter(points: points, color: scheme.primary),
        ),
      ),
    );
  }
}
