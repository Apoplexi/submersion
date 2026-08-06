import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'package:submersion/core/database/sqlcipher_setup.dart';
import 'package:submersion/core/services/database_service.dart';
import 'package:submersion/core/services/logger_service.dart';
import 'package:submersion/core/services/security/database_security_service.dart';
import 'package:submersion/core/services/notification_service.dart';
import 'package:submersion/features/backup/data/repositories/backup_preferences.dart';
import 'package:submersion/features/backup/data/services/backup_encryption_key_store.dart';
import 'package:submersion/features/backup/data/services/backup_service.dart';
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

  // Background isolate cannot access cloud auth, so backup is local-only.
  // The backup-encryption key store IS injected: when the user has enabled
  // backup encryption, the scheduled backup must still be written as an
  // encrypted .sbe (otherwise _activeBackupKey fails closed and the whole
  // scheduled backup fails). Secure storage is reachable from this isolate.
  final dbAdapter = DefaultBackupDatabaseAdapter(DatabaseService.instance);
  final service = BackupService(
    dbAdapter: dbAdapter,
    preferences: preferences,
    backupEncryptionKeyStore: BackupEncryptionKeyStore(),
  );

  try {
    final record = await service.performBackup(isAutomatic: true);
    log.info('Automatic backup completed: ${record.filename}');
    await NotificationService.instance.showBackupNotification(success: true);
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
