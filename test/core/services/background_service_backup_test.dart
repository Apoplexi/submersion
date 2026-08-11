import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:submersion/core/data/repositories/sync_repository.dart';
import 'package:submersion/core/database/database.dart';
import 'package:submersion/core/services/background_service.dart';
import 'package:submersion/core/services/cloud_storage/cloud_storage_provider.dart';
import 'package:submersion/features/backup/data/repositories/backup_preferences.dart';
import 'package:submersion/features/backup/data/services/backup_service.dart';
import 'package:submersion/features/backup/domain/entities/backup_record.dart';

import '../../support/fake_cloud_storage_provider.dart';

/// Writes a stand-in backup file so the service has real bytes to upload.
class _FakeBackupDatabaseAdapter implements BackupDatabaseAdapter {
  @override
  Future<void> backup(String destinationPath) async {
    final file = File(destinationPath);
    await file.parent.create(recursive: true);
    await file.writeAsString('fake backup data');
  }

  @override
  Future<void> restore(
    String backupPath, {
    void Function(int, int)? onMigrationProgress,
  }) async {}

  @override
  Future<String> get databasePath async => '/fake/db/path';

  @override
  AppDatabase get database =>
      throw UnimplementedError('Fake database does not support queries');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            if (methodCall.method == 'getTemporaryDirectory' ||
                methodCall.method == 'getApplicationDocumentsDirectory') {
              return Directory.systemTemp.path;
            }
            return null;
          },
        );
  });

  late FakeCloudStorageProvider cloud;

  setUp(() {
    cloud = FakeCloudStorageProvider(providerId: 'dropbox');
  });

  Future<SharedPreferences> seedPrefs({
    required bool cloudBackupEnabled,
    String? lastProvider = 'dropbox',
  }) async {
    SharedPreferences.setMockInitialValues(
      lastProvider == null ? {} : {'sync_last_provider': lastProvider},
    );
    final prefs = await SharedPreferences.getInstance();
    await BackupPreferences(prefs).setCloudBackupEnabled(cloudBackupEnabled);
    return prefs;
  }

  // The support fake's createFolder returns the folder name as its id.
  Future<List<CloudFileInfo>> uploadedBackups() => cloud.listFiles(
    folderId: 'Submersion Backups',
    namePattern: 'submersion_backup_',
  );

  Future<BackupRecord> runScheduledBackup(SharedPreferences prefs) async {
    final service = await buildScheduledBackupService(
      prefs: prefs,
      dbAdapter: _FakeBackupDatabaseAdapter(),
      instanceFor: (CloudProviderType type) => cloud,
    );
    return service.performBackup(isAutomatic: true);
  }

  test('the scheduled (headless) backup uploads to the cloud when the user '
      'turned cloud backup on', () async {
    final prefs = await seedPrefs(cloudBackupEnabled: true);

    final record = await runScheduledBackup(prefs);

    expect(
      await uploadedBackups(),
      hasLength(1),
      reason:
          'issue #969: the background isolate built a BackupService with no '
          'cloud provider, so automatic backups never left the device',
    );
    expect(record.location, BackupLocation.both);
    expect(record.cloudFileId, isNotNull);
    expect(record.isAutomatic, isTrue);
  });

  test('stays local when the user has not enabled cloud backup', () async {
    final prefs = await seedPrefs(cloudBackupEnabled: false);

    final record = await runScheduledBackup(prefs);

    expect(await uploadedBackups(), isEmpty);
    expect(record.location, BackupLocation.local);
  });

  test('stays local when no cloud provider is connected', () async {
    final prefs = await seedPrefs(cloudBackupEnabled: true, lastProvider: null);

    final record = await runScheduledBackup(prefs);

    expect(await uploadedBackups(), isEmpty);
    expect(record.location, BackupLocation.local);
  });
}
