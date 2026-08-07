import 'dart:io';

import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';

/// Applies the per-isolate sqlite3 loader override needed for SQLCipher.
///
/// `open.overrideFor` is per-isolate state: call this in EVERY isolate that
/// opens the database — the main isolate (bootstrap), the drift worker
/// isolate opener, and the Workmanager headless isolate.
///
/// Only Android needs an explicit override with sqlcipher_flutter_libs; on
/// iOS/macOS the pod links SQLCipher, and on Windows/Linux the bundled
/// library is picked up by the default loader. Idempotent.
void setupSqlcipher() {
  if (Platform.isAndroid) {
    open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
  }
}

/// The PRAGMA that keys a SQLCipher connection with a raw (already
/// KDF-stretched) 32-byte key, given as 64 hex chars. Must be the first
/// statement executed on the connection.
///
/// Top-level here (not on DatabaseService) so the drift worker isolate and
/// the encryption migrator can build it without importing
/// database_service.dart — that file imports both of them.
String cipherKeyPragma(String keyHex) => 'PRAGMA key = "x\'$keyHex\'"';
