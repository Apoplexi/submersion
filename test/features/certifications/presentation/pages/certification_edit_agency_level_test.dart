import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/constants/enums.dart';
import 'package:submersion/features/certifications/data/repositories/certification_repository.dart';
import 'package:submersion/features/certifications/domain/entities/certification.dart';
import 'package:submersion/features/certifications/presentation/pages/certification_edit_page.dart';
import 'package:submersion/features/certifications/presentation/providers/certification_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

import '../../../../helpers/mock_providers.dart';
import '../../../../helpers/test_database.dart';

void main() {
  late CertificationRepository repository;

  setUp(() async {
    await setUpTestDatabase();
    repository = CertificationRepository();
  });

  tearDown(() async {
    await tearDownTestDatabase();
  });

  Future<Widget> buildHarness({String? certificationId}) async {
    final overrides = await getBaseOverrides();
    return ProviderScope(
      overrides: [
        ...overrides,
        certificationRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: CertificationEditPage(
            certificationId: certificationId,
            embedded: true,
          ),
        ),
      ),
    );
  }

  Finder agencyDropdown() =>
      find.byType(DropdownButtonFormField<CertificationAgency>);
  Finder levelDropdown() =>
      find.byType(DropdownButtonFormField<CertificationLevel>);

  Future<void> selectFromDropdown(
    WidgetTester tester,
    Finder dropdown,
    String optionLabel,
  ) async {
    await tester.ensureVisible(dropdown);
    await tester.pumpAndSettle();
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    // The overlay duplicates the selected item's label; .last hits the menu.
    // Menu items below the fold must be scrolled into view first.
    final item = find.text(optionLabel).last;
    await tester.ensureVisible(item);
    await tester.pumpAndSettle();
    await tester.tap(item);
    await tester.pumpAndSettle();
  }

  testWidgets('agency dropdown appears above level dropdown', (tester) async {
    await tester.pumpWidget(await buildHarness());
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(agencyDropdown()).dy,
      lessThan(tester.getTopLeft(levelDropdown()).dy),
    );
  });

  testWidgets('selecting CMAS restricts levels to CMAS grades + specialties', (
    tester,
  ) async {
    await tester.pumpWidget(await buildHarness());
    await tester.pumpAndSettle();

    await selectFromDropdown(tester, agencyDropdown(), 'CMAS');

    await tester.ensureVisible(levelDropdown());
    await tester.pumpAndSettle();
    await tester.tap(levelDropdown());
    await tester.pumpAndSettle();

    expect(find.text('2★ Diver'), findsOneWidget);
    expect(find.text('Nitrox'), findsOneWidget);
    expect(find.text('Advanced Open Water'), findsNothing);
  });

  testWidgets('switching agency resets an incompatible level', (tester) async {
    await tester.pumpWidget(await buildHarness());
    await tester.pumpAndSettle();

    // Default agency is PADI; pick a PADI-ladder level.
    await selectFromDropdown(tester, levelDropdown(), 'Advanced Open Water');
    expect(find.text('Advanced Open Water'), findsOneWidget);

    await selectFromDropdown(tester, agencyDropdown(), 'CMAS');

    expect(find.text('Advanced Open Water'), findsNothing);
    expect(find.text('Not specified'), findsOneWidget);
  });

  testWidgets('switching agency keeps a compatible (specialty) level', (
    tester,
  ) async {
    await tester.pumpWidget(await buildHarness());
    await tester.pumpAndSettle();

    await selectFromDropdown(tester, levelDropdown(), 'Nitrox');
    await selectFromDropdown(tester, agencyDropdown(), 'CMAS');

    expect(find.text('Nitrox'), findsOneWidget);
  });

  testWidgets(
    'existing record with out-of-catalog level renders and survives save',
    (tester) async {
      final now = DateTime(2024);
      final cert = await repository.createCertification(
        Certification(
          id: '',
          name: 'Legacy CMAS card',
          agency: CertificationAgency.cmas,
          level: CertificationLevel.advancedOpenWater,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await tester.pumpWidget(await buildHarness(certificationId: cert.id));
      await tester.pumpAndSettle();

      // Stored level renders even though it is not in the CMAS catalog.
      expect(find.text('Advanced Open Water'), findsOneWidget);

      // Save without touching agency or level; the value must survive.
      await tester.tap(find.text('Save'));
      await tester.pump(const Duration(seconds: 1));

      final saved = await tester.runAsync(
        () => repository.getCertificationById(cert.id),
      );
      expect(saved!.level, CertificationLevel.advancedOpenWater);
      expect(saved.agency, CertificationAgency.cmas);
    },
  );
}
