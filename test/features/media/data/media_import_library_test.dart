import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/database.dart';
import 'package:submersion/features/media/data/repositories/media_repository.dart';
import 'package:submersion/features/media/data/services/enrichment_service.dart';
import 'package:submersion/features/media/data/services/media_import_service.dart';
import 'package:submersion/features/media/data/services/photo_picker_service.dart';
import 'package:submersion/features/media/domain/entities/media_source_type.dart';

import '../../../helpers/test_database.dart';

AssetInfo assetInfo(String id, {String? filePath}) => AssetInfo(
  id: id,
  type: AssetType.image,
  createDateTime: DateTime(2026, 6, 12, 10),
  width: 100,
  height: 100,
  filename: '$id.jpg',
  filePath: filePath,
);

void main() {
  late AppDatabase db;
  late MediaRepository repo;
  late MediaImportService service;

  setUp(() async {
    db = await setUpTestDatabase();
    repo = MediaRepository();
    service = MediaImportService(
      mediaRepository: repo,
      enrichmentService: EnrichmentService(),
    );
    expect(db, isNotNull);
  });
  tearDown(tearDownTestDatabase);

  test(
    'library import creates unlinked retained rows without enrichment',
    () async {
      final result = await service.importPhotosToLibrary(
        selectedAssets: [assetInfo('a1', filePath: '/tmp/a.jpg')],
      );

      expect(result.imported, hasLength(1));
      final row = await repo.getMediaById(result.imported.single.id);
      expect(row!.diveId, isNull);
      expect(row.retainInLibrary, isTrue);
      expect(row.enrichment, isNull);
      expect(row.sourceType, MediaSourceType.localFile);
      expect(row.localPath, '/tmp/a.jpg');
    },
  );

  test(
    'library import dedupes desktop picks against every existing row',
    () async {
      await service.importPhotosToLibrary(
        selectedAssets: [assetInfo('a1', filePath: '/tmp/a.jpg')],
      );
      final second = await service.importPhotosToLibrary(
        selectedAssets: [assetInfo('a1', filePath: '/tmp/a.jpg')],
      );
      expect(second.imported, isEmpty);
      expect(second.skippedDuplicates, 1);
    },
  );

  test('gallery assets dedupe on platform asset id', () async {
    await service.importPhotosToLibrary(selectedAssets: [assetInfo('g1')]);
    final second = await service.importPhotosToLibrary(
      selectedAssets: [assetInfo('g1'), assetInfo('g2')],
    );
    expect(second.imported, hasLength(1));
    expect(second.skippedDuplicates, 1);
    expect(second.imported.single.platformAssetId, 'g2');
  });
}
