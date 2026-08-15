import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:submersion/core/database/database.dart';
import 'package:submersion/core/services/database_service.dart';
import 'package:submersion/features/dive_3d/domain/spatial/seascape_appearance.dart';
import 'package:submersion/features/divers/presentation/providers/diver_providers.dart';
import 'package:submersion/features/settings/data/repositories/diver_settings_repository.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';

import '../../helpers/test_database.dart';

/// Drives the real [SettingsNotifier] so the device-local seascape
/// appearance load/save path is exercised end to end (same harness as the
/// deco stop settings test: the notifier resolves a default diver from the
/// database even before any setter runs).
void main() {
  late AppDatabase db;

  Future<ProviderContainer> containerWith(Map<String, Object> prefsSeed) async {
    SharedPreferences.setMockInitialValues({
      currentDiverIdKey: 'd1',
      ...prefsSeed,
    });
    final prefs = await SharedPreferences.getInstance();
    db = await setUpTestDatabase();
    final now = DateTime.now().millisecondsSinceEpoch;
    await db
        .into(db.divers)
        .insert(
          DiversCompanion.insert(
            id: 'd1',
            name: 'Test Diver',
            createdAt: now,
            updatedAt: now,
          ),
        );
    await DiverSettingsRepository().createSettingsForDiver('d1');
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    container.read(settingsProvider);
    await Future<void>.delayed(Duration.zero);
    return container;
  }

  tearDown(() {
    DatabaseService.instance.resetForTesting();
  });

  test('loads seascape appearance from SharedPreferences', () async {
    const stored = SeascapeAppearance(rampBanded: true, wallAngleDeg: 30.0);
    final container = await containerWith({
      SettingsKeys.seascapeAppearance: stored.encode(),
    });
    expect(container.read(settingsProvider).seascapeAppearance, stored);
  });

  test('setSeascapeAppearance updates state and persists to prefs', () async {
    final container = await containerWith({});
    expect(
      container.read(settingsProvider).seascapeAppearance,
      const SeascapeAppearance(),
    );

    const next = SeascapeAppearance(
      rampMaxDepthMeters: 40.0,
      contourMode: SeascapeContourMode.custom,
      customLevels: [SeascapeContourLevel(depthMeters: 10.0)],
    );
    await container.read(settingsProvider.notifier).setSeascapeAppearance(next);

    expect(container.read(settingsProvider).seascapeAppearance, next);
    final prefs = await SharedPreferences.getInstance();
    expect(
      SeascapeAppearance.decode(
        prefs.getString(SettingsKeys.seascapeAppearance),
      ),
      next,
    );
  });
}
