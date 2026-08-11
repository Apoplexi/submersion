import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'package:submersion/core/data/repositories/sync_repository.dart'
    show CloudProviderType;
import 'package:submersion/core/database/sqlcipher_setup.dart';
import 'package:submersion/core/services/cloud_storage/cloud_storage_provider.dart';
import 'package:submersion/core/services/cloud_storage/headless_cloud_provider.dart';
import 'package:submersion/core/services/database_service.dart';
import 'package:submersion/core/services/logger_service.dart';
import 'package:submersion/core/services/security/database_security_service.dart';
import 'package:submersion/core/services/notification_service.dart';
import 'package:submersion/core/services/sync/crypto/encryption_key_store.dart';
import 'package:submersion/core/services/sync/sync_preferences.dart';
import 'package:submersion/features/backup/data/repositories/backup_preferences.dart';
import 'package:submersion/features/backup/data/services/backup_encryption_key_store.dart';
import 'package:submersion/features/backup/data/services/backup_service.dart';
import 'package:submersion/features/backup/domain/entities/backup_record.dart';
import 'package:submersion/features/equipment/data/repositories/equipment_repository_impl.dart';
import 'package:submersion/features/notifications/data/repositories/scheduled_notification_repository.dart';
import 'package:submersion/features/notifications/data/services/notification_scheduler.dart';
import 'package:submersion/features/settings/data/repositories/diver_settings_repository.dart';

const String kNotificationRefreshTask = 'com.submersion.notificationRefresh';
const String kBackupTask = 'com.submersion.backup';

/// Headless isolates have no unlock UI. Load the cached key (keychain) and
/// hand it to DatabaseService; when the database is encrypted and no cached
/// key exists (fresh device, keychain wipe), the task must SKIP — never
/// prompt, never open, never corrupt.
Future<bool> prepareHeadlessDatabaseKey({
  required SharedPreferences prefs,
}) async {
  // Fresh isolate: re-apply the per-isolate sqlite3 loader override.
  setupSqlcipher();
  final security = DatabaseSecurityService.instance;
  await security.configure(prefs: prefs);
  if (!security.encryptionEnabled) return true;
  final loaded = await security.tryLoadCachedKey();
  if (!loaded || security.databaseKeyHex == null) return false;
  DatabaseService.instance.databaseKeyHex = security.databaseKeyHex;
  return true;
}

/// Callback for Workmanager background tasks
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    const log = LoggerService('BackgroundService');
    log.info('Background task started: $task');

    try {
      final prefs = await SharedPreferences.getInstance();
      final ready = await prepareHeadlessDatabaseKey(prefs: prefs);
      if (!ready) {
        log.info(
          'Background task skipped: database is encrypted and no cached '
          'key is available in this headless context.',
        );
        return true; // "succeeded" — do not retry-loop a locked database
      }

      // Initialize database
      await DatabaseService.instance.initialize();

      // Initialize notification service
      await NotificationService.instance.initialize();

      if (task == kNotificationRefreshTask) {
        await _refreshNotifications(log);
      } else if (task == kBackupTask) {
        await _performScheduledBackup(log);
      }

      log.info('Background task completed: $task');
      return true;
    } catch (e, stackTrace) {
      log.error(
        'Background task failed: $task',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  });
}

Future<void> _refreshNotifications(LoggerService log) async {
  log.info('Refreshing notification schedule');

  final settingsRepository = DiverSettingsRepository();
  final equipmentRepository = EquipmentRepository();
  final scheduledNotificationRepository = ScheduledNotificationRepository();

  // Get the default diver's settings
  // In background, we use the most recently active diver
  final settings = await settingsRepository.getSettingsForDiver('default');
  if (settings == null || !settings.notificationsEnabled) {
    log.info('Notifications disabled, skipping refresh');
    return;
  }

  final scheduler = NotificationScheduler(
    notificationService: NotificationService.instance,
    equipmentRepository: equipmentRepository,
    scheduledNotificationRepository: scheduledNotificationRepository,
  );

  await scheduler.scheduleAll(settings: settings);
}

/// The [BackupService] the scheduled backup runs on.
///
/// Every store this reaches for is isolate-safe: SharedPreferences and secure
/// storage (credentials, both encryption keys). That is what lets a scheduled
/// backup honour the user's "Cloud Backup" switch -- for a long time this
/// isolate built a cloud-less service, so automatic backups silently stayed on
/// the device while the UI advertised cloud uploads (issue #969).
///
/// The two key stores are separately load-bearing:
///   * backup encryption -- when the flag is on, the artifact MUST be written
///     as an encrypted `.sbe`, otherwise `_activeBackupKey` fails closed and
///     the whole scheduled backup throws.
///   * sync encryption -- the cloud copy of an otherwise-plaintext backup is
///     framed before upload, exactly as the foreground path frames it, so
///     restore sees one artifact format regardless of who wrote it.
///
/// [instanceFor] is a test seam for the cloud-provider singletons.
@visibleForTesting
Future<BackupService> buildScheduledBackupService({
  required SharedPreferences prefs,
  required BackupDatabaseAdapter dbAdapter,
  CloudStorageProvider Function(CloudProviderType type)? instanceFor,
}) async {
  return BackupService(
    dbAdapter: dbAdapter,
    preferences: BackupPreferences(prefs),
    cloudProvider: await resolveHeadlessCloudProvider(
      prefs: prefs,
      instanceFor: instanceFor,
    ),
    encryptionKeyStore: EncryptionKeyStore(),
    syncPreferences: SyncPreferences(prefs),
    backupEncryptionKeyStore: BackupEncryptionKeyStore(),
  );
}

Future<void> _performScheduledBackup(LoggerService log) async {
  log.info('Checking if scheduled backup is due');

  final prefs = await SharedPreferences.getInstance();
  final preferences = BackupPreferences(prefs);
  final settings = preferences.getSettings();

  if (!settings.enabled) {
    log.info('Automatic backups disabled, skipping');
    return;
  }

  if (!settings.isBackupDue) {
    log.info('Backup not yet due, skipping');
    return;
  }

  log.info('Backup is due, starting automatic backup');

  final service = await buildScheduledBackupService(
    prefs: prefs,
    dbAdapter: DefaultBackupDatabaseAdapter(DatabaseService.instance),
  );

  try {
    final record = await service.performBackup(isAutomatic: true);
    // The record's location is the only honest signal: the upload swallows
    // its own failures to protect the local artifact, so a cloud copy the
    // user asked for can be missing from an otherwise successful backup.
    final cloudCopyMissing =
        settings.cloudBackupEnabled && record.location == BackupLocation.local;
    log.info(
      'Automatic backup completed: ${record.filename} '
      '(location: ${record.location.name})',
    );
    await NotificationService.instance.showBackupNotification(
      success: true,
      cloudCopyMissing: cloudCopyMissing,
    );
  } catch (e, stack) {
    log.error('Automatic backup failed', error: e, stackTrace: stack);
    await NotificationService.instance.showBackupNotification(
      success: false,
      error: e.toString(),
    );
  }
}

/// Initialize background task registration
Future<void> initializeBackgroundService() async {
  // Background service is mobile-only (iOS/Android)
  if (!Platform.isIOS && !Platform.isAndroid) {
    return;
  }

  await Workmanager().initialize(callbackDispatcher);

  // Register periodic task for notification refresh
  await Workmanager().registerPeriodicTask(
    'notification-refresh',
    kNotificationRefreshTask,
    frequency: const Duration(hours: 6), // Refresh every 6 hours
    constraints: Constraints(
      networkType: NetworkType.notRequired,
      requiresBatteryNotLow: false,
      requiresCharging: false,
      requiresDeviceIdle: false,
      requiresStorageNotLow: false,
    ),
  );

  // Register periodic task for automatic backups
  // Checks every 12 hours; actual frequency managed by BackupSettings.isBackupDue
  await Workmanager().registerPeriodicTask(
    'backup-task',
    kBackupTask,
    frequency: const Duration(hours: 12),
    constraints: Constraints(
      networkType: NetworkType.notRequired,
      requiresBatteryNotLow: true,
      requiresCharging: false,
      requiresDeviceIdle: false,
      requiresStorageNotLow: true,
    ),
  );
}
