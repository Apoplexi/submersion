import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/dive_log/domain/entities/gas_switch.dart';
import 'package:submersion/features/dive_log/presentation/providers/dive_providers.dart';
import 'package:submersion/features/dive_log/presentation/providers/gas_switch_providers.dart';

void main() {
  test('augments real map with an estimated line for a manual tank', () async {
    final dive = Dive(
      id: 'd1',
      dateTime: DateTime(2026, 1, 1),
      tanks: const [
        DiveTank(
          id: 't1',
          gasMix: GasMix(o2: 21),
          startPressure: 200,
          endPressure: 60,
        ),
      ],
      profile: const [
        DiveProfilePoint(timestamp: 0, depth: 0),
        DiveProfilePoint(timestamp: 1800, depth: 0),
      ],
    );

    final container = ProviderContainer(
      overrides: [
        tankPressuresProvider(
          'd1',
        ).overrideWith((ref) async => <String, List<TankPressurePoint>>{}),
        diveProvider('d1').overrideWith((ref) async => dive),
        gasSwitchesProvider(
          'd1',
        ).overrideWith((ref) async => <GasSwitchWithTank>[]),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(
      estimatedTankPressuresProvider('d1').future,
    );

    expect(result.estimatedTankIds, {'t1'});
    expect(result.pressures['t1']!.first.pressure, 200);
    expect(result.pressures['t1']!.last.pressure, 60);
  });
}
