import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/database.dart';
import 'package:submersion/core/database/local_cache_database.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/media/data/repositories/media_repository.dart';
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

  MediaItem item(String name, {String? diveId, String? siteId}) => MediaItem(
    id: '',
    mediaType: MediaType.photo,
    filePath: '/tmp/$name',
    originalFilename: name,
    diveId: diveId,
    siteId: siteId,
    takenAt: DateTime(2026, 1, 1),
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
}
