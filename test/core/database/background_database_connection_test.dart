import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/background_database_connection.dart';

/// Minimal drift database used only to drive the remote executor.
class _TinyDb extends GeneratedDatabase {
  _TinyDb(super.e);

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  int get schemaVersion => 1;
}

/// Stands in for the real SQLite close, which can take seconds when it has to
/// checkpoint a large WAL. Everything else forwards to [_inner].
class _SlowClosingExecutor implements QueryExecutor {
  _SlowClosingExecutor(this._inner, this._closeDelay);

  final QueryExecutor _inner;
  final Duration _closeDelay;

  @override
  Future<void> close() async {
    await Future<void>.delayed(_closeDelay);
    await _inner.close();
  }

  @override
  SqlDialect get dialect => _inner.dialect;

  @override
  Future<bool> ensureOpen(QueryExecutorUser user) => _inner.ensureOpen(user);

  @override
  Future<List<Map<String, Object?>>> runSelect(
    String statement,
    List<Object?> args,
  ) => _inner.runSelect(statement, args);

  @override
  Future<int> runInsert(String statement, List<Object?> args) =>
      _inner.runInsert(statement, args);

  @override
  Future<int> runUpdate(String statement, List<Object?> args) =>
      _inner.runUpdate(statement, args);

  @override
  Future<int> runDelete(String statement, List<Object?> args) =>
      _inner.runDelete(statement, args);

  @override
  Future<void> runCustom(String statement, [List<Object?>? args]) =>
      _inner.runCustom(statement, args);

  @override
  Future<void> runBatched(BatchedStatements statements) =>
      _inner.runBatched(statements);

  @override
  TransactionExecutor beginTransaction() => _inner.beginTransaction();

  @override
  QueryExecutor beginExclusive() => _inner.beginExclusive();
}

/// Built in its own scope so the closure sent to the worker isolate captures
/// nothing but the delay.
DatabaseConnection Function() _slowClosingOpener(int closeDelayMs) {
  return () => DatabaseConnection(
    _SlowClosingExecutor(
      NativeDatabase.memory(),
      Duration(milliseconds: closeDelayMs),
    ),
  );
}

void main() {
  const closeDelay = Duration(seconds: 2);

  test('awaitWorkerShutdown does not return until the worker has finished '
      'closing the database', () async {
    final connection = await BackgroundDatabaseConnection.open(
      File('unused-by-the-test-opener.db'),
      debugOpener: _slowClosingOpener(closeDelay.inMilliseconds),
    );
    final db = _TinyDb(connection.connection);
    await db.customSelect('SELECT 1').get();

    final sw = Stopwatch()..start();
    await db.close();
    final afterDbClose = sw.elapsed;

    final exitedCleanly = await connection.awaitWorkerShutdown(
      timeout: const Duration(seconds: 20),
      killIfStuck: false,
    );
    final afterWorkerShutdown = sw.elapsed;

    // The bug this guards against: drift answers the shutdown request before
    // the executor is closed, so db.close() alone returns early. Letting the
    // process exit at that point leaves the worker running FFI callbacks into
    // a VM that is tearing them down.
    expect(
      afterDbClose,
      lessThan(closeDelay),
      reason: 'db.close() is expected to return before the executor is closed',
    );
    expect(exitedCleanly, isTrue);
    expect(
      afterWorkerShutdown,
      greaterThanOrEqualTo(closeDelay),
      reason: 'awaitWorkerShutdown must wait for the real close',
    );
  }, timeout: const Timeout(Duration(seconds: 60)));

  test(
    'awaitWorkerShutdown kills a stuck worker when asked to',
    () async {
      final connection = await BackgroundDatabaseConnection.open(
        File('unused-by-the-test-opener.db'),
        debugOpener: _slowClosingOpener(
          const Duration(minutes: 5).inMilliseconds,
        ),
      );
      final db = _TinyDb(connection.connection);
      await db.customSelect('SELECT 1').get();
      await db.close();

      final exitedCleanly = await connection.awaitWorkerShutdown(
        timeout: const Duration(milliseconds: 300),
        killIfStuck: true,
      );

      expect(
        exitedCleanly,
        isFalse,
        reason: 'the worker was still closing, so it had to be killed',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'awaitWorkerShutdown throws instead of killing on reopen paths',
    () async {
      final connection = await BackgroundDatabaseConnection.open(
        File('unused-by-the-test-opener.db'),
        debugOpener: _slowClosingOpener(
          const Duration(minutes: 5).inMilliseconds,
        ),
      );
      final db = _TinyDb(connection.connection);
      await db.customSelect('SELECT 1').get();
      await db.close();

      await expectLater(
        connection.awaitWorkerShutdown(
          timeout: const Duration(milliseconds: 300),
          killIfStuck: false,
        ),
        throwsA(isA<TimeoutException>()),
      );

      // Killing is still available afterwards so the test does not leak a
      // worker isolate that would keep the test process alive.
      await connection.awaitWorkerShutdown(
        timeout: const Duration(milliseconds: 100),
        killIfStuck: true,
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test('closeDatabaseForAppShutdown closes SQLite despite a paused watch() '
      'subscription (Riverpod 3 auto-pause at quit)', () async {
    final dir = Directory.systemTemp.createTempSync('bg_conn_paused');
    addTearDown(() => dir.deleteSync(recursive: true));

    final connection = await BackgroundDatabaseConnection.open(
      File('${dir.path}/app.db'),
    );
    final db = _TinyDb(connection.connection);
    await db.customStatement('CREATE TABLE t (id INTEGER PRIMARY KEY)');

    // A live watch() whose subscription is paused makes db.close() hang in
    // streamQueries.close() before the executor is ever asked to close —
    // exactly what Riverpod 3 does to unlistened providers' streams.
    final firstSnapshot = Completer<void>();
    final subscription = db.customSelect('SELECT id FROM t').watch().listen((
      _,
    ) {
      if (!firstSnapshot.isCompleted) firstSnapshot.complete();
    });
    // Pause only once the stream is live; a fixed sleep would be flaky on
    // contended CI.
    await firstSnapshot.future;
    subscription.pause();

    final sw = Stopwatch()..start();
    final clean = await closeDatabaseForAppShutdown(
      db,
      background: connection,
      gracefulTimeout: const Duration(milliseconds: 300),
    );
    sw.stop();

    expect(clean, isTrue, reason: 'the worker must exit without a kill');
    expect(
      sw.elapsed,
      lessThan(const Duration(seconds: 4)),
      reason: 'shutdown must not sit out full timeouts',
    );
    // The worker really closed SQLite: a completed close removes the WAL.
    expect(File('${dir.path}/app.db-wal').existsSync(), isFalse);

    subscription.resume();
    await subscription.cancel();
  }, timeout: const Timeout(Duration(seconds: 60)));

  test(
    'opens a usable database on the worker isolate',
    () async {
      final dir = Directory.systemTemp.createTempSync('bg_conn');
      addTearDown(() => dir.deleteSync(recursive: true));

      final connection = await BackgroundDatabaseConnection.open(
        File('${dir.path}/app.db'),
      );
      final db = _TinyDb(connection.connection);

      await db.customStatement('CREATE TABLE t (id INTEGER PRIMARY KEY)');
      await db.customStatement('INSERT INTO t (id) VALUES (7)');
      final rows = await db.customSelect('SELECT id FROM t').get();
      expect(rows.single.read<int>('id'), 7);

      await db.close();
      final exitedCleanly = await connection.awaitWorkerShutdown(
        timeout: const Duration(seconds: 20),
        killIfStuck: false,
      );

      expect(exitedCleanly, isTrue);
      expect(File('${dir.path}/app.db').existsSync(), isTrue);
      // A completed SQLite close removes the WAL sidecars.
      expect(File('${dir.path}/app.db-wal').existsSync(), isFalse);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
