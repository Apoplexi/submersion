import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/database.dart';
import 'package:submersion/features/media/data/repositories/media_repository.dart';
import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media/domain/entities/media_source_type.dart';

import '../../../helpers/test_database.dart';

void main() {
  // ignore: unused_local_variable
  late AppDatabase db;
  late MediaRepository repo;

  setUp(() async {
    db = await setUpTestDatabase();
    repo = MediaRepository();
  });
  tearDown(tearDownTestDatabase);

  MediaItem item(
    String name,
    DateTime takenAt, {
    MediaType mediaType = MediaType.photo,
  }) => MediaItem(
    id: '',
    mediaType: mediaType,
    sourceType: MediaSourceType.platformGallery,
    filePath: '/tmp/$name',
    localPath: '/tmp/$name',
    originalFilename: name,
    takenAt: takenAt,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  test('returns newest photos first, capped at limit, photos only', () async {
    await repo.createMedia(item('jan.jpg', DateTime(2026, 1, 1)));
    await repo.createMedia(item('mar.jpg', DateTime(2026, 3, 1)));
    await repo.createMedia(item('feb.jpg', DateTime(2026, 2, 1)));
    await repo.createMedia(
      item('apr.mov', DateTime(2026, 4, 1), mediaType: MediaType.video),
    );

    final result = await repo.getRecentPhotos(limit: 2);
    expect(result, hasLength(2));
    // takenAt hydrates as UTC; compare instants, not DateTime objects.
    expect(result[0].takenAt.toLocal(), DateTime(2026, 3, 1));
    expect(result[1].takenAt.toLocal(), DateTime(2026, 2, 1));
    expect(result.every((m) => m.mediaType == MediaType.photo), isTrue);
  });

  test('empty table returns empty list', () async {
    expect(await repo.getRecentPhotos(), isEmpty);
  });
}
