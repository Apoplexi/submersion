# Site Media Attachments Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Attach photos, videos, and documents (PDFs and common file types) to dive sites, and enable document attachments on dives (issues #211, #627).

**Architecture:** Reuse the existing `media` table's `siteId` FK (already synced and merge-safe); add the missing read path, providers, and UI. Extract a shared media grid core from `DiveMediaSection` and build a new `SiteMediaSection` on it. Documents are a new `MediaType.document` stored by reference (bookmark/SAF/path) like desktop photos; PDFs render in-app via `pdfrx` and get real page-1 thumbnails; site deletion gets an HLC-stamped media cascade mirroring the dive-side fix.

**Tech Stack:** Flutter/Dart, Drift ORM, Riverpod (legacy StateNotifier imports), file_picker, photo_manager, pdfrx (new dependency), share_plus.

**Spec:** `docs/superpowers/specs/2026-08-10-site-media-attachments-design.md`

## Global Constraints

- Work in worktree `.claude/worktrees/site-media-attachments`, branch `worktree-site-media-attachments`. Run all commands from the worktree root.
- After every task: `dart format .` (whole project) must produce no changes at commit time.
- `flutter analyze` on the WHOLE project must be clean — infos are fatal in CI.
- Every user-visible string goes through `context.l10n.<key>`. New keys must be added to ALL 11 ARB files: `lib/l10n/arb/app_{ar,de,en,es,fr,he,hu,it,nl,pt,zh}.arb`, then run `flutter gen-l10n`. EXCEPTION: shared widgets that both dive and site sections consume take display strings as constructor parameters (adding l10n inside a shared widget breaks consumer widget tests — established project trap).
- SHARED-WIDGET TRAP: widget tests that pump a widget using `context.l10n` need a `MaterialApp` with localization delegates. Follow the pattern in `test/features/media/presentation/widgets/dive_media_section_test.dart`.
- No emojis anywhere. No `console.log`-style debug prints. Immutability (copyWith) for entities.
- Schema version goes 147 -> 148 exactly once (Task 3). Any task run out of order must not re-bump it.
- Commit after each task with the message given in the task. Do NOT add a Co-Authored-By line or session URL.
- Tests use `flutter test <path>` per task; a per-file timeout of 120s is normal for repository tests. The full suite runs in Task 15 only.
- Riverpod: this project uses Riverpod 3 with legacy StateNotifier imported via `package:submersion/core/providers/provider.dart` (NOT `package:flutter_riverpod/flutter_riverpod.dart` for providers files). Copy imports from the files you modify.

## File Structure

| File | Responsibility |
| --- | --- |
| `lib/features/media/domain/entities/media_item.dart` | Modify: `MediaType.document`, `isDocument`/`isPdf`/`documentExtension` getters, mime cases |
| `lib/features/media/data/repositories/media_repository.dart` | Modify: site reads, site-deletion partition/unlink |
| `lib/core/database/database.dart` | Modify: v148 migration (site index + dedupe unique index) |
| `lib/core/database/performance_indexes.dart` | Modify: `idx_media_site_id` |
| `lib/features/dive_sites/data/repositories/site_repository_impl.dart` | Modify: media cascade on site delete |
| `lib/features/media/presentation/providers/site_media_providers.dart` | Create: site media providers + notifier |
| `lib/features/media/presentation/widgets/media_grid.dart` | Create: shared grid pieces (tile, selection header, empty state) |
| `lib/features/media/presentation/widgets/dive_media_section.dart` | Modify: compose shared pieces, add-document menu |
| `lib/features/media/presentation/widgets/site_media_section.dart` | Create: site attachments section |
| `lib/features/media/presentation/pages/site_media_viewer_page.dart` | Create: site-scoped photo viewer |
| `lib/features/media/presentation/pages/document_viewer_page.dart` | Create: in-app PDF viewer |
| `lib/features/media/data/services/document_import_service.dart` | Create: reference-linking document attach |
| `lib/features/media/data/services/pdf_page_renderer.dart` | Create: PDF page-1 -> JPEG bytes |
| `lib/features/media/data/services/media_import_service.dart` | Modify: `importPhotosForSite` |
| `lib/features/media/presentation/helpers/site_media_import_helper.dart` | Create: site add-photos / add-document flows |
| `lib/features/media_store/data/thumbnail_generator.dart` | Modify: PDF branch |
| `lib/core/services/media_store/store_keys.dart` | Modify: document content types |
| `lib/features/dive_sites/presentation/pages/site_detail_page.dart` | Modify: mount `SiteMediaSection` |
| `lib/features/dive_log/presentation/pages/dive_detail_page.dart` | Modify: add-document wiring |
| `lib/features/media/presentation/pages/photo_viewer_page.dart` | Modify: exclude documents from photo list |

---

## Phase 1: Data layer

### Task 1: `MediaType.document` and document getters

**Files:**
- Modify: `lib/features/media/domain/entities/media_item.dart`
- Test: `test/features/media/domain/entities/media_item_document_test.dart` (create)

**Interfaces:**
- Produces: `MediaType.document`; `MediaItem.isDocument` (bool), `MediaItem.isPdf` (bool), `MediaItem.documentExtension` (String, lowercase without dot, `''` when unknown). Later tasks (tiles, thumbnails, viewers) branch on these.

- [ ] **Step 1: Write the failing test**

Create `test/features/media/domain/entities/media_item_document_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/media/domain/entities/media_item.dart';

MediaItem _doc(String? filename) => MediaItem(
  id: 'm1',
  mediaType: MediaType.document,
  originalFilename: filename,
  takenAt: DateTime(2026),
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  test('MediaType.document round-trips through fromString', () {
    expect(MediaType.fromString('document'), MediaType.document);
    expect(MediaType.document.name, 'document');
  });

  test('isDocument true only for document type', () {
    expect(_doc('map.pdf').isDocument, isTrue);
    expect(
      _doc('map.pdf').copyWith(mediaType: MediaType.photo).isDocument,
      isFalse,
    );
  });

  test('isPdf keys on extension case-insensitively', () {
    expect(_doc('reef-map.pdf').isPdf, isTrue);
    expect(_doc('reef-map.PDF').isPdf, isTrue);
    expect(_doc('notes.docx').isPdf, isFalse);
    expect(_doc(null).isPdf, isFalse);
  });

  test('documentExtension lowercases and strips the dot', () {
    expect(_doc('Map.PDF').documentExtension, 'pdf');
    expect(_doc('notes.docx').documentExtension, 'docx');
    expect(_doc('README').documentExtension, '');
    expect(_doc(null).documentExtension, '');
  });

  test('shareMimeType maps pdf', () {
    expect(_doc('map.pdf').shareMimeType, 'application/pdf');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/media/domain/entities/media_item_document_test.dart`
Expected: FAIL — `document` is not a member of `MediaType`.

- [ ] **Step 3: Implement**

In `lib/features/media/domain/entities/media_item.dart`:

1. Add `document` to the enum (line ~7) and its `displayName` case:

```dart
enum MediaType {
  photo,
  video,
  instructorSignature,
  document;

  String get displayName {
    switch (this) {
      case MediaType.photo:
        return 'Photo';
      case MediaType.video:
        return 'Video';
      case MediaType.instructorSignature:
        return 'Instructor Signature';
      case MediaType.document:
        return 'Document';
    }
  }
  // fromString unchanged (name-based, picks up the new member automatically)
}
```

2. Next to `bool get isVideo` (line ~153) add:

```dart
  /// True for attachment documents (PDFs and opaque files).
  bool get isDocument => mediaType == MediaType.document;

  /// Lowercased extension of [originalFilename] without the dot; '' when
  /// absent. Presentation-only: storage addressing uses StoreKeys.
  String get documentExtension {
    final name = originalFilename;
    if (name == null) return '';
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  /// True for documents that render in the in-app PDF viewer.
  bool get isPdf => isDocument && documentExtension == 'pdf';
```

3. In the `shareMimeType` switch (line ~171), add cases before the default:

```dart
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'txt':
        return 'text/plain';
      case 'gpx':
        return 'application/gpx+xml';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/media/domain/entities/media_item_document_test.dart`
Expected: PASS. Also run `flutter test test/features/media/domain/` to catch enum-exhaustiveness breaks in sibling tests; fix any switch over `MediaType` that fails to compile by adding a `document` case that behaves like `photo` unless the surrounding code is video-specific.

- [ ] **Step 5: Format and commit**

```bash
dart format .
git add -A
git commit -m "Add MediaType.document with pdf/document helpers"
```

### Task 2: Repository site reads

**Files:**
- Modify: `lib/features/media/data/repositories/media_repository.dart`
- Test: `test/features/media/data/repositories/media_repository_site_test.dart` (create)

**Interfaces:**
- Consumes: existing `_mapRowToMediaItem`, `_db.media`, `_db.mediaEnrichment`.
- Produces:
  - `Future<List<domain.MediaItem>> getMediaForSite(String siteId)` — ordered by `takenAt` ascending, includes enrichment when present.
  - `Future<int> getMediaCountForSite(String siteId)`
  - `Future<Set<String>> getLinkedAssetIdsForSite(String siteId)` — non-null `platformAssetId`s of rows with this `siteId` (dedupe for gallery imports).
  - `Future<Set<String>> getLinkedLocalPathsForSite(String siteId)` — non-null `localPath`s (dedupe for file imports).

- [ ] **Step 1: Write the failing test**

Create `test/features/media/data/repositories/media_repository_site_test.dart`. Copy the test-database setUp/tearDown scaffolding from the top of `test/features/media/data/repositories/media_repository_test.dart` verbatim (in-memory `AppDatabase` + `DatabaseService` override) — do not invent your own harness. Then:

```dart
  group('getMediaForSite', () {
    test('returns only media linked to the site, ordered by takenAt', () async {
      // Insert a site row 'site-1' and a dive row 'dive-1' using the same
      // companion helpers the existing tests in media_repository_test.dart
      // use. Then three media rows via repository.createMedia:
      final late1 = await repository.createMedia(
        MediaItem(
          id: '',
          siteId: 'site-1',
          mediaType: MediaType.photo,
          takenAt: DateTime(2026, 3, 2),
          createdAt: DateTime(2026, 3, 2),
          updatedAt: DateTime(2026, 3, 2),
        ),
      );
      final early = await repository.createMedia(
        MediaItem(
          id: '',
          siteId: 'site-1',
          mediaType: MediaType.document,
          originalFilename: 'map.pdf',
          takenAt: DateTime(2026, 3, 1),
          createdAt: DateTime(2026, 3, 1),
          updatedAt: DateTime(2026, 3, 1),
        ),
      );
      await repository.createMedia(
        MediaItem(
          id: '',
          diveId: 'dive-1',
          mediaType: MediaType.photo,
          takenAt: DateTime(2026, 3, 3),
          createdAt: DateTime(2026, 3, 3),
          updatedAt: DateTime(2026, 3, 3),
        ),
      );

      final result = await repository.getMediaForSite('site-1');
      expect(result.map((m) => m.id), [early.id, late1.id]);
      expect(await repository.getMediaCountForSite('site-1'), 2);
      expect(await repository.getMediaCountForSite('site-none'), 0);
    });

    test('linked asset ids and local paths for dedupe', () async {
      await repository.createMedia(
        MediaItem(
          id: '',
          siteId: 'site-1',
          platformAssetId: 'asset-9',
          mediaType: MediaType.photo,
          takenAt: DateTime(2026),
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
      await repository.createMedia(
        MediaItem(
          id: '',
          siteId: 'site-1',
          sourceType: MediaSourceType.localFile,
          localPath: '/tmp/map.pdf',
          mediaType: MediaType.document,
          originalFilename: 'map.pdf',
          takenAt: DateTime(2026),
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        ),
      );
      expect(await repository.getLinkedAssetIdsForSite('site-1'), {'asset-9'});
      expect(await repository.getLinkedLocalPathsForSite('site-1'), {
        '/tmp/map.pdf',
      });
    });
  });
```

Note: creating media with a `siteId` requires the referenced site row to exist only if FKs are ON in the harness — the existing scaffolding runs with `PRAGMA foreign_keys = ON` via `beforeOpen`, so insert minimal `dive_sites` / `dives` parent rows first (copy the insert helpers used by `media_repository_cascade_test.dart` in `test/features/media/data/`).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/media/data/repositories/media_repository_site_test.dart`
Expected: FAIL — `getMediaForSite` undefined.

- [ ] **Step 3: Implement**

In `media_repository.dart`, directly below `getMediaForDive` (line ~70), mirroring its shape:

```dart
  /// Get all media directly attached to a site, ordered by takenAt.
  /// Enrichment rides along for rows that are also dive-linked.
  Future<List<domain.MediaItem>> getMediaForSite(String siteId) async {
    try {
      final query =
          _db.select(_db.media).join([
              leftOuterJoin(
                _db.mediaEnrichment,
                _db.mediaEnrichment.mediaId.equalsExp(_db.media.id),
              ),
            ])
            ..where(_db.media.siteId.equals(siteId))
            ..orderBy([OrderingTerm.asc(_db.media.takenAt)]);

      final rows = await query.get();
      return rows.map((row) {
        final mediaRow = row.readTable(_db.media);
        final enrichmentRow = row.readTableOrNull(_db.mediaEnrichment);
        return _mapRowToMediaItem(mediaRow, enrichmentRow);
      }).toList();
    } catch (e, stackTrace) {
      _log.error(
        'Failed to get media for site: $siteId',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Count of media directly attached to a site (badges/headers).
  Future<int> getMediaCountForSite(String siteId) async {
    final count = _db.media.id.count();
    final query = _db.selectOnly(_db.media)
      ..addColumns([count])
      ..where(_db.media.siteId.equals(siteId));
    final row = await query.getSingle();
    return row.read(count) ?? 0;
  }

  /// Platform asset ids already linked to [siteId] (gallery-import dedupe;
  /// site counterpart of getLinkedAssetIdsForDive).
  Future<Set<String>> getLinkedAssetIdsForSite(String siteId) async {
    final assetId = _db.media.platformAssetId;
    final query = _db.selectOnly(_db.media)
      ..addColumns([assetId])
      ..where(_db.media.siteId.equals(siteId) & assetId.isNotNull());
    final rows = await query.get();
    return rows.map((r) => r.read(assetId)!).toSet();
  }

  /// Local paths already linked to [siteId] (file-import dedupe; site
  /// counterpart of getLinkedLocalPathsForDive).
  Future<Set<String>> getLinkedLocalPathsForSite(String siteId) async {
    final path = _db.media.localPath;
    final query = _db.selectOnly(_db.media)
      ..addColumns([path])
      ..where(_db.media.siteId.equals(siteId) & path.isNotNull());
    final rows = await query.get();
    return rows.map((r) => r.read(path)!).toSet();
  }
```

Before writing, open the existing `getLinkedAssetIdsForDive` / `getLinkedLocalPathsForDive` in the same file and match their exact style (column selection, null handling) — if they differ from the above, follow the file, not this plan.

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/media/data/repositories/media_repository_site_test.dart`
Expected: PASS.

- [ ] **Step 5: Format and commit**

```bash
dart format .
git add -A
git commit -m "Add site media read path to MediaRepository"
```

### Task 3: Migration v148 — site index and site dedupe index

**Files:**
- Modify: `lib/core/database/database.dart`
- Modify: `lib/core/database/performance_indexes.dart`

**Interfaces:**
- Produces: schema version 148; indexes `idx_media_site_id` and `idx_media_asset_site_unique` exist on fresh and upgraded databases.

- [ ] **Step 1: Bump schema version**

In `lib/core/database/database.dart`:
- `static const int currentSchemaVersion = 147;` (line ~2939) becomes `148`.
- Append `148,` to the end of the `migrationVersions` list (line ~2944).
- Confirm `schemaVersion` getter reads `currentSchemaVersion` (it does; no other change).

- [ ] **Step 2: Add the migration block**

Directly after `if (from < 147) await reportProgress();` (line ~7666), add:

```dart
        if (from < 148) {
          // Site media (issues #211/#627). Query index for the site gallery;
          // dedupe cleanup + partial unique index mirroring the dive-side
          // v38 pair so the same gallery asset cannot be linked to the same
          // site twice. Keep the oldest duplicate (lowest created_at).
          await customStatement('''
            CREATE INDEX IF NOT EXISTS idx_media_site_id
            ON media(site_id)
          ''');
          await customStatement('''
            DELETE FROM media WHERE id IN (
              SELECT m.id FROM media m
              INNER JOIN (
                SELECT platform_asset_id, site_id, MIN(created_at) as min_created
                FROM media
                WHERE platform_asset_id IS NOT NULL AND site_id IS NOT NULL
                GROUP BY platform_asset_id, site_id
                HAVING COUNT(*) > 1
              ) dupes ON m.platform_asset_id = dupes.platform_asset_id
                AND m.site_id = dupes.site_id
                AND m.created_at > dupes.min_created
            )
          ''');
          await customStatement('''
            CREATE UNIQUE INDEX IF NOT EXISTS idx_media_asset_site_unique
            ON media(platform_asset_id, site_id)
            WHERE platform_asset_id IS NOT NULL AND site_id IS NOT NULL
          ''');
        }
        if (from < 148) await reportProgress();
```

- [ ] **Step 3: Register the query index for fresh databases**

In `lib/core/database/performance_indexes.dart`, add to the media group (near `idx_media_platform_asset_id`, line ~176):

```dart
  (
    name: 'idx_media_site_id',
    ddl:
        'CREATE INDEX IF NOT EXISTS idx_media_site_id '
        'ON media(site_id)',
  ),
```

(The partial unique index is migration-created; check how `idx_media_asset_dive_unique` is asserted for fresh databases — search `database.dart` for `idx_media_asset_dive_unique` outside the `from < 38` block. If it is also created in `beforeOpen` or an `onCreate` path, add `idx_media_asset_site_unique` beside it the same way; if fresh databases get it purely via `onCreate` running all migrations, no extra step is needed.)

- [ ] **Step 4: Verify**

Run: `flutter test test/core/database/` (schema/migration tests)
Expected: PASS. If a schema-verification test asserts the exact version, it now sees 148 from the constant, so no fixture edit should be needed; if one fails listing expected indexes, add the two new names to it.

- [ ] **Step 5: Format and commit**

```bash
dart format .
git add -A
git commit -m "Add v148 migration: media site index and site dedupe index"
```

### Task 4: HLC-stamped media cascade on site deletion

**Files:**
- Modify: `lib/features/media/data/repositories/media_repository.dart`
- Modify: `lib/features/dive_sites/data/repositories/site_repository_impl.dart`
- Test: `test/features/media/data/media_repository_site_cascade_test.dart` (create)

**Interfaces:**
- Consumes: `MediaDeletionCoordinator` (`lib/features/media_store/data/media_deletion_coordinator.dart` — verify path via its import in `dive_repository_impl.dart`), `MediaTransferQueueRepository`.
- Produces:
  - `MediaRepository.partitionMediaForSiteDeletion(List<String> siteIds)` -> `({List<domain.MediaItem> doomed, List<String> unlinkIds})`
  - `MediaRepository.unlinkMediaFromDeletedSites(List<String> mediaIds)`
  - `SiteRepository` factory now injectable: `SiteRepository({MediaRepository? mediaRepository, MediaDeletionCoordinator? mediaDeletionCoordinator})`; `deleteSite(String id, {bool cascadeMedia = true})`, `bulkDeleteSites(List<String> ids, {bool cascadeMedia = true})`.

- [ ] **Step 1: Write the failing test**

Create `test/features/media/data/media_repository_site_cascade_test.dart`, scaffolding copied from `test/features/media/data/media_repository_cascade_test.dart` (same DB harness and parent-row helpers). Test bodies:

```dart
  group('partitionMediaForSiteDeletion', () {
    test('site-only media is doomed; dive-linked and library rows unlink',
        () async {
      // parent rows: site-1, dive-1
      final siteOnly = await repository.createMedia(/* siteId: 'site-1' */);
      final diveLinked = await repository.createMedia(
        /* siteId: 'site-1', diveId: 'dive-1' */
      );
      final libraryRow = await repository.createMedia(
        /* siteId: 'site-1', sourceType: MediaSourceType.networkUrl */
      );

      final split = await repository.partitionMediaForSiteDeletion(['site-1']);
      expect(split.doomed.map((m) => m.id), [siteOnly.id]);
      expect(
        split.unlinkIds.toSet(),
        {diveLinked.id, libraryRow.id},
      );
    });

    test('empty input returns empty partition', () async {
      final split = await repository.partitionMediaForSiteDeletion([]);
      expect(split.doomed, isEmpty);
      expect(split.unlinkIds, isEmpty);
    });
  });

  group('unlinkMediaFromDeletedSites', () {
    test('nulls siteId, bumps updatedAt, marks sync-pending', () async {
      final m = await repository.createMedia(/* siteId: 'site-1' */);
      await repository.unlinkMediaFromDeletedSites([m.id]);
      final after = await repository.getMediaById(m.id);
      expect(after!.siteId, isNull);
      // sync pending: assert via the same sync_pending query the dive
      // cascade test uses.
    });
  });
```

Fill the `/* ... */` companions exactly as the dive cascade test builds its media items (full MediaItem constructors with takenAt/createdAt/updatedAt). Also add a `SiteRepository.deleteSite` integration case: create site + site-only media + dive-linked media, call `SiteRepository(...).deleteSite('site-1')` with an injected recording `MediaDeletionCoordinator` fake (copy the fake from the dive cascade test), and assert: the site row is gone, the site-only item was passed to `deleteMediaItems`, the dive-linked row survives with `siteId == null`.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/media/data/media_repository_site_cascade_test.dart`
Expected: FAIL — methods undefined.

- [ ] **Step 3: Implement the repository half**

In `media_repository.dart` directly below `unlinkMediaFromDeletedDives` (line ~1067):

```dart
  /// Splits a dying site's media: `doomed` rows die with the site
  /// (site-only, non-library), `unlinkIds` survive as dive-linked or
  /// library-level rows with siteId nulled. Site counterpart of
  /// [partitionMediaForDiveDeletion].
  Future<({List<domain.MediaItem> doomed, List<String> unlinkIds})>
  partitionMediaForSiteDeletion(List<String> siteIds) async {
    if (siteIds.isEmpty) {
      return (doomed: const <domain.MediaItem>[], unlinkIds: const <String>[]);
    }
    final rows = await (_db.select(
      _db.media,
    )..where((t) => t.siteId.isIn(siteIds))).get();
    final doomed = <domain.MediaItem>[];
    final unlinkIds = <String>[];
    for (final row in rows) {
      final keep =
          row.diveId != null ||
          libraryLevelSourceTypes.contains(row.sourceType);
      if (keep) {
        unlinkIds.add(row.id);
      } else {
        doomed.add(_mapRowToMediaItem(row));
      }
    }
    return (doomed: doomed, unlinkIds: unlinkIds);
  }

  /// Explicitly unlinks surviving media from deleted sites, with the HLC
  /// stamp the silent FK SET NULL never produced. Site counterpart of
  /// [unlinkMediaFromDeletedDives].
  Future<void> unlinkMediaFromDeletedSites(List<String> mediaIds) async {
    if (mediaIds.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction(() async {
      await (_db.update(_db.media)..where((t) => t.id.isIn(mediaIds))).write(
        MediaCompanion(siteId: const Value(null), updatedAt: Value(now)),
      );
      for (final id in mediaIds) {
        await _syncRepository.markRecordPending(
          entityType: 'media',
          recordId: id,
          localUpdatedAt: now,
        );
      }
    });
    SyncEventBus.notifyLocalChange();
  }
```

- [ ] **Step 4: Implement the site-repository half**

In `site_repository_impl.dart` (class is named `SiteRepository`, line 15):

1. Mirror `DiveRepository`'s injectable factory (see `dive_repository_impl.dart:62-84`):

```dart
  factory SiteRepository({
    MediaRepository? mediaRepository,
    MediaDeletionCoordinator? mediaDeletionCoordinator,
  }) {
    final media = mediaRepository ?? MediaRepository();
    return SiteRepository._(
      media,
      mediaDeletionCoordinator ??
          MediaDeletionCoordinator(
            mediaRepository: media,
            queue: () => MediaTransferQueueRepository(),
          ),
    );
  }

  SiteRepository._(this._mediaRepository, this._mediaDeletionCoordinator);

  final MediaRepository _mediaRepository;
  final MediaDeletionCoordinator _mediaDeletionCoordinator;
```

If `SiteRepository` currently has a default generative constructor used broadly, keep source compatibility: the factory above IS the unnamed constructor, so `SiteRepository()` callers compile unchanged. Copy the exact imports for `MediaDeletionCoordinator` and `MediaTransferQueueRepository` from `dive_repository_impl.dart`.

2. Add the cascade and wire it in:

```dart
  /// Cascade a dying site's media: site-only rows die with the site
  /// (via the coordinator's enqueue-before-delete path); dive-linked and
  /// library-level rows survive with siteId nulled and HLC-stamped.
  /// Mirrors DiveRepository._cascadeMediaForDiveDeletion.
  Future<void> _cascadeMediaForSiteDeletion(List<String> ids) async {
    final split = await _mediaRepository.partitionMediaForSiteDeletion(ids);
    if (split.doomed.isNotEmpty) {
      await _mediaDeletionCoordinator.deleteMediaItems(split.doomed);
    }
    if (split.unlinkIds.isNotEmpty) {
      await _mediaRepository.unlinkMediaFromDeletedSites(split.unlinkIds);
    }
  }
```

In `deleteSite` (line ~301) add the parameter and call before the row delete:

```dart
  Future<void> deleteSite(String id, {bool cascadeMedia = true}) async {
    try {
      _log.info('Deleting site: $id');
      if (cascadeMedia) await _cascadeMediaForSiteDeletion([id]);
      await (_db.delete(_db.diveSites)..where((t) => t.id.equals(id))).go();
      ...
```

Same pattern in `bulkDeleteSites` (line ~336): `if (cascadeMedia) await _cascadeMediaForSiteDeletion(ids);` before the bulk delete.

3. Check the site MERGE path (`mergeSites`, line ~359 onward): it relinks media to the survivor via `_relinkMedia` BEFORE deleting merged-away sites. Find how merged sites are deleted — if via `deleteSite`/`bulkDeleteSites`, pass `cascadeMedia: false` there (media was already relinked; the cascade must not race the undo snapshot). If it deletes rows directly with `_db.delete`, leave it as is.

- [ ] **Step 5: Run tests**

Run: `flutter test test/features/media/data/media_repository_site_cascade_test.dart test/features/media/data/media_repository_cascade_test.dart test/features/dive_sites/`
Expected: PASS (existing site tests confirm the factory change broke nothing).

- [ ] **Step 6: Format and commit**

```bash
dart format .
git add -A
git commit -m "Cascade site deletion through media partition with HLC stamps"
```

---

## Phase 2: Providers

### Task 5: Site media providers

**Files:**
- Create: `lib/features/media/presentation/providers/site_media_providers.dart`
- Test: `test/features/media/presentation/providers/site_media_providers_test.dart` (create)

**Interfaces:**
- Consumes: `mediaRepositoryProvider`, `mediaDeletionCoordinatorProvider` (exported by `media_store_providers.dart`), `diveRepositoryProvider.getDivesForSite(siteId)`.
- Produces:
  - `mediaForSiteProvider` — `FutureProvider.family<List<MediaItem>, String>`
  - `mediaCountForSiteProvider` — `FutureProvider.family<int, String>`
  - `siteMediaListNotifierProvider` — `StateNotifierProvider.family<SiteMediaListNotifier, AsyncValue<List<MediaItem>>, String>` with `refresh()`, `addMedia(MediaItem)`, `updateMedia(MediaItem)`, `deleteMultipleMedia(List<String>)`
  - `mediaFromDivesAtSiteProvider` — `FutureProvider.family<Map<Dive, List<MediaItem>>, String>` (dive-photo aggregation, trip pattern)
  - `flatMediaFromDivesAtSiteProvider` — `FutureProvider.family<List<MediaItem>, String>` (viewer navigation, sorted by takenAt)

- [ ] **Step 1: Write the failing test**

Create `test/features/media/presentation/providers/site_media_providers_test.dart`. Use a `ProviderContainer` with the real repository over the standard in-memory DB harness (copy container setup from `test/features/media/presentation/providers/` siblings — if none exists there, copy the DB harness from `media_repository_site_test.dart` and build a bare `ProviderContainer()`):

```dart
  test('mediaForSiteProvider returns direct attachments', () async {
    // seed site-1 + one media row via MediaRepository
    final list = await container.read(mediaForSiteProvider('site-1').future);
    expect(list, hasLength(1));
    expect(await container.read(mediaCountForSiteProvider('site-1').future), 1);
  });

  test('notifier deleteMultipleMedia removes rows and refreshes', () async {
    // seed two rows; read notifier, delete one, expect state has one left
  });

  test('mediaFromDivesAtSiteProvider groups by dive and drops empty dives',
      () async {
    // seed dive-1 at site-1 with one media row, dive-2 at site-1 with none
    final grouped = await container.read(
      mediaFromDivesAtSiteProvider('site-1').future,
    );
    expect(grouped.keys.map((d) => d.id), ['dive-1']);
  });
```

Flesh out seeding with the same parent-row helpers as Task 2's test.

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/media/presentation/providers/site_media_providers_test.dart`
Expected: FAIL — file does not exist.

- [ ] **Step 3: Implement**

Create `lib/features/media/presentation/providers/site_media_providers.dart`:

```dart
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/dive_log/presentation/providers/dive_repository_provider.dart';
import 'package:submersion/features/media/data/repositories/media_repository.dart';
import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media/presentation/providers/media_providers.dart';
import 'package:submersion/features/media_store/presentation/providers/media_store_providers.dart';

/// Media directly attached to a site (attachments group), ordered by takenAt.
final mediaForSiteProvider = FutureProvider.family<List<MediaItem>, String>((
  ref,
  siteId,
) async {
  final repository = ref.watch(mediaRepositoryProvider);
  ref.invalidateSelfWhen(repository.watchMediaChanges());
  return repository.getMediaForSite(siteId);
});

/// Count of direct site attachments (badges/headers).
final mediaCountForSiteProvider = FutureProvider.family<int, String>((
  ref,
  siteId,
) async {
  final repository = ref.watch(mediaRepositoryProvider);
  ref.invalidateSelfWhen(repository.watchMediaChanges());
  return repository.getMediaCountForSite(siteId);
});

/// Media from dives logged at the site, grouped by dive with empty dives
/// dropped. Same bounded fan-out as mediaForTripProvider.
final mediaFromDivesAtSiteProvider =
    FutureProvider.family<Map<Dive, List<MediaItem>>, String>((
      ref,
      siteId,
    ) async {
      final dives = await ref
          .watch(diveRepositoryProvider)
          .getDivesForSite(siteId);
      if (dives.isEmpty) return {};

      const chunkSize = 12;
      final mediaLists = <List<MediaItem>>[];
      for (var offset = 0; offset < dives.length; offset += chunkSize) {
        final chunk = dives.skip(offset).take(chunkSize);
        mediaLists.addAll(
          await Future.wait(
            chunk.map(
              (dive) => ref.watch(mediaForDiveProvider(dive.id).future),
            ),
          ),
        );
      }

      final Map<Dive, List<MediaItem>> result = {};
      for (var i = 0; i < dives.length; i++) {
        if (mediaLists[i].isNotEmpty) {
          result[dives[i]] = mediaLists[i];
        }
      }
      return result;
    });

/// Flat, chronological dive-photo list for the site viewer.
final flatMediaFromDivesAtSiteProvider =
    FutureProvider.family<List<MediaItem>, String>((ref, siteId) async {
      final grouped = await ref.watch(
        mediaFromDivesAtSiteProvider(siteId).future,
      );
      final all = grouped.values.expand((list) => list).toList();
      all.sort((a, b) => a.takenAt.compareTo(b.takenAt));
      return all;
    });

/// Mutations on a site's direct attachments. Site counterpart of
/// MediaListNotifier.
class SiteMediaListNotifier extends StateNotifier<AsyncValue<List<MediaItem>>> {
  final MediaRepository _repository;
  final Ref _ref;
  final String _siteId;

  SiteMediaListNotifier(this._repository, this._ref, this._siteId)
    : super(const AsyncValue.loading()) {
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    state = const AsyncValue.loading();
    try {
      final media = await _repository.getMediaForSite(_siteId);
      state = AsyncValue.data(media);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() async {
    await _loadMedia();
    _ref.invalidate(mediaForSiteProvider(_siteId));
    _ref.invalidate(mediaCountForSiteProvider(_siteId));
  }

  Future<MediaItem> addMedia(MediaItem item) async {
    final newItem = await _repository.createMedia(item);
    await refresh();
    return newItem;
  }

  Future<void> updateMedia(MediaItem item) async {
    await _repository.updateMedia(item);
    await refresh();
    _ref.invalidate(mediaByIdProvider(item.id));
  }

  /// Routed through the deletion coordinator so remote-blob delete intents
  /// are enqueued before rows die (orphan-prevention spec 5.2).
  Future<void> deleteMultipleMedia(List<String> ids) async {
    await _ref.read(mediaDeletionCoordinatorProvider).deleteMultipleMedia(ids);
    await refresh();
  }
}

final siteMediaListNotifierProvider =
    StateNotifierProvider.family<
      SiteMediaListNotifier,
      AsyncValue<List<MediaItem>>,
      String
    >((ref, siteId) {
      final repository = ref.watch(mediaRepositoryProvider);
      return SiteMediaListNotifier(repository, ref, siteId);
    });
```

Verify `getDivesForSite` exists on the dive repository (`dive_repository_impl.dart:2046`) and returns `List<Dive>`; verify `invalidateSelfWhen` is available via `core/providers/provider.dart` (it is used the same way in `mediaForDiveProvider`).

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/media/presentation/providers/site_media_providers_test.dart`
Expected: PASS.

- [ ] **Step 5: Format and commit**

```bash
dart format .
git add -A
git commit -m "Add site media providers and mutation notifier"
```

---

## Phase 3: Shared grid extraction

### Task 6: Extract shared media grid pieces

**Files:**
- Create: `lib/features/media/presentation/widgets/media_grid.dart`
- Modify: `lib/features/media/presentation/widgets/dive_media_section.dart`
- Test: existing `test/features/media/presentation/widgets/dive_media_section_test.dart` must keep passing; new `test/features/media/presentation/widgets/media_grid_test.dart`

**Interfaces:**
- Produces (all in `media_grid.dart`, all taking display strings as parameters — NO `context.l10n` inside these shared widgets, per the global l10n constraint):

```dart
class MediaSelectionHeader extends StatelessWidget {
  final int selectedCount;
  final int totalCount;
  final VoidCallback onSelectAll;
  final VoidCallback onCancel;
  final VoidCallback onUnlinkSelected;
  final String selectedCountLabel;   // e.g. l10n.media_diveMediaSection_selectedCount(n)
  final String selectAllLabel;
  final String cancelTooltip;
  final String unlinkTooltip;
  const MediaSelectionHeader({...});
}

class MediaEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const MediaEmptyState({required this.icon, required this.message, ...});
}

class MediaThumbnailTile extends StatelessWidget {
  final MediaItem item;
  final AppSettings settings;
  final bool isSelectionMode;
  final bool isSelected;
  final String semanticsLabel;
  const MediaThumbnailTile({...});
}

class OrphanedMediaPlaceholder extends StatelessWidget { ... }
```

- [ ] **Step 1: Move the pieces**

Create `media_grid.dart` by MOVING (not copying) these private classes out of `dive_media_section.dart`, renamed public:
- `_SelectionHeader` -> `MediaSelectionHeader` (lines 467-514). Replace the four `context.l10n.*` calls with the new string parameters.
- `_EmptyMediaState` -> `MediaEmptyState` (lines 517-551). Parameterize icon and message (`Icons.photo_camera_outlined` + `l10n.media_diveMediaSection_emptyState` become the dive call-site's arguments).
- `_MediaThumbnailContent` -> `MediaThumbnailTile` (lines 559-688). Parameterize the semantics label. Keep the store badge, video badge, selection overlays, and depth badge exactly as they are (the depth badge self-hides when `item.enrichment == null`, so site usage needs no flag). Add ONE new branch after the video-icon block — the document tile treatment:

```dart
            // Document badge (top-right, mirrors the video badge slot)
            if (item.isDocument && !isSelected)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.documentExtension.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
```

- `_OrphanedPlaceholder` -> `OrphanedMediaPlaceholder` (lines 691-708).

Imports for the new file: copy from `dive_media_section.dart` (MediaItem, MediaItemView, MediaStoreBadge, UnitFormatter, settings providers, material).

- [ ] **Step 2: Rewire `DiveMediaSection`**

In `dive_media_section.dart`: import `media_grid.dart`; replace the four private-class usages with the public ones, passing the l10n strings at the call sites, e.g.:

```dart
              mediaAsync.whenOrNull(
                    data: (media) => MediaSelectionHeader(
                      selectedCount: _selectedIndices.length,
                      totalCount: media.length,
                      onSelectAll: () => _selectAll(media.length),
                      onCancel: _exitSelectionMode,
                      onUnlinkSelected: () => _unlinkSelected(context, media),
                      selectedCountLabel: context.l10n
                          .media_diveMediaSection_selectedCount(
                            _selectedIndices.length,
                          ),
                      selectAllLabel: context
                          .l10n.media_diveMediaSection_selectAllButton,
                      cancelTooltip: context
                          .l10n.media_diveMediaSection_cancelSelectionButton,
                      unlinkTooltip: context.l10n
                          .media_diveMediaSection_unlinkSelectedButton(
                            _selectedIndices.length,
                          ),
                    ),
                  ) ??
                  const SizedBox.shrink()
```

and

```dart
                if (media.isEmpty) {
                  return MediaEmptyState(
                    icon: Icons.photo_camera_outlined,
                    message: context.l10n.media_diveMediaSection_emptyState,
                  );
                }
```

and in the itemBuilder:

```dart
                  itemBuilder: (context, item, isSelected) {
                    final thumbnail = MediaThumbnailTile(
                      item: item,
                      settings: settings,
                      isSelectionMode: _isSelectionMode,
                      isSelected: isSelected,
                      semanticsLabel:
                          context.l10n.media_diveMediaSection_thumbnailLabel,
                    );
                    ...
```

The orphaned branch inside `MediaThumbnailTile` moves WITH the tile (the tile itself decides `item.isOrphaned ? OrphanedMediaPlaceholder() : MediaItemView(...)`) so both sections get it for free — mirror how `_MediaThumbnailContent` currently receives the decision from outside (lines 589-597) by moving that `if` INSIDE the tile's build.

- [ ] **Step 3: Write the grid test**

Create `test/features/media/presentation/widgets/media_grid_test.dart` (harness copied from `dive_media_section_test.dart` — MaterialApp + ProviderScope with overrides):

```dart
  testWidgets('MediaEmptyState renders icon and message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MediaEmptyState(icon: Icons.map_outlined, message: 'No media'),
        ),
      ),
    );
    expect(find.text('No media'), findsOneWidget);
    expect(find.byIcon(Icons.map_outlined), findsOneWidget);
  });

  testWidgets('MediaSelectionHeader disables unlink at zero selection',
      (tester) async {
    // pump with selectedCount: 0 and assert the delete IconButton onPressed
    // is null; with selectedCount: 1 assert it is enabled.
  });
```

(Do not attempt to render `MediaThumbnailTile` with a real item — it needs the resolver pipeline; the existing dive tests already cover the composed rendering paths.)

- [ ] **Step 4: Run tests**

Run: `flutter test test/features/media/presentation/widgets/media_grid_test.dart test/features/media/presentation/widgets/dive_media_section_test.dart test/features/media/presentation/widgets/dive_media_section_lightroom_test.dart`
Expected: PASS — the refactor is behavior-preserving.

- [ ] **Step 5: Format and commit**

```bash
dart format .
git add -A
git commit -m "Extract shared media grid pieces from DiveMediaSection"
```

---

## Phase 4: Site UI

### Task 7: Site media viewer page

**Files:**
- Create: `lib/features/media/presentation/pages/site_media_viewer_page.dart`
- Test: `test/features/media/presentation/pages/site_media_viewer_page_test.dart` (create)

**Interfaces:**
- Consumes: `mediaForSiteProvider`, `flatMediaFromDivesAtSiteProvider` (Task 5), `MediaItemView`, `resolvedFullResolutionProvider`, `writeShareTempFile`.
- Produces: `SiteMediaViewerPage({required String siteId, required String initialMediaId, required SiteViewerScope scope})` where `enum SiteViewerScope { attachments, divePhotos }` picks which list backs the pager.

- [ ] **Step 1: Implement the page**

Model on `trip_photo_viewer_page.dart` with these deltas (copy its structure wholesale, then apply):

1. Class/fields:

```dart
enum SiteViewerScope { attachments, divePhotos }

class SiteMediaViewerPage extends ConsumerStatefulWidget {
  final String siteId;
  final String initialMediaId;
  final SiteViewerScope scope;

  const SiteMediaViewerPage({
    super.key,
    required this.siteId,
    required this.initialMediaId,
    required this.scope,
  });
  ...
}
```

2. List source in `build` — filter documents out (they open in `DocumentViewerPage`, not the photo pager):

```dart
    final sourceAsync = widget.scope == SiteViewerScope.attachments
        ? ref.watch(mediaForSiteProvider(widget.siteId))
        : ref.watch(flatMediaFromDivesAtSiteProvider(widget.siteId));
    final mediaAsync = sourceAsync.whenData(
      (list) => list.where((m) => !m.isDocument).toList(),
    );
```

3. Drop the dive-context pieces: no `mediaForTripProvider` lookup, no `_findDiveForMedia`, no `PositionedMiniProfileOverlay`, and the bottom overlay passes `siteName: null` (delete the site-name row entirely). Everything else — immersive mode, `PhotoViewGallery` via `MediaItemView(fit: BoxFit.contain)`, swipe-down-to-close, share via `resolvedFullResolutionProvider` + `writeShareTempFile` + `SharePlus` — stays identical to the trip page (reuse its l10n keys `media_photoViewer_*`, which are viewer-generic).

4. The private helper classes `_PhotoGallery`, `_TopOverlay`, `_BottomMetadataOverlay`, `_MetadataChip` are small and page-private in the trip file; replicate the ones you need privately in this file rather than exporting them from the trip page (they are 40-120 lines each; page-private duplication is the established pattern — the trip page itself duplicated them from `photo_viewer_page.dart`).

- [ ] **Step 2: Write the smoke test**

```dart
  testWidgets('shows empty message when site has no photos', (tester) async {
    // ProviderScope overriding mediaForSiteProvider('site-1') with
    // AsyncValue.data(const <MediaItem>[]) via a FutureProvider override;
    // pump SiteMediaViewerPage(siteId: 'site-1', initialMediaId: 'x',
    // scope: SiteViewerScope.attachments) inside MaterialApp with l10n
    // delegates; expect the media_photoViewer_noPhotosAvailable text.
  });
```

Copy the l10n-capable MaterialApp harness from an existing page test (e.g. `test/features/media/presentation/widgets/dive_media_section_test.dart`).

- [ ] **Step 3: Run tests**

Run: `flutter test test/features/media/presentation/pages/site_media_viewer_page_test.dart`
Expected: PASS.

- [ ] **Step 4: Format and commit**

```bash
dart format .
git add -A
git commit -m "Add site-scoped media viewer page"
```

### Task 8: SiteMediaSection widget

**Files:**
- Create: `lib/features/media/presentation/widgets/site_media_section.dart`
- Test: `test/features/media/presentation/widgets/site_media_section_test.dart` (create)

**Interfaces:**
- Consumes: Task 5 providers, Task 6 grid pieces, Task 7 viewer, `DocumentViewerPage` (Task 12 — until then, tapping a PDF routes through a callback, see below).
- Produces: `SiteMediaSection({required String siteId, VoidCallback? onAddPhotosPressed, VoidCallback? onAddDocumentPressed, void Function(MediaItem)? onOpenDocument})` — the section renders the attachments grid + dive-photos group; add actions and document-opening are injected by the page (keeps this widget free of picker/viewer wiring, mirroring how `DiveMediaSection` takes `onAddPressed`).

- [ ] **Step 1: Write the failing test**

Create `test/features/media/presentation/widgets/site_media_section_test.dart` (harness from `dive_media_section_test.dart`, overriding `mediaForSiteProvider` / `mediaFromDivesAtSiteProvider` / `siteMediaListNotifierProvider` dependencies via a real container over the in-memory DB, or provider overrides — follow whichever style the dive test uses):

```dart
  testWidgets('empty state renders map icon and site empty message',
      (tester) async {
    // site with no media: expect l10n.media_siteMediaSection_emptyState text
  });

  testWidgets('add menu exposes photos and document actions', (tester) async {
    // pump with onAddPhotosPressed/onAddDocumentPressed spies; tap the add
    // icon; expect two menu entries; tap each; expect the spies fired.
  });

  testWidgets('dive photos group hidden when no dives have media',
      (tester) async {
    // mediaFromDivesAtSiteProvider -> {}: the ExpansionTile is absent.
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/media/presentation/widgets/site_media_section_test.dart`
Expected: FAIL — widget does not exist.

- [ ] **Step 3: Implement**

Create `site_media_section.dart`. Structure (follow `DiveMediaSection`'s state handling for selection mode; ~250 lines):

```dart
class SiteMediaSection extends ConsumerStatefulWidget {
  final String siteId;
  final VoidCallback? onAddPhotosPressed;
  final VoidCallback? onAddDocumentPressed;
  final void Function(MediaItem)? onOpenDocument;

  const SiteMediaSection({
    super.key,
    required this.siteId,
    this.onAddPhotosPressed,
    this.onAddDocumentPressed,
    this.onOpenDocument,
  });
  ...
}
```

Build, inside a `Card` (same padding/typography as `DiveMediaSection`):

1. Header row: `Icons.photo_library` icon, `context.l10n.media_siteMediaSection_title`, spacer, and a `PopupMenuButton<String>` with `Icons.add_photo_alternate` as its child exposing two items — `'photos'` (`l10n.media_siteMediaSection_addPhotos`) and `'document'` (`l10n.media_siteMediaSection_addDocument`) — dispatching to the two callbacks. In selection mode swap the header for `MediaSelectionHeader` wired to `siteMediaListNotifierProvider(widget.siteId).notifier.deleteMultipleMedia` with a confirm dialog (copy `_unlinkSelected` from `DiveMediaSection`, swapping the notifier and the l10n keys for the `media_siteMediaSection_*` variants).
2. Attachments grid: `ref.watch(mediaForSiteProvider(widget.siteId))` -> empty: `MediaEmptyState(icon: Icons.map_outlined, message: l10n.media_siteMediaSection_emptyState)`; non-empty: `DragSelectGridView<MediaItem>` exactly as `DiveMediaSection` builds it (4 columns, shrinkWrap, `MediaThumbnailTile` items), with `onItemTap`:

```dart
                  onItemTap: (index) {
                    final item = media[index];
                    if (item.isDocument) {
                      widget.onOpenDocument?.call(item);
                      return;
                    }
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        fullscreenDialog: true,
                        builder: (_) => SiteMediaViewerPage(
                          siteId: widget.siteId,
                          initialMediaId: item.id,
                          scope: SiteViewerScope.attachments,
                        ),
                      ),
                    );
                  },
```

3. Dive-photos group, collapsed by default so site reference material stays prominent (spec decision 2):

```dart
            final grouped =
                ref.watch(mediaFromDivesAtSiteProvider(widget.siteId));
            ...
            if (flat.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                initiallyExpanded: false,
                title: Text(
                  context.l10n.media_siteMediaSection_divePhotosGroup(
                    flat.length,
                  ),
                  style: textTheme.titleSmall,
                ),
                children: [
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                    itemCount: flat.length,
                    itemBuilder: (context, index) => GestureDetector(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          fullscreenDialog: true,
                          builder: (_) => SiteMediaViewerPage(
                            siteId: widget.siteId,
                            initialMediaId: flat[index].id,
                            scope: SiteViewerScope.divePhotos,
                          ),
                        ),
                      ),
                      child: MediaThumbnailTile(
                        item: flat[index],
                        settings: settings,
                        isSelectionMode: false,
                        isSelected: false,
                        semanticsLabel: context
                            .l10n.media_siteMediaSection_divePhotoLabel,
                      ),
                    ),
                  ),
                ],
              ),
```

where `flat` is the grouped map's values flattened in `takenAt` order (compute inline; the dive-photos group is read-only, no selection mode).

- [ ] **Step 4: Add the l10n keys (English only for now)**

Add to `lib/l10n/arb/app_en.arb` (full-locale sweep happens in Task 14):

```json
  "media_siteMediaSection_title": "Site Media",
  "media_siteMediaSection_addPhotos": "Add photos or videos",
  "media_siteMediaSection_addDocument": "Add document",
  "media_siteMediaSection_emptyState": "No maps, photos, or documents attached to this site",
  "media_siteMediaSection_divePhotosGroup": "Photos from dives here ({count})",
  "@media_siteMediaSection_divePhotosGroup": {
    "placeholders": { "count": { "type": "int" } }
  },
  "media_siteMediaSection_divePhotoLabel": "Dive photo",
  "media_siteMediaSection_unlinkSelectedTitle": "Remove {count} attachments?",
  "@media_siteMediaSection_unlinkSelectedTitle": {
    "placeholders": { "count": { "type": "int" } }
  },
  "media_siteMediaSection_unlinkSelectedContent": "The selected items will be removed from this site. Files in your photo library or on disk are not deleted.",
  "@media_siteMediaSection_unlinkSelectedContent": {
    "placeholders": { "count": { "type": "int" } }
  },
  "media_siteMediaSection_unlinkSelectedSuccess": "Removed {count} attachments",
  "@media_siteMediaSection_unlinkSelectedSuccess": {
    "placeholders": { "count": { "type": "int" } }
  }
```

Match the exact placeholder/metadata style of the neighboring `media_diveMediaSection_*` keys in `app_en.arb` (open them and copy the format — some use `num` with plurals; mirror whichever form the dive keys use). Run `flutter gen-l10n`. Other locales get a temporary English copy ONLY if `flutter analyze` requires all locales to define every key (it does — untranslated keys fail generation); in that case copy the English strings into the other 10 ARBs now and mark Task 14 as the translation pass.

- [ ] **Step 5: Run tests**

Run: `flutter test test/features/media/presentation/widgets/site_media_section_test.dart`
Expected: PASS.

- [ ] **Step 6: Format and commit**

```bash
dart format .
git add -A
git commit -m "Add SiteMediaSection with attachments grid and dive photos group"
```
