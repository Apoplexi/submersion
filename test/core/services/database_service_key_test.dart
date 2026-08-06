import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' show OpenMode;

import 'package:submersion/core/services/database_service.dart';
import 'package:submersion/core/services/security/database_locked_exception.dart';

void main() {
  test('cipherKeyPragma formats a raw-key pragma', () {
    expect(DatabaseService.cipherKeyPragma('ab01'), 'PRAGMA key = "x\'ab01\'"');
  });

  test(
    'getStoredSchemaVersion still works keyless on a plaintext db',
    () async {
      final tmp = await Directory.systemTemp.createTemp('dbsvc_key');
      addTearDown(() => tmp.delete(recursive: true));
      final path = '${tmp.path}/plain.db';
      final db = DatabaseService.openRaw(path, mode: OpenMode.readWriteCreate);
      db.execute('PRAGMA user_version = 42');
      db.dispose();
      expect(DatabaseService.getStoredSchemaVersion(path), 42);
    },
  );

  test(
    'encrypted-looking file without a key throws DatabaseLockedException',
    () async {
      final tmp = await Directory.systemTemp.createTemp('dbsvc_key');
      addTearDown(() => tmp.delete(recursive: true));
      final path = '${tmp.path}/enc.db';
      File(
        path,
      ).writeAsBytesSync(List<int>.generate(4096, (i) => (i * 37 + 11) % 256));
      expect(
        () => DatabaseService.getStoredSchemaVersion(path),
        throwsA(
          isA<DatabaseLockedException>().having(
            (e) => e.wrongKey,
            'wrongKey',
            false,
          ),
        ),
      );
    },
  );
}
