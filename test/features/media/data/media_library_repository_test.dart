import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/database.dart';
import 'package:submersion/features/media/data/repositories/media_library_repository.dart';
import 'package:submersion/features/media/data/repositories/media_repository.dart';
import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media/domain/entities/media_library_filter.dart';
import 'package:submersion/features/media/domain/entities/media_source_type.dart';

import '../../../helpers/test_database.dart';

void main() {
  late AppDatabase db;
  late MediaRepository mediaRepo;
  late MediaLibraryRepository repo;

  final epoch = DateTime(2026, 1, 1).millisecondsSinceEpoch;

  Future<void> insertDiver(String id) => db
      .into(db.divers)
      .insert(
        DiversCompanion(
          id: Value(id),
          name: Value(id),
          createdAt: Value(epoch),
          updatedAt: Value(epoch),
        ),
      );

  Future<void> insertSite(String id, String name) => db
      .into(db.diveSites)
      .insert(
        DiveSitesCompanion(
          id: Value(id),
          name: Value(name),
          createdAt: Value(epoch),
          updatedAt: Value(epoch),
        ),
      );

  Future<void> insertTrip(String id) => db
      .into(db.trips)
      .insert(
        TripsCompanion(
          id: Value(id),
          name: Value(id),
          startDate: Value(epoch),
          endDate: Value(epoch),
          createdAt: Value(epoch),
          updatedAt: Value(epoch),
        ),
      );

  Future<void> insertDive(
    String id, {
    required String diverId,
    int? number,
    String? siteId,
    String? tripId,
    DateTime? dateTime,
  }) => db
      .into(db.dives)
      .insert(
        DivesCompanion(
          id: Value(id),
          diverId: Value(diverId),
          diveNumber: Value(number),
          siteId: Value(siteId),
          tripId: Value(tripId),
          diveDateTime: Value(
            (dateTime ?? DateTime(2026, 1, 1)).millisecondsSinceEpoch,
          ),
          createdAt: Value(epoch),
          updatedAt: Value(epoch),
        ),
      );

  Future<void> insertMedia(
    String id,
    DateTime takenAt, {
    String? diveId,
    MediaType mediaType = MediaType.photo,
    MediaSourceType sourceType = MediaSourceType.localFile,
    bool isOrphaned = false,
  }) => mediaRepo.createMedia(
    MediaItem(
      id: id,
      mediaType: mediaType,
      sourceType: sourceType,
      filePath: '/tmp/$id',
      localPath: '/tmp/$id',
      originalFilename: '$id.jpg',
      diveId: diveId,
      takenAt: takenAt,
      isOrphaned: isOrphaned,
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
    ),
  );

  setUp(() async {
    db = await setUpTestDatabase();
    mediaRepo = MediaRepository();
    repo = MediaLibraryRepository();

    await insertDiver('d1');
    await insertDiver('d2');
    await insertSite('site-1', 'Blue Hole');
    await insertTrip('trip-1');
    await insertDive(
      'dive-1',
      diverId: 'd1',
      number: 1,
      siteId: 'site-1',
      tripId: 'trip-1',
      dateTime: DateTime(2026, 6, 12),
    );
    await insertDive(
      'dive-2',
      diverId: 'd1',
      number: 2,
      dateTime: DateTime(2026, 6, 11),
    );
    await insertDive('dive-other', diverId: 'd2');

    await insertMedia('p1', DateTime(2026, 6, 12, 10, 0), diveId: 'dive-1');
    await insertMedia('p2', DateTime(2026, 6, 12, 10, 5), diveId: 'dive-1');
    await insertMedia('p3', DateTime(2026, 6, 12, 10, 10), diveId: 'dive-1');
    await insertMedia(
      'v1',
      DateTime(2026, 6, 11, 9, 0),
      diveId: 'dive-2',
      mediaType: MediaType.video,
    );
    await insertMedia(
      'other-diver-photo',
      DateTime(2026, 7, 1),
      diveId: 'dive-other',
    );
    await insertMedia('unlinked-1', DateTime(2026, 5, 1));
    await insertMedia(
      'unlinked-url-1',
      DateTime(2026, 5, 2),
      sourceType: MediaSourceType.networkUrl,
    );
    await insertMedia(
      'orphaned-1',
      DateTime(2026, 6, 12, 9, 0),
      diveId: 'dive-1',
      isOrphaned: true,
    );
    await insertMedia(
      'sig-1',
      DateTime(2026, 6, 12, 11, 0),
      diveId: 'dive-1',
      mediaType: MediaType.instructorSignature,
      sourceType: MediaSourceType.signature,
    );
  });
  tearDown(tearDownTestDatabase);

  group('MediaLibraryRepository.getPage', () {
    test('excludes signatures and other divers, includes unlinked', () async {
      final page = await repo.getPage(diverId: 'd1');
      final ids = page.entries.map((e) => e.item.id).toList();
      expect(ids, isNot(contains('sig-1')));
      expect(ids, isNot(contains('other-diver-photo')));
      expect(ids, contains('unlinked-1'));
      expect(ids, contains('unlinked-url-1'));
      expect(ids, hasLength(7));
    });

    test(
      'orders by COALESCE(taken_at, created_at) DESC then id DESC',
      () async {
        final page = await repo.getPage(diverId: 'd1');
        final keys = page.entries
            .map((e) => e.item.takenAt.millisecondsSinceEpoch)
            .toList();
        final sorted = [...keys]..sort((a, b) => b.compareTo(a));
        expect(keys, sorted);
        expect(page.entries.first.item.id, 'p3');
      },
    );

    test(
      'keyset pagination walks the full set without gaps or repeats',
      () async {
        final first = await repo.getPage(diverId: 'd1', limit: 3);
        expect(first.entries, hasLength(3));
        expect(first.nextCursor, isNotNull);

        final second = await repo.getPage(
          diverId: 'd1',
          after: first.nextCursor,
          limit: 50,
        );
        expect(second.nextCursor, isNull);

        final all = {
          ...first.entries.map((e) => e.item.id),
          ...second.entries.map((e) => e.item.id),
        };
        expect(all, hasLength(7));
      },
    );

    test('mediaType, health, and dive filters compile correctly', () async {
      final videos = await repo.getPage(
        diverId: 'd1',
        filter: const MediaLibraryFilter(mediaType: MediaType.video),
      );
      expect(videos.entries.map((e) => e.item.id), ['v1']);

      final missing = await repo.getPage(
        diverId: 'd1',
        filter: const MediaLibraryFilter(health: MediaHealthFilter.missing),
      );
      expect(missing.entries.map((e) => e.item.id), ['orphaned-1']);

      final unlinked = await repo.getPage(
        diverId: 'd1',
        filter: const MediaLibraryFilter(health: MediaHealthFilter.unlinked),
      );
      expect(unlinked.entries.map((e) => e.item.id), ['unlinked-1']);

      final dive2 = await repo.getPage(
        diverId: 'd1',
        filter: const MediaLibraryFilter(diveId: 'dive-2'),
      );
      expect(dive2.entries.map((e) => e.item.id), ['v1']);
    });

    test('site, trip, and date range filters compile correctly', () async {
      final atSite = await repo.getPage(
        diverId: 'd1',
        filter: const MediaLibraryFilter(siteId: 'site-1'),
      );
      expect(atSite.entries.map((e) => e.item.id).toSet(), {
        'p1',
        'p2',
        'p3',
        'orphaned-1',
      });

      final onTrip = await repo.getPage(
        diverId: 'd1',
        filter: const MediaLibraryFilter(tripId: 'trip-1'),
      );
      expect(onTrip.entries.map((e) => e.item.id).toSet(), {
        'p1',
        'p2',
        'p3',
        'orphaned-1',
      });

      final inMay = await repo.getPage(
        diverId: 'd1',
        filter: MediaLibraryFilter(
          fromDate: DateTime(2026, 5, 1),
          toDate: DateTime(2026, 5, 31),
        ),
      );
      expect(inMay.entries.map((e) => e.item.id).toSet(), {
        'unlinked-1',
        'unlinked-url-1',
      });
    });

    test('joins dive header fields', () async {
      final page = await repo.getPage(diverId: 'd1');
      final onDive1 = page.entries.firstWhere((e) => e.item.id == 'p1');
      expect(onDive1.diveNumber, 1);
      expect(onDive1.siteName, 'Blue Hole');
      final unlinked = page.entries.firstWhere(
        (e) => e.item.id == 'unlinked-1',
      );
      expect(unlinked.diveNumber, isNull);
      expect(unlinked.siteName, isNull);
    });
  });

  group('counts', () {
    test(
      'countUnlinked excludes library-level sources and signatures',
      () async {
        expect(await repo.countUnlinked(), 1);
      },
    );

    test('countMissing counts is_orphaned rows', () async {
      expect(await repo.countMissing(), 1);
    });

    test('countBySourceType buckets every non-signature row', () async {
      final counts = await repo.countBySourceType();
      expect(counts[MediaSourceType.localFile], 7);
      expect(counts[MediaSourceType.networkUrl], 1);
      expect(counts.containsKey(MediaSourceType.signature), isFalse);
    });

    test('countBySourceType omits source types with no rows', () async {
      final counts = await repo.countBySourceType();
      expect(
        counts.keys,
        unorderedEquals(<MediaSourceType>[
          MediaSourceType.localFile,
          MediaSourceType.networkUrl,
        ]),
      );
    });
  });
}
