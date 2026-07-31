import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:submersion/core/domain/entities/storage_config.dart';
import 'package:submersion/core/services/database_location_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const bookmarkChannel = MethodChannel(
    'app.submersion/security_scoped_bookmark',
  );

  setUp(() {
    // resetToDefault releases any security-scoped bookmark via a platform
    // channel that has no host implementation in tests. The binary
    // messenger is process-global, so the handler is removed again after
    // each test rather than leaking into later ones.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bookmarkChannel, (call) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(bookmarkChannel, null),
    );
  });

  Future<DatabaseLocationService> serviceWithCustomFolder(String folder) async {
    SharedPreferences.setMockInitialValues({});
    final service = DatabaseLocationService(
      await SharedPreferences.getInstance(),
    );
    await service.saveStorageConfig(
      StorageConfig(
        mode: StorageLocationMode.customFolder,
        customFolderPath: folder,
      ),
    );
    return service;
  }

  group('validateCustomLocationAtStartup (#218)', () {
    test('accessible custom database is kept on every platform', () async {
      final dir = await Directory.systemTemp.createTemp('submersion218');
      addTearDown(() => dir.delete(recursive: true));
      await File(
        p.join(dir.path, 'submersion.db'),
      ).writeAsBytes(List.filled(32, 1));

      final service = await serviceWithCustomFolder(dir.path);
      final check = await service.validateCustomLocationAtStartup(
        isBookmarkPlatform: false,
      );

      expect(check, StartupLocationCheck.accessible);
      expect(
        (await service.getStorageConfig()).mode,
        StorageLocationMode.customFolder,
      );
    });

    /// Makes the database path exist but be impossible to open for
    /// reading, which is the real "sandbox revoked access" shape. A merely
    /// absent file is a different case (first launch) and must not reset.
    Future<Directory> folderWithUnreadableDatabase() async {
      final dir = await Directory.systemTemp.createTemp('submersion218');
      addTearDown(() => dir.delete(recursive: true));
      await Directory(p.join(dir.path, 'submersion.db')).create();
      return dir;
    }

    test(
      'a missing database keeps the config on a non-bookmark platform',
      () async {
        final dir = await Directory.systemTemp.createTemp('submersion218');
        addTearDown(() => dir.delete(recursive: true));

        final service = await serviceWithCustomFolder(dir.path);
        final check = await service.validateCustomLocationAtStartup(
          isBookmarkPlatform: false,
        );

        expect(check, StartupLocationCheck.keptDatabaseMissing);
        expect(
          (await service.getStorageConfig()).mode,
          StorageLocationMode.customFolder,
        );
      },
    );

    test(
      'a missing database keeps the config on a bookmark platform too: it is '
      'the first launch after choosing a folder, not lost access',
      () async {
        final dir = await Directory.systemTemp.createTemp('submersion218');
        addTearDown(() => dir.delete(recursive: true));

        final service = await serviceWithCustomFolder(dir.path);
        final check = await service.validateCustomLocationAtStartup(
          isBookmarkPlatform: true,
        );

        expect(check, StartupLocationCheck.keptDatabaseMissing);
        expect(
          (await service.getStorageConfig()).mode,
          StorageLocationMode.customFolder,
          reason: 'a freshly chosen folder must survive its first launch',
        );
      },
    );

    test(
      'an unreadable database on a non-bookmark platform KEEPS the config',
      () async {
        final dir = await folderWithUnreadableDatabase();

        final service = await serviceWithCustomFolder(dir.path);
        final check = await service.validateCustomLocationAtStartup(
          isBookmarkPlatform: false,
        );

        expect(
          check,
          StartupLocationCheck.keptInaccessible,
          reason:
              'without a sandbox there is nothing to recover from; wiping '
              'the user choice made the setting appear to never persist',
        );
        expect(
          (await service.getStorageConfig()).mode,
          StorageLocationMode.customFolder,
        );
      },
    );

    test(
      'an unreadable database on a bookmark platform resets to default',
      () async {
        final dir = await folderWithUnreadableDatabase();

        final service = await serviceWithCustomFolder(dir.path);
        final check = await service.validateCustomLocationAtStartup(
          isBookmarkPlatform: true,
        );

        expect(check, StartupLocationCheck.resetToDefault);
        expect(
          (await service.getStorageConfig()).mode,
          StorageLocationMode.appDefault,
        );
      },
    );

    test('default location short-circuits', () async {
      SharedPreferences.setMockInitialValues({});
      final service = DatabaseLocationService(
        await SharedPreferences.getInstance(),
      );

      expect(
        await service.validateCustomLocationAtStartup(
          isBookmarkPlatform: false,
        ),
        StartupLocationCheck.defaultLocation,
      );
    });
  });
}
