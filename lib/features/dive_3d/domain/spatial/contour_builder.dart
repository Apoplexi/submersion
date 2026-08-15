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
