import 'package:drift/drift.dart';

import 'package:submersion/core/database/local_cache_database.dart';
import 'package:submersion/core/services/local_cache_database_service.dart';

/// One indexed file under a watched root.
class IndexedFile {
  const IndexedFile({
    required this.rootPath,
    required this.relativePath,
    required this.sizeBytes,
    required this.mtimeMillis,
    this.contentHash,
  });

  final String rootPath;
  final String relativePath;
  final int sizeBytes;
  final int mtimeMillis;
  final String? contentHash;

  String get absolutePath => '$rootPath/$relativePath';
}

/// Per-device watcher state (Media section Phase 5): which folders to scan
/// and what was found in them last time.
///
/// Lives in the local cache database because every value here is derivable
/// from the filesystem in front of this device -- syncing a path from
/// another machine would only produce warnings about roots that do not
/// exist here.
class WatchedFolderRepository {
  WatchedFolderRepository({LocalCacheDatabase? database})
    : _database = database;

  final LocalCacheDatabase? _database;

  LocalCacheDatabase get _db =>
      _database ?? LocalCacheDatabaseService.instance.database;

  Future<List<String>> getRoots() async {
    final rows = await (_db.select(
      _db.watchedRoots,
    )..orderBy([(t) => OrderingTerm.asc(t.path)])).get();
    return [for (final row in rows) row.path];
  }

  Future<void> addRoot(String path) async {
    await _db
        .into(_db.watchedRoots)
        .insertOnConflictUpdate(
          WatchedRootsCompanion(
            path: Value(path),
            addedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
  }

  /// Drops the root and everything indexed beneath it -- a root the user
  /// removed must not keep feeding the auto-repair pass.
  Future<void> removeRoot(String path) async {
    await _db.transaction(() async {
      await (_db.delete(
        _db.watchedRoots,
      )..where((t) => t.path.equals(path))).go();
      await (_db.delete(
        _db.watchedFolderIndex,
      )..where((t) => t.rootPath.equals(path))).go();
    });
  }

  Future<DateTime?> lastScanAt(String rootPath) async {
    final row = await (_db.select(
      _db.watchedRoots,
    )..where((t) => t.path.equals(rootPath))).getSingleOrNull();
    final stamp = row?.lastScanAt;
    return stamp == null ? null : DateTime.fromMillisecondsSinceEpoch(stamp);
  }

  Future<void> stampScanned(String rootPath, DateTime at) async {
    await (_db.update(
      _db.watchedRoots,
    )..where((t) => t.path.equals(rootPath))).write(
      WatchedRootsCompanion(lastScanAt: Value(at.millisecondsSinceEpoch)),
    );
  }

  /// Everything indexed under [rootPath], keyed by relative path.
  Future<Map<String, IndexedFile>> indexForRoot(String rootPath) async {
    final rows = await (_db.select(
      _db.watchedFolderIndex,
    )..where((t) => t.rootPath.equals(rootPath))).get();
    return {
      for (final row in rows)
        row.relativePath: IndexedFile(
          rootPath: row.rootPath,
          relativePath: row.relativePath,
          sizeBytes: row.sizeBytes,
          mtimeMillis: row.mtimeMillis,
          contentHash: row.contentHash,
        ),
    };
  }

  Future<void> upsertIndexed(IndexedFile file) async {
    await _db
        .into(_db.watchedFolderIndex)
        .insertOnConflictUpdate(
          WatchedFolderIndexCompanion(
            rootPath: Value(file.rootPath),
            relativePath: Value(file.relativePath),
            sizeBytes: Value(file.sizeBytes),
            mtimeMillis: Value(file.mtimeMillis),
            contentHash: Value(file.contentHash),
          ),
        );
  }

  /// Drops index rows under [rootPath] whose file was not seen this scan.
  Future<void> pruneMissing(
    String rootPath,
    Set<String> keepRelativePaths,
  ) async {
    await (_db.delete(_db.watchedFolderIndex)..where(
          (t) =>
              t.rootPath.equals(rootPath) &
              t.relativePath.isNotIn(keepRelativePaths),
        ))
        .go();
  }

  /// Content hash to absolute path across every watched root -- the lookup
  /// the auto-repair pass runs against missing rows.
  Future<Map<String, String>> hashToPath() async {
    final rows = await (_db.select(
      _db.watchedFolderIndex,
    )..where((t) => t.contentHash.isNotNull())).get();
    return {
      for (final row in rows)
        row.contentHash!: '${row.rootPath}/${row.relativePath}',
    };
  }
}
