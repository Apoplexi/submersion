import 'package:shared_preferences/shared_preferences.dart';

import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/core/services/log_file_service.dart';
import 'package:submersion/features/settings/presentation/providers/debug_log_providers.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';

/// The provider overrides the app's root [ProviderScope] installs.
///
/// Shared with the post-restore safety sweep, which builds a second, throwaway
/// container against the freshly restored database. Both must install the same
/// overrides: [logFileServiceProvider] throws unless overridden, and a
/// container missing [sharedPreferencesProvider] cannot resolve settings. Keep
/// this the single definition so the two cannot drift apart.
///
/// Returns `List<dynamic>` because Riverpod 3 does not export its `Override`
/// type, so it cannot be named in a signature -- the same constraint that
/// makes `test/helpers/test_app.dart` take `List<dynamic>`. Call sites pass the
/// result to `overrides:` with `.cast()`, which infers the real element type
/// from context.
List<dynamic> rootProviderOverrides({
  required SharedPreferences prefs,
  required LogFileService logFileService,
}) {
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    logFileServiceProvider.overrideWithValue(logFileService),
  ];
}
