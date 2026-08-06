import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' show OpenMode;

import 'package:submersion/core/database/sqlcipher_setup.dart';
import 'package:submersion/core/services/database_service.dart';
import 'package:submersion/core/services/security/database_encryption_migrator.dart';
import 'package:submersion/core/services/security/database_locked_exception.dart';
import 'package:submersion/core/services/security/database_security_sidecar.dart';
import 'package:submersion/core/services/security/database_security_service.dart';
import 'package:submersion/core/services/sync/crypto/keyslots.dart';

/// The only place the REAL SQLCipher runs under test: `flutter test` on the
/// host loads the system SQLite (no cipher), so encrypted opens, the export
/// choreography, and the key derivation are proven here, on-device.
///
/// Single testWidgets body on purpose: a second app launch in one
/// integration-test file hangs on macOS.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const testKdf = KdfParams(m: 64, t: 1, p: 1);

  testWidgets('full encryption lifecycle against real SQLCipher', (
    tester,
  ) async {
    setupSqlcipher();
    final tmp = await Directory.systemTemp.createTemp('dbsec_integration');
    addTearDown(() => tmp.delete(recursive: true));
    final dbPath = '${tmp.path}/submersion.db';

    // 0. Cipher is linked: raw open answers cipher_version.
    final probe = DatabaseService.openRaw(
      dbPath,
      mode: OpenMode.readWriteCreate,
    );
    expect(
      probe.select('PRAGMA cipher_version'),
      isNotEmpty,
      reason: 'sqlcipher_flutter_libs must be the linked sqlite3',
    );
    probe.execute('CREATE TABLE t (v TEXT)');
    probe.execute("INSERT INTO t VALUES ('dive-1')");
    probe.execute('PRAGMA user_version = 7');
    probe.dispose();
    expect(isEncryptedDatabaseFile(dbPath), false);

    // 1. Security + key derivation from the sidecar credential.
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final svc = DatabaseSecurityService.instance;
    svc.resetForTesting();
    await svc.configure(prefs: prefs);
    await svc.enableSecurity(
      password: 'correct-horse',
      dbPath: dbPath,
      kdf: testKdf,
    );
    final mlk = await Keyslots.tryUnwrap(
      file: (await DatabaseSecuritySidecar.read(dbPath))!,
      secret: 'correct-horse',
    );
    expect(mlk, isNotNull, reason: 'password must unwrap the sidecar');
    final keyHex = await DatabaseSecurityService.deriveDbKeyHex(mlk!);

    // 2. Encrypt in place with the REAL exporter.
    await DatabaseEncryptionMigrator().encryptInPlace(
      dbPath: dbPath,
      keyHex: keyHex,
    );
    expect(isEncryptedDatabaseFile(dbPath), true);

    // 3. Keyless and wrong-key opens fail as DatabaseLockedException; the
    //    keyed open works and user_version survived the export.
    expect(
      () => DatabaseService.getStoredSchemaVersion(dbPath),
      throwsA(
        isA<DatabaseLockedException>().having(
          (e) => e.wrongKey,
          'wrongKey',
          false,
        ),
      ),
    );
    expect(
      () => DatabaseService.getStoredSchemaVersion(dbPath, keyHex: 'ff' * 32),
      throwsA(
        isA<DatabaseLockedException>().having(
          (e) => e.wrongKey,
          'wrongKey',
          true,
        ),
      ),
    );
    expect(DatabaseService.getStoredSchemaVersion(dbPath, keyHex: keyHex), 7);
    final keyed = DatabaseService.openRaw(dbPath, keyHex: keyHex);
    expect(keyed.select('SELECT v FROM t').first.values.first, 'dive-1');
    keyed.dispose();

    // 4. Portable backup: decrypt-export produces a plaintext file.
    final backupPath = '${tmp.path}/backup.db';
    await sqlcipherExport(
      sourcePath: dbPath,
      targetPath: backupPath,
      sourceKeyHex: keyHex,
      targetKeyHex: null,
    );
    expect(isEncryptedDatabaseFile(backupPath), false);
    expect(DatabaseService.getStoredSchemaVersion(backupPath), 7);

    // 5. Decrypt in place round-trips.
    await DatabaseEncryptionMigrator().decryptInPlace(
      dbPath: dbPath,
      keyHex: keyHex,
    );
    expect(isEncryptedDatabaseFile(dbPath), false);
    expect(DatabaseService.getStoredSchemaVersion(dbPath), 7);
    final plain = DatabaseService.openRaw(dbPath);
    expect(plain.select('SELECT v FROM t').first.values.first, 'dive-1');
    plain.dispose();

    svc.resetForTesting();
  });
}
