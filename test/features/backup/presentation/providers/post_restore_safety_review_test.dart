import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:submersion/core/database/database.dart';
import 'package:submersion/core/services/log_file_service.dart';
import 'package:submersion/features/backup/presentation/providers/post_restore_safety_review.dart';
import 'package:submersion/features/settings/presentation/providers/debug_log_providers.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';

import '../../../../helpers/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late SharedPreferences prefs;

  setUp(() async {
    db = await setUpTestDatabase();
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    final ts = DateTime.utc(2026, 8, 8).millisecondsSinceEpoch;
    // Foreign keys are enforced, so the owning diver must exist first.
    await db
        .into(db.divers)
        .insert(
          DiversCompanion(
            id: const Value('diver-a'),
            name: const Value('Diver A'),
            // Default diver: with no id in SharedPreferences, SettingsNotifier
            // falls back to getDefaultDiver() to decide whose settings to load.
            isDefault: const Value(true),
            createdAt: Value(ts),
            updatedAt: Value(ts),
          ),
        );
    await db
        .into(db.dives)
        .insert(
          DivesCompanion(
            id: const Value('d1'),
            diverId: const Value('diver-a'),
            diveDateTime: Value(ts),
            createdAt: Value(ts),
            updatedAt: Value(ts),
          ),
        );
  });

  tearDown(() => tearDownTestDatabase());

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        // Never initialized, so no directory is created.
        logFileServiceProvider.overrideWithValue(
          LogFileService(logDirectory: '/tmp/submersion-test'),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test('runs a whole-library sweep and reports progress', () async {
    final seen = <(int, int)>[];

    final result = await makeContainer()
        .read(postRestoreSafetyReviewProvider)
        .run(onProgress: (done, total) => seen.add((done, total)));

    // The dive has no profile, so nothing is persisted -- but it is visited,
    // which is what proves the scratch container reached the restored data.
    expect(result.swept, 1);
    expect(result.cancelled, isFalse);
    expect(seen.first, (0, 1));
    expect(seen.last, (1, 1));
  });

  // The whole point of the throwaway container: it must grade against the
  // RESTORED database's settings, not the process-wide defaults. Turning the
  // master toggle off in the restored diver's row is the cheapest observable
  // proof -- the sweep can only no-op if it actually read that row, since the
  // default for safetyReviewEnabled is on.
  test('reads settings from the restored database, not the defaults', () async {
    await db
        .into(db.diverSettings)
        .insert(
          DiverSettingsCompanion(
            id: const Value('s1'),
            diverId: const Value('diver-a'),
            safetyReviewEnabled: const Value(false),
            createdAt: Value(DateTime.utc(2026, 8, 8).millisecondsSinceEpoch),
            updatedAt: Value(DateTime.utc(2026, 8, 8).millisecondsSinceEpoch),
          ),
        );

    final result = await makeContainer()
        .read(postRestoreSafetyReviewProvider)
        .run();

    expect(
      result.swept,
      0,
      reason: 'the restored diver has the safety review switched off',
    );
  });

  test('honours cancellation', () async {
    final result = await makeContainer()
        .read(postRestoreSafetyReviewProvider)
        .run(isCancelled: () => true);

    expect(result.cancelled, isTrue);
    expect(result.swept, 0);
  });
}
