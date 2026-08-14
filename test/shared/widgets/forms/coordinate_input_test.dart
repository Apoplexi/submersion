import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/utils/coordinates/coordinate_format.dart';
import 'package:submersion/shared/widgets/forms/coordinate_input.dart';

void main() {
  Future<void> pumpInput(
    WidgetTester tester, {
    required CoordinateFormat format,
    double? latitude,
    double? longitude,
    required void Function(double?, double?) onChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoordinateInput(
            format: format,
            latitude: latitude,
            longitude: longitude,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  testWidgets('decimal degrees shows two axis fields', (tester) async {
    await pumpInput(
      tester,
      format: CoordinateFormat.decimalDegrees,
      latitude: 20.361944,
      longitude: -87.029722,
      onChanged: (_, _) {},
    );
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('20.361944'), findsOneWidget);
    expect(find.text('-87.029722'), findsOneWidget);
  });

  testWidgets('mgrs collapses to a single grid reference field', (
    tester,
  ) async {
    await pumpInput(
      tester,
      format: CoordinateFormat.mgrs,
      latitude: 20.361944,
      longitude: -87.029722,
      onChanged: (_, _) {},
    );
    expect(find.byType(TextFormField), findsOneWidget);
    expect(find.text('16Q DH 96898 51535'), findsOneWidget);
  });

  testWidgets('utm shows zone, easting and northing', (tester) async {
    await pumpInput(
      tester,
      format: CoordinateFormat.utm,
      latitude: 20.361944,
      longitude: -87.029722,
      onChanged: (_, _) {},
    );
    expect(find.text('16Q'), findsOneWidget);
    expect(find.text('496898'), findsOneWidget);
    expect(find.text('2251535'), findsOneWidget);
  });

  testWidgets('dms shows degree, minute and second sub-fields per axis', (
    tester,
  ) async {
    await pumpInput(
      tester,
      format: CoordinateFormat.degreesMinutesSeconds,
      latitude: 20.361944,
      longitude: -87.029722,
      onChanged: (_, _) {},
    );
    expect(find.byType(TextFormField), findsNWidgets(6));
    expect(find.text('43.0'), findsOneWidget);
  });

  testWidgets('editing a decimal field reports decimal degrees out', (
    tester,
  ) async {
    double? lat;
    await pumpInput(
      tester,
      format: CoordinateFormat.decimalDegrees,
      latitude: 0,
      longitude: 0,
      onChanged: (a, _) => lat = a,
    );
    await tester.enterText(find.byType(TextFormField).first, '20.361944');
    await tester.pump();
    expect(lat, closeTo(20.361944, 1e-9));
  });

  testWidgets('typing a grid reference reports decimal degrees out', (
    tester,
  ) async {
    double? lat;
    double? lng;
    await pumpInput(
      tester,
      format: CoordinateFormat.mgrs,
      onChanged: (a, b) {
        lat = a;
        lng = b;
      },
    );
    await tester.enterText(find.byType(TextFormField), '16Q DH 96898 51535');
    await tester.pump();
    expect(lat, closeTo(20.361944, 2e-5));
    expect(lng, closeTo(-87.029722, 2e-5));
  });

  testWidgets('pasting any format into an axis field fills both axes', (
    tester,
  ) async {
    double? lat;
    double? lng;
    await pumpInput(
      tester,
      format: CoordinateFormat.decimalDegrees,
      onChanged: (a, b) {
        lat = a;
        lng = b;
      },
    );
    // A DMS pair pasted while the app is set to decimal degrees still works:
    // text arrives in whatever notation its author used.
    await tester.enterText(
      find.byType(TextFormField).first,
      '20° 21\' 43.0" N, 87° 01\' 47.0" W',
    );
    await tester.pump();
    expect(lat, closeTo(20.361944, 1e-4));
    expect(lng, closeTo(-87.029722, 1e-4));
  });

  testWidgets('a pasted pair fills the visible fields, not just the callback', (
    tester,
  ) async {
    await pumpInput(
      tester,
      format: CoordinateFormat.decimalDegrees,
      latitude: 1.0,
      longitude: 2.0,
      onChanged: (_, _) {},
    );

    await tester.enterText(
      find.byType(TextFormField).first,
      '20° 21\' 43.0" N, 87° 01\' 47.0" W',
    );
    await tester.pump();

    // The parent holds the coordinate and does not rebuild this widget on
    // every keystroke, so re-seeding from the parent's values would wipe what
    // was just pasted.
    expect(find.text('20.361944'), findsOneWidget);
    expect(find.text('-87.029722'), findsOneWidget);
    expect(find.text('1.000000'), findsNothing);
  });

  testWidgets('a coordinate outside the UTM band falls back to the decimal '
      'layout instead of showing empty grid fields', (tester) async {
    await pumpInput(
      tester,
      format: CoordinateFormat.mgrs,
      latitude: 85.5,
      longitude: 10.0,
      onChanged: (_, _) {},
    );

    // MGRS is undefined above 84 N. Rendering its layout here would show the
    // position as missing, and editing would then report it away.
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('85.500000'), findsOneWidget);
    expect(find.text('10.000000'), findsOneWidget);
  });

  testWidgets('an unparseable entry reports null rather than a stale value', (
    tester,
  ) async {
    double? lat = 1;
    await pumpInput(
      tester,
      format: CoordinateFormat.decimalDegrees,
      onChanged: (a, _) => lat = a,
    );
    await tester.enterText(find.byType(TextFormField).first, 'not a number');
    await tester.pump();
    expect(lat, isNull);
  });

  testWidgets('half a coordinate reports nothing', (tester) async {
    double? lat = 1;
    double? lng = 1;
    await pumpInput(
      tester,
      format: CoordinateFormat.decimalDegrees,
      onChanged: (a, b) {
        lat = a;
        lng = b;
      },
    );
    await tester.enterText(find.byType(TextFormField).first, '20.361944');
    await tester.pump();
    // The longitude is still empty, so this is not yet a position.
    expect(lat, isNull);
    expect(lng, isNull);
  });
}
