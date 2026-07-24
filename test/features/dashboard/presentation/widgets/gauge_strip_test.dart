import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:submersion/core/constants/enums.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/dashboard/presentation/providers/gauge_providers.dart';
import 'package:submersion/features/dashboard/presentation/widgets/gauge_strip.dart';
import 'package:submersion/features/equipment/domain/entities/service_clock_status.dart';
import 'package:submersion/features/equipment/domain/entities/service_kind.dart';
import 'package:submersion/features/equipment/domain/entities/service_schedule.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

import '../../../../helpers/mock_providers.dart';

Future<void> pumpStrip(
  WidgetTester tester,
  DashboardGauges gauges, {
  MockSettingsNotifier? settingsNotifier,
}) async {
  final overrides = await getBaseOverrides(settingsNotifier: settingsNotifier);
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

  testWidgets('hidden chip types are not rendered', (tester) async {
    final settingsNotifier = MockSettingsNotifier();
    await settingsNotifier.setHomeChipEnabled('noFly', false);
    await settingsNotifier.setHomeChipEnabled('gear', false);
    await pumpStrip(
      tester,
      const DashboardGauges(
        gearGauges: [],
        hasGear: false,
        insurance: null,
        noFlyStatus: null,
        daysSinceLastDive: 12,
      ),
      settingsNotifier: settingsNotifier,
    );
    expect(find.text('No-fly 0:00'), findsNothing);
    expect(find.text('Add gear'), findsNothing);
    expect(find.text('Last dive 12d ago'), findsOneWidget);
  });

  testWidgets('attention chips render when their data is present', (
    tester,
  ) async {
    await pumpStrip(
      tester,
      const DashboardGauges(
        gearGauges: [],
        hasGear: true,
        insurance: null,
        noFlyStatus: null,
        daysSinceLastDive: 200,
        expiringCertCount: 2,
        uploadsPending: 3,
        syncEnabled: true,
        syncPending: 5,
        dataQualityFindings: 4,
      ),
    );
    expect(find.text('2 certifications expiring'), findsOneWidget);
    expect(find.text('3 uploads pending'), findsOneWidget);
    expect(find.text('5 unsynced'), findsOneWidget);
    expect(find.text('4 data issues'), findsOneWidget);
    expect(find.text('No backup yet'), findsOneWidget);
    expect(find.text('Last dive 200d ago'), findsOneWidget);
  });
}
