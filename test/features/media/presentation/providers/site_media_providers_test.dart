import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/database.dart';
import 'package:submersion/core/database/local_cache_database.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/media/data/repositories/media_repository.dart';
import 'package:submersion/features/media/data/services/document_import_service.dart';
import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media/presentation/providers/site_media_providers.dart';
import 'package:submersion/features/media_store/data/media_deletion_coordinator.dart';
import 'package:submersion/features/media_store/data/media_transfer_queue_repository.dart';
import 'package:submersion/features/media_store/presentation/providers/media_store_providers.dart';

import '../../../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late LocalCacheDatabase cacheDb;
  late MediaRepository repository;
  late ProviderContainer container;

  setUp(() async {
    db = await setUpTestDatabase();
    cacheDb = LocalCacheDatabase(NativeDatabase.memory());
    repository = MediaRepository();
    container = ProviderContainer(
      overrides: [
        mediaDeletionCoordinatorProvider.overrideWithValue(
          MediaDeletionCoordinator(
            mediaRepository: repository,
            queue: () => MediaTransferQueueRepository(database: cacheDb),
          ),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await cacheDb.close();
    await tearDownTestDatabase();
  });

  final epoch = DateTime(2026, 1, 1).millisecondsSinceEpoch;

  Future<void> insertDive(String id, {String? siteId}) => db
      .into(db.dives)
      .insert(
        DivesCompanion(
          id: Value(id),
          diveDateTime: Value(epoch),
          siteId: Value(siteId),
          createdAt: Value(epoch),
          updatedAt: Value(epoch),
        ),
      );

  Future<void> insertSite(String id) => db
      .into(db.diveSites)
      .insert(
        DiveSitesCompanion(
          id: Value(id),
          name: const Value('Reef'),
          createdAt: Value(epoch),
          updatedAt: Value(epoch),
        ),
      );

  MediaItem item(
    String name, {
    String? diveId,
    String? siteId,
    DateTime? takenAt,
  }) => MediaItem(
    id: '',
    mediaType: MediaType.photo,
    filePath: '/tmp/$name',
    originalFilename: name,
    diveId: diveId,
    siteId: siteId,
    takenAt: takenAt ?? DateTime(2026, 1, 1),
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  test('mediaForSiteProvider returns direct attachments with count', () async {
    await insertSite('site-1');
    await repository.createMedia(item('a.jpg', siteId: 'site-1'));

    final list = await container.read(mediaForSiteProvider('site-1').future);
    expect(list, hasLength(1));
    expect(await container.read(mediaCountForSiteProvider('site-1').future), 1);
    expect(await container.read(mediaCountForSiteProvider('site-2').future), 0);
  });

  test('notifier deleteMultipleMedia removes rows and refreshes', () async {
    await insertSite('site-1');
    final m1 = await repository.createMedia(item('a.jpg', siteId: 'site-1'));
    final m2 = await repository.createMedia(item('b.jpg', siteId: 'site-1'));

    final notifier = container.read(
      siteMediaListNotifierProvider('site-1').notifier,
    );
    await notifier.refresh();
    await notifier.deleteMultipleMedia([m1.id]);

    final state = container.read(siteMediaListNotifierProvider('site-1'));
    expect(state.value!.map((m) => m.id), [m2.id]);
  });

  test('notifier addMedia inserts a row and the state reflects it', () async {
    await insertSite('site-1');
    final notifier = container.read(
      siteMediaListNotifierProvider('site-1').notifier,
    );
    await notifier.refresh();
    expect(container.read(siteMediaListNotifierProvider('site-1')).value, []);

    final created = await notifier.addMedia(item('a.jpg', siteId: 'site-1'));

    expect(created.id, isNotEmpty);
    final state = container.read(siteMediaListNotifierProvider('site-1'));
    expect(state.value!.map((m) => m.id), [created.id]);
    // addMedia refreshes, so the read-side providers see it too.
    expect(await container.read(mediaCountForSiteProvider('site-1').future), 1);
  });

  test(
    'notifier updateMedia writes the change and the state reflects it',
    () async {
      await insertSite('site-1');
      final notifier = container.read(
        siteMediaListNotifierProvider('site-1').notifier,
      );
      final created = await notifier.addMedia(item('a.jpg', siteId: 'site-1'));

      await notifier.updateMedia(created.copyWith(caption: 'Wreck bow'));

      final state = container.read(siteMediaListNotifierProvider('site-1'));
      expect(state.value!.single.caption, 'Wreck bow');
      // Not just in memory: the row itself changed.
      final reread = await repository.getMediaForSite('site-1');
      expect(reread.single.caption, 'Wreck bow');
    },
  );

  test(
    'notifier state becomes an error when the repository load fails',
    () async {
      await insertSite('site-1');
      // A closed database makes every query throw, and MediaRepository rethrows;
      // the notifier's guarded load is what keeps that from escaping unhandled.
      // (tearDownTestDatabase closes it a second time, which drift tolerates.)
      await db.close();

      container.read(siteMediaListNotifierProvider('site-1').notifier);
      await pumpEventQueue();

      final state = container.read(siteMediaListNotifierProvider('site-1'));
      expect(state.hasError, isTrue);
      expect(state.hasValue, isFalse);
    },
  );

  test('mediaCountForSiteProvider counts every direct attachment', () async {
    await insertSite('site-1');
    await insertSite('site-2');
    await repository.createMedia(item('a.jpg', siteId: 'site-1'));
    await repository.createMedia(item('b.jpg', siteId: 'site-1'));
    await repository.createMedia(item('c.jpg', siteId: 'site-1'));
    await repository.createMedia(item('d.jpg', siteId: 'site-2'));

    expect(await container.read(mediaCountForSiteProvider('site-1').future), 3);
    expect(await container.read(mediaCountForSiteProvider('site-2').future), 1);
  });

  test(
    'flatMediaFromDivesAtSiteProvider orders by takenAt across dives',
    () async {
      await insertSite('site-1');
      await insertDive('dive-1', siteId: 'site-1');
      await insertDive('dive-2', siteId: 'site-1');
      // Deliberately out of order, and interleaved across the two dives, so
      // per-dive ordering alone cannot produce the expected sequence.
      await repository.createMedia(
        item('late.jpg', diveId: 'dive-1', takenAt: DateTime(2026, 3, 3)),
      );
      await repository.createMedia(
        item('early.jpg', diveId: 'dive-2', takenAt: DateTime(2026, 1, 1)),
      );
      await repository.createMedia(
        item('middle.jpg', diveId: 'dive-1', takenAt: DateTime(2026, 2, 2)),
      );

      final flat = await container.read(
        flatMediaFromDivesAtSiteProvider('site-1').future,
      );
      expect(flat.map((m) => m.originalFilename), [
        'early.jpg',
        'middle.jpg',
        'late.jpg',
      ]);
    },
  );

  test(
    'mediaFromDivesAtSiteProvider groups by dive and drops empty dives',
    () async {
      await insertSite('site-1');
      await insertDive('dive-1', siteId: 'site-1');
      await insertDive('dive-2', siteId: 'site-1');
      await repository.createMedia(item('a.jpg', diveId: 'dive-1'));

      final grouped = await container.read(
        mediaFromDivesAtSiteProvider('site-1').future,
      );
      expect(grouped.keys.map((d) => d.id), ['dive-1']);
      expect(grouped.values.single, hasLength(1));

      final flat = await container.read(
        flatMediaFromDivesAtSiteProvider('site-1').future,
      );
      expect(flat, hasLength(1));
    },
  );

  test('documentImportServiceProvider wires a usable import service', () {
    final service = container.read(documentImportServiceProvider);

    // The provider is the only place the document attach flow gets its
    // repository, bookmark storage and media-store enqueue hook, so a
    // construction failure here would only surface as a crash on tap.
    expect(service.mediaRepository, isNotNull);
    expect(service.bookmarkStorage, isNotNull);
    expect(service.onMediaCreated, isNotNull);
    expect(
      DocumentImportService.allowedExtensions,
      containsAll(<String>['pdf', 'doc', 'docx', 'txt', 'gpx']),
    );
    // Riverpod caches it, so repeat taps share one service.
    expect(container.read(documentImportServiceProvider), same(service));
  });
}
