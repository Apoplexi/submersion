import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/constants/enums.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/cylinder_configs/domain/entities/cylinder_config.dart';
import 'package:submersion/features/cylinder_configs/domain/entities/cylinder_config_item.dart';
import 'package:submersion/features/cylinder_configs/presentation/providers/cylinder_config_providers.dart';
import 'package:submersion/features/cylinder_configs/presentation/widgets/unit_configurations_card.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

void main() {
  final now = DateTime.utc(2026, 8, 5);

  CylinderConfigItem item(TankRole role) => CylinderConfigItem(
    id: 'i-${role.name}',
    configId: 'c1',
    tankRole: role,
    createdAt: now,
    updatedAt: now,
  );

  Widget host(List<CylinderConfig> configs) => ProviderScope(
    overrides: [
      cylinderConfigsForEquipmentProvider(
        'rb-1',
      ).overrideWith((ref) async => configs),
    ],
    child: const MaterialApp(
      // Pinned: an unpinned locale makes text finders machine-dependent.
      locale: Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: UnitConfigurationsCard(equipmentId: 'rb-1')),
    ),
  );

  testWidgets("lists the unit's configurations with cylinder counts", (
    tester,
  ) async {
    await tester.pumpWidget(
      host([
        CylinderConfig(
          id: 'c1',
          name: 'JJ trimix',
          equipmentId: 'rb-1',
          items: [item(TankRole.diluent), item(TankRole.oxygenSupply)],
          createdAt: now,
          updatedAt: now,
        ),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Configurations'), findsOneWidget);
    expect(find.text('JJ trimix'), findsOneWidget);
    expect(find.text('Diluent, O₂ Supply'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('shows an empty state with an add action when there are none', (
    tester,
  ) async {
    await tester.pumpWidget(host(const []));
    await tester.pumpAndSettle();

    expect(find.text('Configurations'), findsOneWidget);
    expect(find.text('New configuration'), findsOneWidget);
    expect(
      find.textContaining('Save a diluent and bailout setup once'),
      findsOneWidget,
    );
  });
}
