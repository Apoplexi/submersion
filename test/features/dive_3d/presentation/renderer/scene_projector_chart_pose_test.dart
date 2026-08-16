import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dive_3d/domain/geometry/scene_bounds.dart';
import 'package:submersion/features/dive_3d/presentation/renderer/scene_projector.dart';
import 'package:submersion/features/dive_3d/presentation/renderer/tissue_chrome_painters.dart';

void main() {
  const bounds = SceneBounds(
    durationSeconds: 1,
    maxDepthMeters: 30,
    sceneMinY: -SceneBounds.ySpan,
    sceneMaxY: 0.6,
    sceneMinZ: -3,
    sceneMaxZ: 3,
  );

  SceneProjector chartProjector() => SceneProjector(
    size: const Size(400, 400),
    bounds: bounds,
    yawDegrees: chartYawDegrees,
    pitchDegrees: chartPitchDegrees,
    mirrorX: true,
  );

  test('chart pose: east projects right, north projects up', () {
    final p = chartProjector();
    final o = p.project(5, 0, 0); // scene center-ish
    final east = p.project(6, 0, 0);
    final north = p.project(5, 0, 1);
    expect(east.dx, greaterThan(o.dx));
    expect((east.dy - o.dy).abs(), lessThan(1e-6));
    expect(north.dy, lessThan(o.dy)); // screen y grows downward
    expect((north.dx - o.dx).abs(), lessThan(1e-6));
  });

  test('chart pose: viewed from above (surface nearer than depth)', () {
    final p = chartProjector();
    expect(p.viewDepth(5, 0, 0), greaterThan(p.viewDepth(5, -4, 0)));
  });

  test('chart pose: compass needle points straight up', () {
    final angle = compassNeedleAngle(chartProjector());
    expect(angle, isNotNull);
    expect(angle!, closeTo(-math.pi / 2, 1e-6));
  });

  test('mirrorX defaults off and leaves the classic pose unchanged', () {
    final a = SceneProjector(size: const Size(400, 400), bounds: bounds);
    final b = SceneProjector(
      size: const Size(400, 400),
      bounds: bounds,
      mirrorX: false,
    );
    expect(a.project(3, -2, 1), b.project(3, -2, 1));
  });
}
