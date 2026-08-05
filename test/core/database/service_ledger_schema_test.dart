import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/database.dart';

import '../../helpers/test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  test('built-in kinds are seeded on fresh install', () async {
    final kinds = await db.select(db.serviceKinds).get();
    expect(kinds.length, 9);
    expect(kinds.every((k) => k.isBuiltIn), isTrue);
    final hydro = kinds.firstWhere((k) => k.id == 'hydro');
    expect(hydro.defaultIntervalDays, 1825);
    expect(hydro.autoAttach, isTrue);
    final reg = kinds.firstWhere((k) => k.id == 'regulator-service');
    expect(reg.defaultIntervalDives, 100);
  });

  test('pre-existing built-in kinds keep null hour intervals', () async {
    // Characterization: pins the current seed so adding an hours column to
    // kSeedBuiltInServiceKindsSql cannot silently shift a positional value.
    final kinds = await db.select(db.serviceKinds).get();
    final byId = {for (final k in kinds) k.id: k};

    expect(
      byId.keys,
      containsAll(<String>[
        'hydro',
        'vip',
        'o2-clean',
        'regulator-service',
        'computer-battery',
        'transmitter-battery',
        'bcd-inspection',
        'drysuit-seals',
        'general-service',
      ]),
    );

    for (final id in byId.keys) {
      expect(
        byId[id]!.defaultIntervalHours,
        isNull,
        reason: '$id must not gain an hours interval',
      );
    }

    expect(byId['vip']!.defaultIntervalDays, 365);
    expect(byId['o2-clean']!.autoAttach, isFalse);
    expect(byId['drysuit-seals']!.defaultIntervalDays, 730);
    expect(byId['general-service']!.defaultIntervalDays, isNull);
    expect(byId['general-service']!.defaultIntervalDives, isNull);
    expect(byId['general-service']!.applicableTypes, '[]');
  });

  test(
    'service_schedules round-trips and cascades on equipment delete',
    () async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await db
          .into(db.equipment)
          .insert(
            EquipmentCompanion.insert(
              id: 'e1',
              name: 'AL80',
              type: 'tank',
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.serviceSchedules)
          .insert(
            ServiceSchedulesCompanion.insert(
              id: 's1',
              equipmentId: 'e1',
              serviceKindId: 'hydro',
              createdAt: now,
              updatedAt: now,
            ),
          );
      final rows = await db.select(db.serviceSchedules).get();
      expect(rows, hasLength(1));
      expect(rows.first.enabled, isTrue); // default
      expect(rows.first.intervalDays, null); // inherit kind default

      await (db.delete(db.equipment)..where((t) => t.id.equals('e1'))).go();
      expect(await db.select(db.serviceSchedules).get(), isEmpty); // cascade
    },
  );

  test('fresh install has the service ledger indexes', () async {
    final idx = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type='index' "
          "AND name LIKE 'idx_service_%'",
        )
        .get();
    expect(
      idx.map((r) => r.data['name']),
      containsAll([
        'idx_service_schedules_equipment',
        'idx_service_records_kind',
      ]),
    );
  });
}
