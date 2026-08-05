import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/courses/presentation/pages/course_edit_page.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

import '../../../../helpers/mock_providers.dart';
import '../../../../helpers/test_database.dart';

void main() {
  setUp(() async {
    await setUpTestDatabase();
  });

  tearDown(() async {
    await tearDownTestDatabase();
  });

  Widget buildHarness({required List<dynamic> overrides}) {
    return ProviderScope(
      overrides: overrides.cast(),
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: CourseEditPage(embedded: true)),
      ),
    );
  }

  // Enters a date via the picker's text-input mode and confirms with OK.
  // Calendar mode cannot even display out-of-range dates, so typed input is
  // the only way to probe the picker's lastDate bound behaviorally: an
  // out-of-range date leaves the dialog open with an "Out of range." error.
  Future<void> enterDateInPicker(WidgetTester tester, DateTime date) async {
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    await tester.enterText(
      find.byType(TextField).last,
      '$month/$day/${date.year}',
    );
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
  }

  testWidgets('start date can be set more than one year in the future', (
    tester,
  ) async {
    final overrides = await getBaseOverrides();
    await tester.pumpWidget(buildHarness(overrides: overrides));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Start Date'));
    await tester.pumpAndSettle();

    final target = DateTime(DateTime.now().year + 2, 6, 15);
    await enterDateInPicker(tester, target);

    expect(find.byType(DatePickerDialog), findsNothing);
    expect(find.textContaining('${target.year}'), findsOneWidget);
  });
}
