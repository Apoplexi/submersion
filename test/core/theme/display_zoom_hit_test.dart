import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/theme/display_zoom.dart';

void main() {
  for (final zoom in const [0.7, 0.8, 1.0, 1.3, 1.4]) {
    testWidgets('forwards taps through the transform at zoom $zoom', (
      tester,
    ) async {
      var taps = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: DisplayZoomScope(
            zoom: zoom,
            child: Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => taps++,
                  child: const Text('Tap me'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Tap me'));
      await tester.pump();

      expect(taps, 1, reason: 'tap must register at zoom $zoom');
    });
  }

  // A centred target is not enough. The transform is anchored top-left, so a
  // widget at the middle of the screen sits at zoom * centre in the scaled
  // space and stays inside the window rect no matter how the boxes are
  // nested. Only targets past that rect expose a hit-test region that is
  // narrower than the painted area.
  for (final zoom in const [0.7, 0.8, 1.0, 1.3, 1.4]) {
    testWidgets('registers a tap on the bottom navigation bar at zoom $zoom', (
      tester,
    ) async {
      var selected = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: DisplayZoomScope(
            zoom: zoom,
            child: Scaffold(
              body: const SizedBox.expand(),
              bottomNavigationBar: NavigationBar(
                selectedIndex: selected,
                onDestinationSelected: (index) => selected = index,
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.scuba_diving),
                    label: 'Dives',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.place),
                    label: 'Sites',
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Sites'));
      await tester.pump();

      expect(
        selected,
        1,
        reason: 'bottom navigation bar must be tappable at zoom $zoom',
      );
    });
  }

  for (final zoom in const [0.7, 0.8, 1.0, 1.3, 1.4]) {
    testWidgets('hit-tests every corner of the window at zoom $zoom', (
      tester,
    ) async {
      final hits = <Offset>[];

      await tester.pumpWidget(
        MaterialApp(
          home: DisplayZoomScope(
            zoom: zoom,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => hits.add(details.globalPosition),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      final window = tester.view.physicalSize / tester.view.devicePixelRatio;
      final corners = <Offset>[
        const Offset(1, 1),
        Offset(window.width - 1, 1),
        Offset(1, window.height - 1),
        Offset(window.width - 1, window.height - 1),
      ];

      for (final corner in corners) {
        await tester.tapAt(corner);
        await tester.pump();
      }

      expect(
        hits,
        corners,
        reason:
            'the whole painted window must stay hit-testable at zoom $zoom; '
            'missing corners mean the scaled subtree is laid out larger than '
            'the box that guards the hit test',
      );
    });
  }
}
