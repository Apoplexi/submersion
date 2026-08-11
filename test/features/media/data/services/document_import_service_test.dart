import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:submersion/features/media/data/services/document_import_service.dart';
import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media/domain/entities/media_source_type.dart';

import '../../presentation/providers/files_tab_providers_test.mocks.dart';

void main() {
  late MockMediaRepository mockRepository;
  late MockLocalMediaPlatform mockPlatform;
  late MockLocalBookmarkStorage mockStorage;
  late List<String> createdIds;
  late DocumentImportService service;

  setUp(() {
    mockRepository = MockMediaRepository();
    mockPlatform = MockLocalMediaPlatform();
    mockStorage = MockLocalBookmarkStorage();
    createdIds = [];
    service = DocumentImportService(
      mediaRepository: mockRepository,
      platform: mockPlatform,
      bookmarkStorage: mockStorage,
      onMediaCreated: createdIds.add,
    );
    when(
      mockPlatform.createBookmark(any),
    ).thenAnswer((_) async => Uint8List.fromList([1, 2, 3]));
    when(mockStorage.write(any, any)).thenAnswer((_) async {});
    var counter = 0;
    when(mockRepository.createMedia(any)).thenAnswer((invocation) async {
      final item = invocation.positionalArguments.first as MediaItem;
      return item.copyWith(id: 'doc-${counter++}');
    });
  });

  test('imports a pdf as a document media row linked to the site', () async {
    final created = await service.importDocuments(
      picked: [(path: '/tmp/reef-map.pdf', filename: 'reef-map.pdf')],
      siteId: 'site-1',
    );

    expect(created, hasLength(1));
    final item = created.single;
    expect(item.mediaType, MediaType.document);
    expect(item.siteId, 'site-1');
    expect(item.diveId, isNull);
    expect(item.sourceType, MediaSourceType.localFile);
    expect(item.originalFilename, 'reef-map.pdf');
    expect(item.isPdf, isTrue);
  });

  test('links to a dive when diveId is given', () async {
    final created = await service.importDocuments(
      picked: [(path: '/tmp/waiver.pdf', filename: 'waiver.pdf')],
      diveId: 'dive-1',
    );

    expect(created.single.diveId, 'dive-1');
    expect(created.single.siteId, isNull);
  });

  test('fires onMediaCreated per row for media-store enqueue', () async {
    await service.importDocuments(
      picked: [
        (path: '/tmp/a.pdf', filename: 'a.pdf'),
        (path: '/tmp/b.txt', filename: 'b.txt'),
      ],
      siteId: 'site-1',
    );

    expect(createdIds, ['doc-0', 'doc-1']);
  });

  test('on this host the platform reference matches the OS branch', () async {
    // The suite runs on macOS (bookmark) or Linux CI (plain path); both
    // must produce a resolvable reference.
    final created = await service.importDocuments(
      picked: [(path: '/tmp/map.pdf', filename: 'map.pdf')],
      siteId: 'site-1',
    );
    final item = created.single;
    expect(
      (item.bookmarkRef != null) || (item.localPath != null),
      isTrue,
      reason: 'a document row must carry a bookmark or a path',
    );
  });
}
