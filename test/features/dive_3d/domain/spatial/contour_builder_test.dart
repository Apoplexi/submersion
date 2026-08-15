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

  group('marchGrid', () {
    double eastOf(int c) => c * 100.0;
    double northOf(int r) => r * 100.0;

    test('single cell, vertical isobath at the midpoint', () {
      // Corners: sw=5 se=15 nw=5 ne=15, level 10. Inside (>=10) = se+ne,
      // marching-squares case S-N: crossings at S edge t=(10-5)/(15-5)=0.5
      // -> (50, 0), and N edge t=0.5 -> (50, 100).
      final grid = [
        [5.0, 15.0], // r=0 (south)
        [5.0, 15.0], // r=1 (north)
      ];
      final lines = marchGrid(
        rows: 2,
        cols: 2,
        depthAt: (r, c) => grid[r][c],
        eastOf: eastOf,
        northOf: northOf,
        levelMeters: 10,
      );
      expect(lines, hasLength(1));
      final pts = lines.single.pointsEastNorth;
      expect(pts, hasLength(4));
      // Accept either direction along the line.
      final ends = {(pts[0], pts[1]), (pts[2], pts[3])};
      expect(ends, {(50.0, 0.0), (50.0, 100.0)});
    });

    test('segments across neighboring cells join into one polyline', () {
      // 2 rows x 3 cols: south row all 5, north row all 15, level 10.
      // Each cell crosses W (t=0.5) and E (t=0.5): a horizontal line at
      // north=50 spanning east 0..200, joined into a single 3-point line.
      final grid = [
        [5.0, 5.0, 5.0],
        [15.0, 15.0, 15.0],
      ];
      final lines = marchGrid(
        rows: 2,
        cols: 3,
        depthAt: (r, c) => grid[r][c],
        eastOf: eastOf,
        northOf: northOf,
        levelMeters: 10,
      );
      expect(lines, hasLength(1));
      final pts = lines.single.pointsEastNorth;
      expect(pts, hasLength(6));
      expect(pts[1], 50.0);
      expect(pts[3], 50.0);
      expect(pts[5], 50.0);
      final easts = {pts[0], pts[2], pts[4]};
      expect(easts, {0.0, 100.0, 200.0});
    });

    test('cells touching a null or land corner are skipped', () {
      // Same as the joining test, but the NE corner is null: the right cell
      // must be skipped, leaving only the left cell's segment.
      final grid = <List<double?>>[
        [5.0, 5.0, 5.0],
        [15.0, 15.0, null],
      ];
      final lines = marchGrid(
        rows: 2,
        cols: 3,
        depthAt: (r, c) => grid[r][c],
        eastOf: eastOf,
        northOf: northOf,
        levelMeters: 10,
      );
      expect(lines, hasLength(1));
      expect(lines.single.pointsEastNorth, hasLength(4));
      // Land corners (depth <= 0) are skipped the same way.
      final landGrid = [
        [5.0, -2.0],
        [15.0, 15.0],
      ];
      expect(
        marchGrid(
          rows: 2,
          cols: 2,
          depthAt: (r, c) => landGrid[r][c],
          eastOf: eastOf,
          northOf: northOf,
          levelMeters: 10,
        ),
        isEmpty,
      );
    });

    test('level outside the cell range yields nothing', () {
      final grid = [
        [5.0, 6.0],
        [7.0, 8.0],
      ];
      expect(
        marchGrid(
          rows: 2,
          cols: 2,
          depthAt: (r, c) => grid[r][c],
          eastOf: eastOf,
          northOf: northOf,
          levelMeters: 40,
        ),
        isEmpty,
      );
    });
  });
}
