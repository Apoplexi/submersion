import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dive_3d/domain/spatial/seascape_appearance.dart';

void main() {
  test('defaults are the spec defaults', () {
    const a = SeascapeAppearance();
    expect(a.rampMaxDepthMeters, isNull);
    expect(a.rampBanded, isFalse);
    expect(a.contourMode, SeascapeContourMode.auto);
    expect(a.customLevels, isEmpty);
    expect(a.wallAngleDeg, 22.0);
  });

  test('encode/decode round-trips every field', () {
    const a = SeascapeAppearance(
      rampMaxDepthMeters: 40.0,
      rampBanded: true,
      contourMode: SeascapeContourMode.custom,
      customLevels: [
        SeascapeContourLevel(depthMeters: 10.0),
        SeascapeContourLevel(depthMeters: 20.0, colorArgb: 0xFFEF4444),
      ],
      wallAngleDeg: 30.0,
    );
    final decoded = SeascapeAppearance.decode(a.encode());
    expect(decoded, a);
    expect(decoded.customLevels[1].colorArgb, 0xFFEF4444);
  });

  test('stored JSON from builds with the thickness field still decodes', () {
    // contourThickness shipped briefly and was removed; the defensive
    // decoder must ignore the legacy key without disturbing its neighbors.
    const raw = '{"rampBanded":true,"contourThickness":2.5,"wallAngleDeg":30}';
    final decoded = SeascapeAppearance.decode(raw);
    expect(decoded.rampBanded, isTrue);
    expect(decoded.wallAngleDeg, 30.0);
  });

  test('decode of null, garbage, or wrong shapes yields defaults', () {
    expect(SeascapeAppearance.decode(null), const SeascapeAppearance());
    expect(SeascapeAppearance.decode('not json'), const SeascapeAppearance());
    expect(SeascapeAppearance.decode('[1,2]'), const SeascapeAppearance());
    expect(
      SeascapeAppearance.decode('{"wallAngleDeg":"x"}'),
      const SeascapeAppearance(),
    );
  });

  test('decode keeps valid custom levels and drops malformed ones', () {
    const raw =
        '{"contourMode":"custom","customLevels":['
        '{"depthMeters":10},'
        '"not an object",'
        '{"depthMeters":-5},'
        '{"depthMeters":"x"},'
        '{"depthMeters":20,"colorArgb":16711680}]}';
    final decoded = SeascapeAppearance.decode(raw);
    expect(decoded.contourMode, SeascapeContourMode.custom);
    expect(decoded.customLevels.map((l) => l.depthMeters).toList(), [
      10.0,
      20.0,
    ]);
    expect(decoded.customLevels.last.colorArgb, 16711680);
  });

  test('copyWith clearRampMax clears the nullable field', () {
    const a = SeascapeAppearance(rampMaxDepthMeters: 40.0);
    expect(a.copyWith(clearRampMax: true).rampMaxDepthMeters, isNull);
    expect(a.copyWith(wallAngleDeg: 35.0).rampMaxDepthMeters, 40.0);
  });

  test('value equality via Equatable', () {
    expect(
      const SeascapeAppearance(rampBanded: true),
      const SeascapeAppearance(rampBanded: true),
    );
    expect(
      const SeascapeAppearance(),
      isNot(const SeascapeAppearance(rampBanded: true)),
    );
  });
}
