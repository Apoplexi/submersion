import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/constants/units.dart';
import 'package:submersion/shared/widgets/app_date_picker.dart';

void main() {
  Future<DateTime? Function()> pumpPickerButton(
    WidgetTester tester,
    DateFormatPreference format,
  ) async {
    DateTime? picked;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                picked = await showAppDatePicker(
                  context: context,
                  dateFormat: format,
                  initialDate: DateTime(2026, 1, 15),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
              },
              child: const Text('pick'),
            ),
          ),
        ),
      ),
    );
    return () => picked;
  }

  testWidgets('manual entry accepts the configured day-first format (#765)', (
    tester,
  ) async {
    final picked = await pumpPickerButton(
      tester,
      DateFormatPreference.ddmmyyyy,
    );

    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();

    // Switch the picker to manual input mode.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    // 31 January in day-first notation: invalid under en-US parsing
    // (month 31), valid under the configured DD/MM/YYYY.
    await tester.enterText(find.byType(TextField), '31/01/2026');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect(picked(), DateTime(2026, 1, 31));
  });

  testWidgets('manual entry hint shows the configured format', (tester) async {
    await pumpPickerButton(tester, DateFormatPreference.ddmmyyyyDots);

    await tester.tap(find.text('pick'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.text('dd.mm.yyyy'), findsOneWidget);
  });
}
