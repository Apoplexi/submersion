import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:submersion/core/constants/units.dart';
import 'package:submersion/features/dive_3d/domain/spatial/seascape_appearance.dart';
import 'package:submersion/features/dive_3d/presentation/widgets/terrain_appearance_sheet.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

import '../../../../helpers/mock_providers.dart';

void main() {
  Future<ProviderContainer> pumpSheet(
    WidgetTester tester, {
    AppSettings initial = const AppSettings(),
  }) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        settingsProvider.overrideWith((ref) => MockSettingsNotifier(initial)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(child: TerrainAppearanceSheet()),
          ),
        ),
      ),
    );
    await tester.pump();
    return container;
  }

  testWidgets('banded switch writes through to settings', (tester) async {
    final container = await pumpSheet(tester);
    expect(
      container.read(settingsProvider).seascapeAppearance.rampBanded,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('seascapeBandedSwitch')));
    await tester.pump();
    expect(
      container.read(settingsProvider).seascapeAppearance.rampBanded,
      isTrue,
    );
  });

  testWidgets('ramp range toggle seeds a default max and clears it', (
    tester,
  ) async {
    final container = await pumpSheet(tester);
    await tester.tap(find.byKey(const ValueKey('seascapeRampRangeSwitch')));
    await tester.pump();
    expect(
      container.read(settingsProvider).seascapeAppearance.rampMaxDepthMeters,
      40.0,
    );
    await tester.tap(find.byKey(const ValueKey('seascapeRampRangeSwitch')));
    await tester.pump();
    expect(
      container.read(settingsProvider).seascapeAppearance.rampMaxDepthMeters,
      isNull,
    );
  });

  testWidgets('custom mode adds a level via the add button', (tester) async {
    final container = await pumpSheet(tester);
    await tester.tap(find.text('Custom'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('seascapeAddLevelButton')));
    await tester.pump();
    final appearance = container.read(settingsProvider).seascapeAppearance;
    expect(appearance.contourMode, SeascapeContourMode.custom);
    expect(appearance.customLevels, hasLength(1));
    expect(appearance.customLevels.single.depthMeters, 10.0);
  });

  testWidgets('a feet diver gets a round seed in their own unit', (
    tester,
  ) async {
    // The editor shows display units, so seeding a fixed 10 m would read as
    // 32.8 ft. The seed is 10 DISPLAY units, stored as meters underneath.
    final container = await pumpSheet(
      tester,
      initial: const AppSettings(depthUnit: DepthUnit.feet),
    );
    await tester.tap(find.text('Custom'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('seascapeAddLevelButton')));
    await tester.pump();
    final level = container
        .read(settingsProvider)
        .seascapeAppearance
        .customLevels
        .single;
    expect(level.depthMeters, closeTo(3.048, 1e-9)); // 10 ft
    // The row's field reads the round display value, not 32.8.
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('seascapeLevelField0')),
          )
          .initialValue,
      '10',
    );
  });

  testWidgets('wall angle slider persists its value', (tester) async {
    final container = await pumpSheet(tester);
    final slider = find.byKey(const ValueKey('seascapeWallAngleSlider'));
    await tester.drag(slider, const Offset(200, 0));
    await tester.pump();
    expect(
      container.read(settingsProvider).seascapeAppearance.wallAngleDeg,
      greaterThan(22.0),
    );
  });
}
