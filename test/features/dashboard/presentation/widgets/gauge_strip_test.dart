import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:submersion/core/constants/enums.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/dashboard/presentation/providers/gauge_providers.dart';
import 'package:submersion/features/dashboard/presentation/widgets/gauge_strip.dart';
import 'package:submersion/features/equipment/domain/entities/equipment_item.dart';
import 'package:submersion/features/equipment/domain/entities/service_clock_status.dart';
import 'package:submersion/features/equipment/domain/entities/service_kind.dart';
import 'package:submersion/features/equipment/domain/entities/service_schedule.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

import '../../../../helpers/mock_providers.dart';

Future<void> pumpStrip(WidgetTester tester, DashboardGauges gauges) async {
  final overrides = await getBaseOverrides();
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: GaugeStrip()),
      ),
      GoRoute(path: '/gear', builder: (_, _) => const Scaffold()),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...overrides,
        dashboardGaugesProvider.overrideWith((ref) async => gauges),
      ].cast(),
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

GearGauge _gearGauge(
  String name,
  EquipmentType type,
  ServiceClockSeverity severity, {
  DateTime? dueDate,
}) {
  final t0 = DateTime(2026, 1, 1);
  return GearGauge(
    type: type,
    itemName: name,
    status: ServiceClockStatus(
      schedule: ServiceSchedule(
        id: 'schedule',
        equipmentId: 'equipment',
        serviceKindId: 'kind',
        createdAt: t0,
        updatedAt: t0,
      ),
      kind: ServiceKind(
        id: 'kind',
        name: 'Annual service',
        createdAt: t0,
        updatedAt: t0,
      ),
      anchor: t0,
      dueDate: dueDate,
      severity: severity,
      now: DateTime.now(),
    ),
  );
}

void main() {
  testWidgets('renders neutral gauges when everything is fine', (tester) async {
    await pumpStrip(
      tester,
      const DashboardGauges(
        gearGauges: [],
        hasGear: false,
        insurance: null,
        noFlyStatus: null,
        daysSinceLastDive: 12,
      ),
    );
    expect(find.text('Last dive 12d ago'), findsOneWidget);
    expect(find.text('Add gear'), findsOneWidget);
    expect(find.text('No-fly 0:00'), findsOneWidget);
    expect(find.text('No insurance on file'), findsOneWidget);
  });

  testWidgets('gear gauge shows overdue chip', (tester) async {
    await pumpStrip(
      tester,
      DashboardGauges(
        gearGauges: [
          _gearGauge(
            'Regulator',
            EquipmentType.regulator,
            ServiceClockSeverity.overdue,
            dueDate: DateTime(2026, 6, 1),
          ),
        ],
        hasGear: true,
        insurance: null,
        noFlyStatus: null,
        daysSinceLastDive: null,
      ),
    );
    expect(find.text('Regulator overdue'), findsOneWidget);
    expect(find.text('No dives yet'), findsOneWidget);
    expect(find.text('Add gear'), findsNothing);
  });
}
