import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/database.dart';
import 'package:submersion/core/services/sync/sync_data_serializer.dart';

void main() {
  test(
    'v145 folds buddy_roles rows into certifications and drops the table',
    () async {
      final nativeDb = NativeDatabase.memory(
        setup: (rawDb) {
          rawDb.execute('PRAGMA user_version = 144');
          rawDb.execute('''
          CREATE TABLE buddies (
            id TEXT NOT NULL PRIMARY KEY, diver_id TEXT, name TEXT NOT NULL,
            email TEXT, phone TEXT, photo_path TEXT,
            notes TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL, hlc TEXT)
        ''');
          rawDb.execute('''
          CREATE TABLE certifications (
            id TEXT NOT NULL PRIMARY KEY, diver_id TEXT, buddy_id TEXT,
            name TEXT NOT NULL, agency TEXT NOT NULL, level TEXT,
            card_number TEXT, issue_date INTEGER, expiry_date INTEGER,
            instructor_name TEXT, instructor_number TEXT, instructor_id TEXT,
            photo_front_path TEXT, photo_back_path TEXT, photo_front BLOB,
            photo_back BLOB, course_id TEXT, notes TEXT NOT NULL DEFAULT '',
            created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL, hlc TEXT)
        ''');
          rawDb.execute('''
          CREATE TABLE buddy_roles (
            id TEXT NOT NULL PRIMARY KEY, buddy_id TEXT NOT NULL,
            role TEXT NOT NULL, credential_number TEXT, agency TEXT,
            notes TEXT NOT NULL DEFAULT '', created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL, hlc TEXT)
        ''');

          rawDb.execute(
            "INSERT INTO buddies (id, name, created_at, updated_at) VALUES "
            "('b1', 'B1', 0, 0), ('b2', 'B2', 0, 0), ('b3', 'B3', 0, 0)",
          );

          // Pre-existing certifications for the dedupe fixtures.
          rawDb.execute(
            "INSERT INTO certifications "
            "(id, buddy_id, name, agency, level, card_number, notes, "
            "created_at, updated_at) VALUES "
            "('c-dm', 'b2', 'Divemaster', 'ssi', 'diveMaster', '999', '', "
            "0, 0)",
          );
          rawDb.execute(
            "INSERT INTO certifications "
            "(id, buddy_id, name, agency, level, card_number, notes, "
            "created_at, updated_at) VALUES "
            "('c-in', 'b2', 'Instructor', 'ssi', 'instructor', NULL, '', "
            "0, 0)",
          );

          // plain convert
          rawDb.execute(
            "INSERT INTO buddy_roles "
            "(id, buddy_id, role, credential_number, agency, notes, "
            "created_at, updated_at) VALUES "
            "('r1', 'b1', 'instructor', '111', 'padi', 'note', 1000, 2000)",
          );
          // dedupe skip (c-dm already has a card number)
          rawDb.execute(
            "INSERT INTO buddy_roles "
            "(id, buddy_id, role, credential_number, agency, notes, "
            "created_at, updated_at) VALUES "
            "('r2', 'b2', 'diveMaster', '222', 'ssi', '', 1000, 2000)",
          );
          // dedupe backfill (c-in has no card number)
          rawDb.execute(
            "INSERT INTO buddy_roles "
            "(id, buddy_id, role, credential_number, agency, notes, "
            "created_at, updated_at) VALUES "
            "('r3', 'b2', 'instructor', '333', 'ssi', '', 1000, 2000)",
          );
          // diveGuide + null agency
          rawDb.execute(
            "INSERT INTO buddy_roles "
            "(id, buddy_id, role, credential_number, agency, notes, "
            "created_at, updated_at) VALUES "
            "('r4', 'b3', 'diveGuide', NULL, NULL, '', 1000, 2000)",
          );
          // unknown role
          rawDb.execute(
            "INSERT INTO buddy_roles "
            "(id, buddy_id, role, credential_number, agency, notes, "
            "created_at, updated_at) VALUES "
            "('r5', 'b3', 'mermaid', '444', 'padi', '', 1000, 2000)",
          );
        },
      );

      final db = AppDatabase(nativeDb);
      addTearDown(() => db.close());

      // buddy_roles is gone.
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE name='buddy_roles'",
          )
          .get();
      expect(tables, isEmpty);

      // plain convert
      final r1Cert = await db
          .customSelect(
            "SELECT * FROM certifications WHERE id = 'buddyrolecert-r1'",
          )
          .getSingle();
      expect(r1Cert.data['buddy_id'], 'b1');
      expect(r1Cert.data['level'], 'instructor');
      expect(r1Cert.data['agency'], 'padi');
      expect(r1Cert.data['card_number'], '111');
      expect(r1Cert.data['name'], 'Instructor');
      expect(r1Cert.data['notes'], 'note');
      expect(r1Cert.data['created_at'], 1000);
      expect(r1Cert.data['updated_at'], 2000);
      expect(r1Cert.data['diver_id'], isNull);

      // dedupe skip: no new row, existing card number preserved.
      final r2Cert = await db
          .customSelect(
            "SELECT * FROM certifications WHERE id = 'buddyrolecert-r2'",
          )
          .get();
      expect(r2Cert, isEmpty);
      final cDm = await db
          .customSelect("SELECT * FROM certifications WHERE id = 'c-dm'")
          .getSingle();
      expect(cDm.data['card_number'], '999');

      // dedupe backfill: no new row, existing cert's card number filled in.
      final r3Cert = await db
          .customSelect(
            "SELECT * FROM certifications WHERE id = 'buddyrolecert-r3'",
          )
          .get();
      expect(r3Cert, isEmpty);
      final cIn = await db
          .customSelect("SELECT * FROM certifications WHERE id = 'c-in'")
          .getSingle();
      expect(cIn.data['card_number'], '333');

      // diveGuide + null agency.
      final r4Cert = await db
          .customSelect(
            "SELECT * FROM certifications WHERE id = 'buddyrolecert-r4'",
          )
          .getSingle();
      expect(r4Cert.data['buddy_id'], 'b3');
      expect(r4Cert.data['level'], 'diveGuide');
      expect(r4Cert.data['agency'], 'other');
      expect(r4Cert.data['card_number'], isNull);
      expect(r4Cert.data['name'], 'Dive Guide');
      expect(r4Cert.data['diver_id'], isNull);

      // unknown role: no cert row created.
      final r5Cert = await db
          .customSelect(
            "SELECT * FROM certifications WHERE id = 'buddyrolecert-r5'",
          )
          .get();
      expect(r5Cert, isEmpty);
    },
  );

  test(
    'a fresh v145+ database has no buddy_roles table (no-op shape)',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE name='buddy_roles'",
          )
          .get();
      expect(tables, isEmpty);
    },
  );

  test('version ladder includes 145', () {
    expect(AppDatabase.currentSchemaVersion, greaterThanOrEqualTo(145));
    expect(AppDatabase.migrationVersions, contains(145));
  });

  test('legacy buddyRoles payload section is silently ignored', () {
    // Old-schema peers still publish buddyRoles arrays; SyncData.fromJson has
    // no such field anymore, so the section must drop without error.
    final data = SyncData.fromJson({
      'buddyRoles': [
        {'id': 'r1', 'buddyId': 'b1', 'role': 'instructor'},
      ],
    });
    expect(data.toJson().containsKey('buddyRoles'), isFalse);
  });
}
