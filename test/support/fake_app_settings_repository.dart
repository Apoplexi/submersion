import 'package:submersion/features/settings/data/repositories/app_settings_repository.dart';

/// In-memory stand-in for [AppSettingsRepository] so tests can exercise
/// settings-backed policies without a database.
///
/// Dart's implicit interfaces let us `implements` the concrete repository, so
/// no production-side abstraction is needed.
class FakeAppSettingsRepository implements AppSettingsRepository {
  final Map<String, String> values = {};

  /// When set, [getRawSetting] throws it.
  Object? throwOnRead;

  /// When set, [setRawSetting] throws it.
  Object? throwOnWrite;

  @override
  Future<String?> getRawSetting(String key) async {
    if (throwOnRead != null) throw throwOnRead!;
    return values[key];
  }

  @override
  Future<void> setRawSetting(String key, String value) async {
    if (throwOnWrite != null) throw throwOnWrite!;
    values[key] = value;
  }

  // Members these tests do not use -- stub to satisfy the interface.
  @override
  Future<bool> getShareByDefault() async =>
      throw UnimplementedError('not used by these tests');

  @override
  Future<void> setShareByDefault(bool value) async =>
      throw UnimplementedError('not used by these tests');

  @override
  Future<List<String>?> getNavPrimaryIdsRaw() async =>
      throw UnimplementedError('not used by these tests');

  @override
  Future<void> setNavPrimaryIds(List<String> ids) async =>
      throw UnimplementedError('not used by these tests');
}
