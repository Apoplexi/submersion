import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/core/providers/root_overrides.dart';
import 'package:submersion/features/dive_log/presentation/providers/safety_review_sweep.dart';
import 'package:submersion/features/settings/presentation/providers/debug_log_providers.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';

/// Runs the whole-library safety sweep that follows a database restore.
///
/// The sweep deliberately runs in its own short-lived [ProviderContainer]
/// rather than the live one. After a restore the live container still holds
/// values built against the REPLACED database -- settingsProvider (and so the
/// gradient factors that shape the ceiling curve the missedDecoStop and
/// highSurfaceGf rules grade against), ProfileLegend's metric-source defaults,
/// and cached analysisDiveProvider/profileAnalysisProvider entries. Computing
/// findings from that state would persist the old device's settings into the
/// restored library, and because saveReview stamps the current engineVersion
/// they would never be recomputed.
///
/// A fresh container builds every provider against the restored database. The
/// live container is left untouched; restartApp() rebuilds the root
/// ProviderScope under a new key moments later and discards it anyway.
class PostRestoreSafetyReview {
  final Ref _ref;

  const PostRestoreSafetyReview(this._ref);

  Future<SafetyReviewSweepResult> run({
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final container = ProviderContainer(
      overrides: rootProviderOverrides(
        prefs: _ref.read(sharedPreferencesProvider),
        logFileService: _ref.read(logFileServiceProvider),
      ).cast(),
    );
    try {
      // Settings load asynchronously: SettingsNotifier starts at the DEFAULTS
      // and only adopts the diver's stored row once its first load completes.
      // Sweeping before that would grade every dive against default gradient
      // factors instead of the restored diver's -- the exact staleness this
      // container exists to avoid -- and would also dispose the container out
      // from under the in-flight load. A failed load is not fatal: the sweep
      // then runs on the defaults, which is what happens everywhere else.
      try {
        await container.read(settingsProvider.notifier).initialLoad;
      } catch (_) {
        // Intentionally ignored; see above.
      }
      return await container
          .read(safetyReviewSweepProvider)
          .run(
            // A restore replaces the whole library, so sweep every diver.
            diverId: null,
            onProgress: onProgress,
            isCancelled: isCancelled,
          );
    } finally {
      container.dispose();
    }
  }
}

final postRestoreSafetyReviewProvider = Provider<PostRestoreSafetyReview>(
  (ref) => PostRestoreSafetyReview(ref),
);
