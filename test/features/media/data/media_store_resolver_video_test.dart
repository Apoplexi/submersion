import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:submersion/core/database/local_cache_database.dart';
import 'package:submersion/core/services/media_store/store_keys.dart';
import 'package:submersion/features/media/data/resolvers/media_store_resolver.dart';
import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media/domain/entities/media_source_type.dart';
import 'package:submersion/features/media/domain/value_objects/media_source_data.dart';
import 'package:submersion/features/media_store/data/media_cache_store.dart';

import '../../../helpers/in_memory_media_object_store.dart';

/// Video-specific behaviour of the store fallback: the path a synced device
/// takes for a file that was linked on another machine.
void main() {
  late LocalCacheDatabase db;
  late Directory root;
  late InMemoryMediaObjectStore store;
  late MediaCacheStore cache;
  late MediaStoreResolver resolver;

  setUp(() async {
    db = LocalCacheDatabase(NativeDatabase.memory());
    root = await Directory.systemTemp.createTemp('msr_video_test');
    store = InMemoryMediaObjectStore();
    cache = MediaCacheStore(database: db, root: root);
    resolver = MediaStoreResolver(store: store, cache: cache);
  });

  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  MediaItem video({
    required String hash,
    String filename = 'DIVE_001.mp4',
    DateTime? uploadedAt,
    DateTime? thumbUploadedAt,
    DateTime? compressedUploadedAt,
  }) => MediaItem(
    id: 'v1',
    mediaType: MediaType.video,
    sourceType: MediaSourceType.localFile,
    localPath: '/Users/somebody/Movies/$filename',
    originalFilename: filename,
    takenAt: DateTime(2026),
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    contentHash: hash,
    remoteUploadedAt: uploadedAt,
    remoteThumbUploadedAt: thumbUploadedAt,
    remoteCompressedUploadedAt: compressedUploadedAt,
  );

  Future<String> seed(String name, List<int> bytes) async {
    final tmp = File('${root.path}/$name');
    await tmp.writeAsBytes(bytes, flush: true);
    return (await sha256OfFile(tmp)).hash;
  }

  // AVFoundation infers a container format from the URL's path extension:
  // video_player_avfoundation builds a bare `AVURLAsset` with no
  // out-of-band MIME hint, so the same bytes at an extensionless path fail
  // with AVFoundationErrorDomain -11828 "Cannot Open". The cache is
  // content-addressed, so the extension has to be carried in deliberately.
  test('a fetched video original keeps its container extension', () async {
    final bytes = 'fake-mp4-bytes'.codeUnits;
    final hash = await seed('clip', bytes);
    store.objects[StoreKeys.objectKey(hash, extension: 'mp4')] = bytes;

    final data = await resolver.tryResolveRemote(
      video(hash: hash, uploadedAt: DateTime(2026)),
      thumbnail: false,
    );

    expect(data, isA<FileData>());
    expect(p.extension((data! as FileData).file.path), '.mp4');
    // Still a cache hit on the second pass: the indexed path and the path
    // written must agree.
    store.objects.clear();
    final again = await resolver.tryResolveRemote(
      video(hash: hash, uploadedAt: DateTime(2026)),
      thumbnail: false,
    );
    expect(again, isA<FileData>());
    expect(p.extension((again! as FileData).file.path), '.mp4');
  });

  test('a fetched compressed video rendition keeps its .mp4 '
      'extension', () async {
    final bytes = 'transcoded-mp4'.codeUnits;
    final hash = 'd4${'6' * 62}';
    store.objects[StoreKeys.renditionKey(hash, ext: 'mp4')] = bytes;

    final data = await resolver.tryResolveRemote(
      video(hash: hash, compressedUploadedAt: DateTime(2026, 7, 2)),
      thumbnail: false,
    );

    expect(data, isA<FileData>());
    expect(p.extension((data! as FileData).file.path), '.mp4');
  });

  test('a fetched photo original keeps its extension too', () async {
    final bytes = 'jpeg-ish'.codeUnits;
    final hash = await seed('reef', bytes);
    store.objects[StoreKeys.objectKey(hash, extension: 'jpg')] = bytes;

    final data = await resolver.tryResolveRemote(
      MediaItem(
        id: 'p1',
        mediaType: MediaType.photo,
        sourceType: MediaSourceType.localFile,
        originalFilename: 'reef.jpg',
        takenAt: DateTime(2026),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        contentHash: hash,
        remoteUploadedAt: DateTime(2026),
      ),
      thumbnail: false,
    );

    expect(data, isA<FileData>());
    expect(p.extension((data! as FileData).file.path), '.jpg');
  });

  // The uploading device derives a poster frame from the video and stores it
  // as a JPEG under the thumb key. It is an image, not video bytes, so the
  // view must be told it is safe to decode.
  test('a video poster from the store is flagged as a poster', () async {
    final poster = 'jpeg-poster-bytes'.codeUnits;
    final hash = 'e5${'5' * 62}';
    store.objects[StoreKeys.thumbKey(hash)] = poster;

    final data = await resolver.tryResolveRemote(
      video(hash: hash, thumbUploadedAt: DateTime(2026)),
      thumbnail: true,
    );

    expect(data, isA<FileData>());
    final poster0 = data! as FileData;
    expect(poster0.isPoster, isTrue);
    expect(p.extension(poster0.file.path), '.jpg');
  });

  test('a photo fetched for a thumbnail is not flagged as a poster', () async {
    final bytes = 'thumb-bytes'.codeUnits;
    final hash = 'f6${'4' * 62}';
    store.objects[StoreKeys.thumbKey(hash)] = bytes;

    final data = await resolver.tryResolveRemote(
      MediaItem(
        id: 'p2',
        mediaType: MediaType.photo,
        sourceType: MediaSourceType.localFile,
        originalFilename: 'reef.jpg',
        takenAt: DateTime(2026),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        contentHash: hash,
        remoteThumbUploadedAt: DateTime(2026),
      ),
      thumbnail: true,
    );

    expect(data, isA<FileData>());
    expect((data! as FileData).isPoster, isFalse);
  });

  // A video original can only ever render as the movie placeholder, so
  // reaching for it to satisfy a grid tile downloads megabytes (potentially
  // over cellular) to draw an icon.
  test('a video thumbnail request never downloads the original', () async {
    final bytes = 'a-very-large-video'.codeUnits;
    final hash = await seed('big', bytes);
    store.objects[StoreKeys.objectKey(hash, extension: 'mp4')] = bytes;
    store.objects[StoreKeys.renditionKey(hash, ext: 'mp4')] = bytes;

    final data = await resolver.tryResolveRemote(
      video(
        hash: hash,
        uploadedAt: DateTime(2026),
        compressedUploadedAt: DateTime(2026),
      ),
      thumbnail: true, // no thumb stamp: no poster was ever uploaded
    );

    expect(data, isNull);
    expect(store.getFileKeys, isEmpty);
  });

  test('a photo thumbnail request still falls back to the original', () async {
    final bytes = 'photo-bytes'.codeUnits;
    final hash = await seed('photo', bytes);
    store.objects[StoreKeys.objectKey(hash, extension: 'jpg')] = bytes;

    final data = await resolver.tryResolveRemote(
      MediaItem(
        id: 'p3',
        mediaType: MediaType.photo,
        sourceType: MediaSourceType.localFile,
        originalFilename: 'reef.jpg',
        takenAt: DateTime(2026),
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        contentHash: hash,
        remoteUploadedAt: DateTime(2026),
      ),
      thumbnail: true,
    );

    expect(data, isA<FileData>());
  });

  // Falling back to the full video is still correct when the caller wants
  // playable bytes rather than something to draw in a grid.
  test('a full-size video request still fetches the original', () async {
    final bytes = 'playable-mp4'.codeUnits;
    final hash = await seed('play', bytes);
    store.objects[StoreKeys.objectKey(hash, extension: 'mp4')] = bytes;

    final data = await resolver.tryResolveRemote(
      video(hash: hash, uploadedAt: DateTime(2026)),
      thumbnail: false,
    );

    expect(data, isA<FileData>());
    expect(await (data! as FileData).file.readAsBytes(), bytes);
  });
}
