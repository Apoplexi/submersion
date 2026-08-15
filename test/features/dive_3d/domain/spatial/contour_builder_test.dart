import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dive_3d/domain/spatial/contour_builder.dart';
import 'package:submersion/features/dive_3d/domain/spatial/seascape_appearance.dart';

void main() {
  group('resolvedContourLevels auto mode', () {
    test('meters diver, 35 m site: 5 m steps, majors every 5th', () {
      // span = 35 display units; niceStep(35 / 15) = niceStep(2.33) = 5.
      // Levels: 5,10,15,20,25,30,35 (7 levels). Major at k % 5 == 0: 25.
      final levels = resolvedContourLevels(
        maxDepthMeters: 35,
        displayUnitInMeters: 1.0,
        depthSymbol: 'm',
        appearance: const SeascapeAppearance(),
      );
      expect(levels.map((l) => l.depthMeters).toList(), [
        5,
        10,
        15,
        20,
        25,
        30,
        35,
      ]);
      expect(levels.map((l) => l.isMajor).toList(), [
        false,
        false,
        false,
        false,
        true,
        false,
        false,
      ]);
      expect(levels.first.label, '5 m');
      expect(levels.every((l) => l.colorArgb == null), isTrue);
    });

    test('feet diver, 35 m site: nice steps in feet, meters underneath', () {
      // 35 m = 114.83 ft; niceStep(114.83 / 15) = niceStep(7.66) = 10 ft.
      // Levels 10..110 ft (11 levels), majors at 50 and 100 ft.
      final levels = resolvedContourLevels(
        maxDepthMeters: 35,
        displayUnitInMeters: 0.3048,
        depthSymbol: 'ft',
        appearance: const SeascapeAppearance(),
      );
      expect(levels, hasLength(11));
      expect(levels.first.depthMeters, closeTo(3.048, 1e-9));
      expect(levels.first.label, '10 ft');
      expect(levels[4].isMajor, isTrue); // 50 ft
      expect(levels[9].isMajor, isTrue); // 100 ft
    });

    test('flat-site guard: fewer than 2 fitting levels means none', () {
      // The step has a floor of 1 display unit (no centimeter contours), so
      // span 1.9 m at unit 1.0: step = max(niceStep(1.9/15), 1) = 1;
      // count = floor(1.9 / 1) = 1 < 2: guard fires, no contours.
      expect(
        resolvedContourLevels(
          maxDepthMeters: 1.9,
          displayUnitInMeters: 1.0,
          depthSymbol: 'm',
          appearance: const SeascapeAppearance(),
        ),
        isEmpty,
      );
      expect(
        resolvedContourLevels(
          maxDepthMeters: 0,
          displayUnitInMeters: 1.0,
          depthSymbol: 'm',
          appearance: const SeascapeAppearance(),
        ),
        isEmpty,
      );
      // span 2.5 m: step 1, levels 1 m and 2 m: just past the guard.
      expect(
        resolvedContourLevels(
          maxDepthMeters: 2.5,
          displayUnitInMeters: 1.0,
          depthSymbol: 'm',
          appearance: const SeascapeAppearance(),
        ).map((l) => l.depthMeters).toList(),
        [1.0, 2.0],
      );
    });
  });

  group('resolvedContourLevels custom mode', () {
    test('custom levels sorted, all labeled major, colors carried', () {
      final levels = resolvedContourLevels(
        maxDepthMeters: 50,
        displayUnitInMeters: 1.0,
        depthSymbol: 'm',
        appearance: const SeascapeAppearance(
          contourMode: SeascapeContourMode.custom,
          customLevels: [
            SeascapeContourLevel(depthMeters: 20.0, colorArgb: 0xFF10B981),
            SeascapeContourLevel(depthMeters: 10.0),
          ],
        ),
      );
      expect(levels.map((l) => l.depthMeters).toList(), [10.0, 20.0]);
      expect(levels.every((l) => l.isMajor), isTrue);
      expect(levels[1].colorArgb, 0xFF10B981);
      expect(levels[0].label, '10 m');
    });

    test('empty custom list falls back to auto', () {
      final levels = resolvedContourLevels(
        maxDepthMeters: 35,
        displayUnitInMeters: 1.0,
        depthSymbol: 'm',
        appearance: const SeascapeAppearance(
          contourMode: SeascapeContourMode.custom,
        ),
      );
      expect(levels, hasLength(7)); // same as the auto 35 m case
    });

    test('custom level deeper than terrain is kept (yields no line later)', () {
      final levels = resolvedContourLevels(
        maxDepthMeters: 15,
        displayUnitInMeters: 1.0,
        depthSymbol: 'm',
        appearance: const SeascapeAppearance(
          contourMode: SeascapeContourMode.custom,
          customLevels: [SeascapeContourLevel(depthMeters: 40.0)],
        ),
      );
      expect(levels.single.depthMeters, 40.0);
    });
  });
}
