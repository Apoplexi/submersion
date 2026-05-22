import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/database.dart';

void main() {
  group('Migration v73 - GPS entry/exit on dives', () {
    test('fresh database has GPS columns on dives', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final cols = await db.customSelect("PRAGMA table_info('dives')").get();
      final names = cols.map((c) => c.read<String>('name')).toSet();

      expect(
        names,
        containsAll(<String>[
          'entry_latitude',
          'entry_longitude',
          'exit_latitude',
          'exit_longitude',
        ]),
      );
    });

    test('a dive round-trips its GPS coordinates', () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final now = DateTime.now().millisecondsSinceEpoch;
      await db
          .into(db.dives)
          .insert(
            DivesCompanion.insert(
              id: 'gps-1',
              diveDateTime: now,
              createdAt: now,
              updatedAt: now,
              entryLatitude: const Value(12.34567),
              entryLongitude: const Value(98.76543),
              exitLatitude: const Value(12.34612),
              exitLongitude: const Value(98.76489),
            ),
          );

      final row = await (db.select(
        db.dives,
      )..where((t) => t.id.equals('gps-1'))).getSingle();
      expect(row.entryLatitude, 12.34567);
      expect(row.exitLongitude, 98.76489);
    });
  });
}
