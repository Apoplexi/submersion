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
    final subscription = stream.listen((_) {});
    // Let the first snapshot arrive so the stream is fully live.
    await Future<void>.delayed(const Duration(milliseconds: 100));

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
