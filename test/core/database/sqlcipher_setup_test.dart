import 'package:flutter_test/flutter_test.dart';

import 'package:submersion/core/database/sqlcipher_setup.dart';

void main() {
  test('setupSqlcipher is callable and idempotent on the host', () {
    // On the host (not Android) this must be a no-op that never throws,
    // and calling it twice must be safe (per-isolate re-entry happens on
    // every background open).
    expect(setupSqlcipher, returnsNormally);
    expect(setupSqlcipher, returnsNormally);
  });
}
