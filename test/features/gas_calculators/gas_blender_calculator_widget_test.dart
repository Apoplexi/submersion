import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:submersion/core/constants/tank_presets.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart'
    show GasMix;
import 'package:submersion/features/gas_calculators/domain/tank_spec.dart';
import 'package:submersion/features/gas_calculators/presentation/providers/gas_calculators_providers.dart';
import 'package:submersion/features/gas_calculators/presentation/widgets/gas_blender_calculator.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

class _TestSettingsNotifier extends StateNotifier<AppSettings>
    implements SettingsNotifier {
  _TestSettingsNotifier(super.settings);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<WidgetRef> _pump(WidgetTester tester) async {
  late WidgetRef captured;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(
          (ref) => _TestSettingsNotifier(const AppSettings()),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) {
              captured = ref;
              return const GasBlenderCalculator();
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return captured;
}

void main() {
  testWidgets('default nitrox target shows the EAN32 fill procedure', (
    tester,
  ) async {
    await _pump(tester);

    // Procedure heading and the target nitrox both render.
    expect(find.text('Fill procedure'), findsOneWidget);
    expect(find.textContaining('EAN32'), findsWidgets);
  });

  testWidgets('a target pressure below the start shows an error', (
    tester,
  ) async {
    final ref = await _pump(tester);

    ref.read(blenderStartPressureProvider.notifier).state = 250;
    await tester.pumpAndSettle();

    expect(find.textContaining('higher than the starting'), findsOneWidget);
    expect(find.text('Fill procedure'), findsNothing);
  });

  testWidgets('a trimix target produces a Tx fill procedure', (tester) async {
    final ref = await _pump(tester);

    ref.read(blenderTargetMixProvider.notifier).state = const GasMix(
      o2: 18,
      he: 45,
    );
    await tester.pumpAndSettle();

    expect(find.text('Fill procedure'), findsOneWidget);
    expect(find.textContaining('Tx 18/45'), findsWidgets);
  });

  testWidgets('the default fill order tops off with air, not helium', (
    tester,
  ) async {
    final ref = await _pump(tester);

    expect(ref.read(blenderFillGas1Provider), const GasMix(o2: 100));
    expect(ref.read(blenderFillGas2Provider), const GasMix(o2: 0, he: 100));
    expect(ref.read(blenderFillGas3Provider), const GasMix(o2: 21));
  });

  testWidgets('a nitrox target skips the helium source in the defaults', (
    tester,
  ) async {
    await _pump(tester);

    // Defaults are an empty cylinder to EAN32: O2 then air, no helium step.
    expect(find.textContaining('Fill Air to'), findsOneWidget);
    expect(find.textContaining('Helium'), findsNothing);
  });

  testWidgets('amounts are real gas quantities for the chosen cylinder', (
    tester,
  ) async {
    await _pump(tester);

    // 27.164 and 167.921 surface litres per litre of cylinder, in a 12 L tank.
    expect(find.textContaining('326 L'), findsOneWidget);
    expect(find.textContaining('2015 L'), findsOneWidget);
  });

  testWidgets('a larger cylinder scales the amounts', (tester) async {
    final ref = await _pump(tester);

    ref.read(blenderTankProvider.notifier).state = TankSpec.fromPreset(
      TankPresets.steel15,
    );
    await tester.pumpAndSettle();

    // 27.164 x 15 L = 407 L of oxygen.
    expect(find.textContaining('407 L'), findsOneWidget);
  });

  testWidgets('an over-rich cylinder is told what to drain to', (tester) async {
    final ref = await _pump(tester);

    ref.read(blenderStartPressureProvider.notifier).state = 150;
    ref.read(blenderStartMixProvider.notifier).state = const GasMix(o2: 40);
    ref.read(blenderTargetMixProvider.notifier).state = const GasMix(o2: 28);
    await tester.pumpAndSettle();

    expect(find.textContaining('Drain to'), findsOneWidget);
    expect(find.text('Fill procedure'), findsNothing);
  });
}
