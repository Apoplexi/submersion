import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _TinyDb extends GeneratedDatabase {
  _TinyDb(super.e);

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  int get schemaVersion => 1;
}

void main() {
  test('db.close() stalls when a watch() subscription is paused '
      '(the Riverpod 3 auto-pause scenario)', () async {
    final db = _TinyDb(NativeDatabase.memory());
    await db.customStatement('CREATE TABLE t (id INTEGER PRIMARY KEY)');

    final stream = db.customSelect('SELECT id FROM t').watch();
    // Wait for the first snapshot so the stream is fully live before pausing;
    // a fixed sleep here would be timing-dependent on contended CI.
    final firstSnapshot = Completer<void>();
    final subscription = stream.listen((_) {
      if (!firstSnapshot.isCompleted) firstSnapshot.complete();
    });
    await firstSnapshot.future;

    // What Riverpod 3 does to the streams of providers nobody listens to.
    subscription.pause();

    final closed = db
        .close()
        .then((_) => 'closed')
        .timeout(const Duration(seconds: 2), onTimeout: () => 'timed out');

    expect(
      await closed,
      'timed out',
      reason: 'a paused subscription blocks StreamQueryStore.close()',
    );

    // Cleanup so the test process can exit.
    subscription.resume();
    await subscription.cancel();
  }, timeout: const Timeout(Duration(seconds: 30)));
}
