import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/gps_log/domain/entities/gps_track.dart';
import 'package:submersion/features/gps_log/presentation/widgets/track_shape_painter.dart';

GpsTrackPoint p(double lat, double lon) =>
    GpsTrackPoint(timestamp: 0, latitude: lat, longitude: lon);

void main() {
  group('shouldRepaint', () {
    test('repaints when the points change', () {
      final a = TrackShapePainter(
        points: [p(0, 0), p(1, 1)],
        color: Colors.blue,
      );
      final b = TrackShapePainter(
        points: [p(0, 0), p(2, 2)],
        color: Colors.blue,
      );
      expect(b.shouldRepaint(a), isTrue);
    });

    test('repaints when the colour changes', () {
      final points = [p(0, 0), p(1, 1)];
      final a = TrackShapePainter(points: points, color: Colors.blue);
      final b = TrackShapePainter(points: points, color: Colors.red);
      expect(b.shouldRepaint(a), isTrue);
    });

    test('does not repaint for an identical point list instance', () {
      final points = [p(0, 0), p(1, 1)];
      final a = TrackShapePainter(points: points, color: Colors.blue);
      final b = TrackShapePainter(points: points, color: Colors.blue);
      expect(b.shouldRepaint(a), isFalse);
    });
  });

  group('TrackShapeChip', () {
    testWidgets('renders at the requested size', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TrackShapeChip(
                points: [p(0, 0), p(0.01, 0.01), p(0, 0.02)],
                width: 88,
                height: 64,
              ),
            ),
          ),
        ),
      );
      final size = tester.getSize(find.byType(TrackShapeChip));
      expect(size.width, 88);
      expect(size.height, 64);
    });

    testWidgets('renders an empty track without throwing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: TrackShapeChip(points: [], width: 88, height: 64),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders a single-point track without dividing by zero', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TrackShapeChip(points: [p(5, 5)], width: 88, height: 64),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('renders a due-north track without producing NaN', (
      tester,
    ) async {
      // Zero longitude span: the scale would divide by zero unguarded.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: TrackShapeChip(
                points: [p(0.0, 5.0), p(0.01, 5.0), p(0.02, 5.0)],
                width: 88,
                height: 64,
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
