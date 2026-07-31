import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:submersion/core/domain/entities/storage_config.dart';
import 'package:submersion/core/services/database_location_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // resetToDefault releases any security-scoped bookmark via a platform
    // channel that has no host implementation in tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('app.submersion/security_scoped_bookmark'),
          (call) async => null,
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

    test(
      'inaccessible database on a non-bookmark platform KEEPS the config',
      () async {
        final dir = await Directory.systemTemp.createTemp('submersion218');
        addTearDown(() => dir.delete(recursive: true));
        // No database file: first launch after choosing a fresh folder.

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
      'inaccessible database on a bookmark platform resets to default',
      () async {
        final dir = await Directory.systemTemp.createTemp('submersion218');
        addTearDown(() => dir.delete(recursive: true));

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
