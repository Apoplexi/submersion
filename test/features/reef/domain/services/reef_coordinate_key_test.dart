import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dive_sites/domain/entities/dive_site.dart';
import 'package:submersion/features/reef/domain/services/reef_coordinate_key.dart';

void main() {
  group('ReefCoordinateKey.quantize', () {
    test('rounds to three decimal places', () {
      final result = ReefCoordinateKey.quantize(
        const GeoPoint(12.160432, -68.280987),
      );
      expect(result.latitude, 12.16);
      expect(result.longitude, -68.281);
    });

    test('rounds negative coordinates away from zero symmetrically', () {
      expect(
        ReefCoordinateKey.quantize(const GeoPoint(-0.5585, 130.6754)).latitude,
        -0.559,
      );
      expect(
        ReefCoordinateKey.quantize(const GeoPoint(0.5585, 130.6754)).latitude,
        0.559,
      );
    });

    test('two points within 110m share a key', () {
      final a = ReefCoordinateKey.format(const GeoPoint(12.1601, -68.2801));
      final b = ReefCoordinateKey.format(const GeoPoint(12.1604, -68.2804));
      expect(a, b);
    });

    test('format pads to exactly three decimals', () {
      expect(
        ReefCoordinateKey.format(const GeoPoint(12.1, -68.0)),
        '12.100,-68.000',
      );
    });

    test('format handles the antimeridian without losing precision', () {
      expect(
        ReefCoordinateKey.format(const GeoPoint(-16.5, 179.9996)),
        '-16.500,180.000',
      );
    });
  });
}
