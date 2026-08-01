import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/database.dart';

/// Minimal pre-v138 shape: a diver_settings table with just a primary key,
/// stamped at v137 so only the 137->138 default_currency migration runs.
NativeDatabase _dbAt137() {
  return NativeDatabase.memory(
    setup: (rawDb) {
      rawDb.execute('PRAGMA user_version = 137');
      rawDb.execute('''
        CREATE TABLE diver_settings (
          id TEXT NOT NULL PRIMARY KEY
        )
      ''');
      rawDb.execute("INSERT INTO diver_settings (id) VALUES ('settings')");
    },
  );
}

void main() {
  test(
    'v138 adds default_currency to diver_settings, defaulting to USD',
    () async {
      final db = AppDatabase(_dbAt137());
      addTearDown(db.close);

      final cols = await db
          .customSelect("PRAGMA table_info('diver_settings')")
          .get();
      final names = cols.map((c) => c.read<String>('name')).toSet();
      expect(names, contains('default_currency'));

      final rows = await db
          .customSelect('SELECT default_currency FROM diver_settings')
          .get();
      expect(rows.single.read<String>('default_currency'), 'USD');
    },
  );

  test('v138 default_currency migration is present', () {
    expect(AppDatabase.currentSchemaVersion, greaterThanOrEqualTo(138));
    expect(AppDatabase.migrationVersions, contains(138));
  });
}
