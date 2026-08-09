import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:submersion/core/constants/map_style.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/deco_calculator/presentation/providers/deco_calculator_providers.dart';
import 'package:submersion/features/planner/domain/entities/dive_plan.dart';
import 'package:submersion/features/planner/presentation/providers/plan_repository_providers.dart';
import 'package:submersion/features/planning/presentation/pages/planning_page.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';

import '../../helpers/test_app.dart';

class _TestSettingsNotifier extends StateNotifier<AppSettings>
    implements SettingsNotifier {
  _TestSettingsNotifier() : super(const AppSettings());

  @override
  Future<void> setMapStyle(MapStyle style) async =>
      state = state.copyWith(mapStyle: style);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('hub leads with New plan and recent saved plans', (tester) async {
    final summaries = [
      DivePlanSummary(
        id: 'p1',
        name: 'Reef 30m',
        updatedAt: DateTime(2026, 7, 4),
        maxDepth: 30.0,
        runtimeSeconds: 45 * 60,
        ttsSeconds: 300,
        mode: PlanMode.oc,
      ),
      DivePlanSummary(
        id: 'p2',
        name: 'Wreck 50m',
        updatedAt: DateTime(2026, 7, 3),
        maxDepth: 50.0,
        runtimeSeconds: 80 * 60,
        ttsSeconds: 2400,
        mode: PlanMode.ccr,
      ),
    ];

    await tester.pumpWidget(
      testApp(
        overrides: [
          settingsProvider.overrideWith((ref) => _TestSettingsNotifier()),
          divePlanSummariesProvider.overrideWith((ref) async => summaries),
        ],
        locale: const Locale('en'),
        child: const PlanningPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dive Planner'), findsOneWidget);
    expect(find.text('Create multi-level dive plans'), findsOneWidget);
    expect(find.text('Reef 30m'), findsOneWidget);
    expect(find.text('Wreck 50m'), findsOneWidget);
    expect(find.text('TOOLS'), findsOneWidget);
    // The calculators remain as tools.
    expect(find.text('Deco Calculator'), findsOneWidget);
  });

  group('hub navigation pushes sub-pages', () {
    // The hub's tools and saved plans are sub-pages: they must push, not go,
    // so the Android system back button pops back to the hub (#647).
    Future<GoRouter> pumpHub(WidgetTester tester) async {
      final router = GoRouter(
        initialLocation: '/planning',
        routes: [
          GoRoute(
            path: '/planning',
            builder: (_, _) => const PlanningPage(),
            routes: [
              GoRoute(
                path: 'deco-calculator',
                builder: (_, _) => const Text('deco calculator page'),
              ),
              GoRoute(
                path: 'dive-planner/:planId',
                builder: (context, state) =>
                    Text('plan:${state.pathParameters['planId']}'),
              ),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);

      await tester.pumpWidget(
        testAppRouter(
          router: router,
          locale: const Locale('en'),
          overrides: [
            settingsProvider.overrideWith((ref) => _TestSettingsNotifier()),
            divePlanSummariesProvider.overrideWith(
              (ref) async => [
                DivePlanSummary(
                  id: 'p1',
                  name: 'Reef 30m',
                  updatedAt: DateTime(2026, 7, 4),
                  maxDepth: 30.0,
                  runtimeSeconds: 45 * 60,
                  ttsSeconds: 300,
                  mode: PlanMode.oc,
                ),
              ],
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      return router;
    }

    testWidgets('tapping a tool pushes it over the hub', (tester) async {
      final router = await pumpHub(tester);

      await tester.tap(find.text('Deco Calculator'));
      await tester.pumpAndSettle();

      expect(find.text('deco calculator page'), findsOneWidget);
      expect(router.routerDelegate.canPop(), isTrue);
    });

    testWidgets('tapping a saved plan pushes it over the hub', (tester) async {
      final router = await pumpHub(tester);

      await tester.tap(find.text('Reef 30m'));
      await tester.pumpAndSettle();

      expect(find.text('plan:p1'), findsOneWidget);
      expect(router.routerDelegate.canPop(), isTrue);
    });
  });

  test('deco calculator environment defaults to legacy standard water', () {
    final container = ProviderContainer(
      overrides: [
        settingsProvider.overrideWith((ref) => _TestSettingsNotifier()),
      ],
    );
    addTearDown(container.dispose);

    final ndlAtSea = container.read(calcDecoStatusProvider).ndlSeconds;

    // Altitude shortens the NDL at the same depth/time/gas.
    container.read(calcAltitudeProvider.notifier).state = 2500.0;
    final ndlAtAltitude = container.read(calcDecoStatusProvider).ndlSeconds;
    expect(ndlAtAltitude, lessThan(ndlAtSea));
  });
}
