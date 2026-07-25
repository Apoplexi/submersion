import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/theme/display_zoom.dart';

void main() {
  group('DisplayZoom constants', () {
    test('range and step describe 14 slider divisions', () {
      expect(DisplayZoom.min, 0.70);
      expect(DisplayZoom.max, 1.40);
      expect(DisplayZoom.step, 0.05);
      expect(DisplayZoom.defaultValue, 1.0);
      expect(
        ((DisplayZoom.max - DisplayZoom.min) / DisplayZoom.step).round(),
        DisplayZoom.divisions,
      );
    });
  });

  group('DisplayZoom.clampValue', () {
    test('returns in-range values unchanged', () {
      expect(DisplayZoom.clampValue(0.85), 0.85);
      expect(DisplayZoom.clampValue(DisplayZoom.min), DisplayZoom.min);
      expect(DisplayZoom.clampValue(DisplayZoom.max), DisplayZoom.max);
    });

    test('clamps values below the minimum', () {
      expect(DisplayZoom.clampValue(0.0), DisplayZoom.min);
      expect(DisplayZoom.clampValue(-1.0), DisplayZoom.min);
    });

    test('clamps values above the maximum', () {
      expect(DisplayZoom.clampValue(9.9), DisplayZoom.max);
    });

    test('falls back to the default for non-finite values', () {
      expect(DisplayZoom.clampValue(double.nan), DisplayZoom.defaultValue);
      expect(DisplayZoom.clampValue(double.infinity), DisplayZoom.defaultValue);
      expect(
        DisplayZoom.clampValue(double.negativeInfinity),
        DisplayZoom.defaultValue,
      );
    });
  });
}
