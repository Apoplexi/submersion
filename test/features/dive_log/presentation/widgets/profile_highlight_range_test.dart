import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:submersion/features/dive_log/presentation/widgets/profile_highlight_range.dart';

void main() {
  ProfileHighlightRange range(int start, int end) => ProfileHighlightRange(
    startTimestamp: start,
    endTimestamp: end,
    color: Colors.teal,
  );

  group('visibleHighlightSpan', () {
    test('returns the full span when inside the window', () {
      final span = visibleHighlightSpan(
        range(60, 120),
        visibleMinX: 0,
        visibleMaxX: 300,
      );
      expect(span, (x1: 60.0, x2: 120.0));
    });

    test('clamps the left edge to the window', () {
      final span = visibleHighlightSpan(
        range(60, 120),
        visibleMinX: 90,
        visibleMaxX: 300,
      );
      expect(span, (x1: 90.0, x2: 120.0));
    });

    test('clamps the right edge to the window', () {
      final span = visibleHighlightSpan(
        range(60, 120),
        visibleMinX: 0,
        visibleMaxX: 100,
      );
      expect(span, (x1: 60.0, x2: 100.0));
    });

    test('returns null when the range is entirely outside the window', () {
      final span = visibleHighlightSpan(
        range(60, 120),
        visibleMinX: 150,
        visibleMaxX: 300,
      );
      expect(span, isNull);
    });

    test('returns null when the visible overlap has zero width', () {
      // Window touches the range at exactly one point (x = 120).
      final span = visibleHighlightSpan(
        range(60, 120),
        visibleMinX: 120,
        visibleMaxX: 300,
      );
      expect(span, isNull);
    });

    test('keeps an instant range while its timestamp is inside the window', () {
      final span = visibleHighlightSpan(
        range(90, 90),
        visibleMinX: 0,
        visibleMaxX: 300,
      );
      expect(span, (x1: 90.0, x2: 90.0));
    });

    test('drops an instant range outside the window', () {
      final span = visibleHighlightSpan(
        range(90, 90),
        visibleMinX: 100,
        visibleMaxX: 300,
      );
      expect(span, isNull);
    });
  });
}
