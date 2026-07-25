import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/theme/display_zoom.dart';

Widget _harness({required double zoom, required Widget child}) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: const MediaQueryData(
        size: Size(1000, 800),
        padding: EdgeInsets.only(top: 40),
        viewPadding: EdgeInsets.only(top: 40),
        viewInsets: EdgeInsets.only(bottom: 200),
        devicePixelRatio: 2.0,
      ),
      child: DisplayZoomScope(zoom: zoom, child: child),
    ),
  );
}

void main() {
  testWidgets('is a no-op at the default zoom', (tester) async {
    await tester.pumpWidget(
      _harness(
        zoom: DisplayZoom.defaultValue,
        child: const SizedBox(key: Key('child')),
      ),
    );

    expect(find.byKey(const Key('child')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(DisplayZoomScope),
        matching: find.byType(Transform),
      ),
      findsNothing,
      reason: 'no transform layer should be added at 100%',
    );
  });

  testWidgets('divides logical size and insets by the zoom factor', (
    tester,
  ) async {
    late MediaQueryData inner;

    await tester.pumpWidget(
      _harness(
        zoom: 0.8,
        child: Builder(
          builder: (context) {
            inner = MediaQuery.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(inner.size.width, moreOrLessEquals(1250));
    expect(inner.size.height, moreOrLessEquals(1000));
    expect(inner.padding.top, moreOrLessEquals(50));
    expect(inner.viewPadding.top, moreOrLessEquals(50));
    expect(inner.viewInsets.bottom, moreOrLessEquals(250));
  });

  testWidgets('multiplies devicePixelRatio by the zoom factor', (tester) async {
    late MediaQueryData inner;

    await tester.pumpWidget(
      _harness(
        zoom: 0.8,
        child: Builder(
          builder: (context) {
            inner = MediaQuery.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(inner.devicePixelRatio, moreOrLessEquals(1.6));
  });

  testWidgets('shrinks the logical viewport when zooming in', (tester) async {
    late MediaQueryData inner;

    await tester.pumpWidget(
      _harness(
        zoom: 1.25,
        child: Builder(
          builder: (context) {
            inner = MediaQuery.of(context);
            return const SizedBox();
          },
        ),
      ),
    );

    expect(inner.size.width, moreOrLessEquals(800));
  });
}
