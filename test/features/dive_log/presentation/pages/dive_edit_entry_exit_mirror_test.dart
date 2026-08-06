import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/dive_log/data/repositories/dive_repository_impl.dart';
import 'package:submersion/features/dive_log/presentation/pages/dive_edit_page.dart';
import 'package:submersion/features/dive_log/presentation/providers/dive_providers.dart';
import 'package:submersion/features/tank_presets/presentation/providers/tank_preset_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

import '../../../../helpers/mock_providers.dart';
import '../../../../helpers/test_database.dart';

/// New-dive pages host a continuous animation, so pumpAndSettle never
/// settles; a bounded pump loop drains async work and animations instead.
Future<void> pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// The Conditions section is collapsed by default and its children are not
/// mounted while collapsed. The whole header row (including the label text)
/// is the toggle tap target.
Future<void> expandConditions(WidgetTester tester) async {
  final header = find.text('Conditions');
  await tester.scrollUntilVisible(
    header,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(header);
  await pumpFrames(tester);
}

/// Opens the EnumPickerRow labeled [rowLabel] and taps the sheet option
/// [optionText]. Sheet options are ListTiles; page rows are not, so
/// widgetWithText(ListTile, ...) cannot hit the row behind the sheet.
Future<void> pickMethod(
  WidgetTester tester,
  String rowLabel,
  String optionText,
) async {
  final row = find.text(rowLabel);
  await tester.scrollUntilVisible(
    row,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(row);
  await pumpFrames(tester);
  await tester.tap(find.widgetWithText(ListTile, optionText));
  await pumpFrames(tester);
}

void main() {
  group('DiveEditPage entry/exit mirroring (new dive)', () {
    late DiveRepository repository;

    setUp(() async {
      await setUpTestDatabase();
      repository = DiveRepository();
    });

    tearDown(() async {
      await tearDownTestDatabase();
    });

    List<dynamic> buildOverrides(List<dynamic> base) {
      return [
        ...base,
        diveRepositoryProvider.overrideWithValue(repository),
        diveListNotifierProvider.overrideWith((ref) {
          return DiveListNotifier(repository, ref);
        }),
        customTankPresetsProvider.overrideWith((ref) async => []),
      ];
    }

    Future<void> pumpNewDivePage(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final overrides = await getBaseOverrides();
      await tester.pumpWidget(
        ProviderScope(
          overrides: buildOverrides(overrides).cast(),
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: DiveEditPage(embedded: true)),
          ),
        ),
      );
      await pumpFrames(tester);
    }

    testWidgets('selecting entry method fills exit method', (tester) async {
      await pumpNewDivePage(tester);
      await expandConditions(tester);

      await pickMethod(tester, 'Entry Method', 'Shore Entry');

      // Entry row value + mirrored exit row value.
      expect(find.text('Shore Entry'), findsNWidgets(2));
    });

    testWidgets('exit follows subsequent entry changes while linked', (
      tester,
    ) async {
      await pumpNewDivePage(tester);
      await expandConditions(tester);

      await pickMethod(tester, 'Entry Method', 'Shore Entry');
      await pickMethod(tester, 'Entry Method', 'Boat Entry');

      expect(find.text('Boat Entry'), findsNWidgets(2));
      expect(find.text('Shore Entry'), findsNothing);
    });

    testWidgets('touching exit breaks the link for the session', (
      tester,
    ) async {
      await pumpNewDivePage(tester);
      await expandConditions(tester);

      await pickMethod(tester, 'Entry Method', 'Shore Entry');
      await pickMethod(tester, 'Exit Method', 'Ladder');
      await pickMethod(tester, 'Entry Method', 'Boat Entry');

      // Entry changed alone; exit kept its explicit value.
      expect(find.text('Boat Entry'), findsOneWidget);
      expect(find.text('Ladder'), findsOneWidget);
    });

    testWidgets('clearing entry while linked clears exit', (tester) async {
      await pumpNewDivePage(tester);
      await expandConditions(tester);

      await pickMethod(tester, 'Entry Method', 'Shore Entry');
      await pickMethod(tester, 'Entry Method', 'Not specified');

      expect(find.text('Shore Entry'), findsNothing);
    });
  });
}
