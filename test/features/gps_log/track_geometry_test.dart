import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/gps_log/domain/entities/gps_track.dart';
import 'package:submersion/features/gps_log/domain/track_geometry.dart';

GpsTrackPoint p(double lat, double lon, {int t = 0}) =>
    GpsTrackPoint(timestamp: t, latitude: lat, longitude: lon);

void main() {
  group('projectLocal', () {
    test('projects a degree offset at the equator to known metres', () {
      // 0.001 deg longitude at the equator = 0.001 * 111320.0 = 111.32 m
      // 0.001 deg latitude anywhere       = 0.001 * 111194.93 = 111.19 m
      final origin = p(0.0, 0.0);
      final offset = projectLocal(origin, p(0.001, 0.001));
      expect(offset.east, closeTo(111.32, 0.01));
      expect(offset.north, closeTo(111.19, 0.01));
    });

    test('is zero for the origin itself', () {
      final origin = p(20.5, -87.3);
      final offset = projectLocal(origin, origin);
      expect(offset.east, 0.0);
      expect(offset.north, 0.0);
    });
  });

  group('simplifyTrack', () {
    test('drops a collinear midpoint', () {
      // All three on the equator: the midpoint lies exactly on the chord,
      // so its perpendicular distance is 0 and any tolerance removes it.
      final points = [p(0.0, 0.0), p(0.0, 0.001), p(0.0, 0.002)];
      final result = simplifyTrack(points, 1.0);
      expect(result.length, 2);
      expect(result.first.longitude, 0.0);
      expect(result.last.longitude, 0.002);
    });

    test('keeps a midpoint deviating more than the tolerance', () {
      // Chord runs along the equator from lon 0 to lon 0.002. The midpoint
      // sits 0.001 deg north of it = 111.19 m perpendicular deviation.
      final points = [p(0.0, 0.0), p(0.001, 0.001), p(0.0, 0.002)];
      final result = simplifyTrack(points, 50.0);
      expect(result.length, 3);
    });

    test('drops a midpoint deviating less than the tolerance', () {
      // Same 111.19 m deviation, but now under a 200 m tolerance.
      final points = [p(0.0, 0.0), p(0.001, 0.001), p(0.0, 0.002)];
      final result = simplifyTrack(points, 200.0);
      expect(result.length, 2);
    });

    test('always preserves first and last points', () {
      final points = List.generate(100, (i) => p(0.0, i * 0.00001, t: i));
      final result = simplifyTrack(points, 1000.0);
      expect(result.length, 2);
      expect(result.first.timestamp, 0);
      expect(result.last.timestamp, 99);
    });

    test('returns the input unchanged for fewer than three points', () {
      expect(simplifyTrack(const [], 10.0), isEmpty);
      expect(simplifyTrack([p(1, 1)], 10.0).length, 1);
      expect(simplifyTrack([p(1, 1), p(2, 2)], 10.0).length, 2);
    });

    test('preserves the original timestamps of surviving points', () {
      final points = [
        p(0.0, 0.0, t: 100),
        p(0.001, 0.001, t: 200),
        p(0.0, 0.002, t: 300),
      ];
      final result = simplifyTrack(points, 50.0);
      expect(result.map((e) => e.timestamp).toList(), [100, 200, 300]);
    });
  });
}
