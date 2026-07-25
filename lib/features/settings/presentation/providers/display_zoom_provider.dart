import 'package:shared_preferences/shared_preferences.dart';

import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/core/theme/display_zoom.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';

/// App-wide display zoom, stored per device.
///
/// Deliberately kept off AppSettings: zoom is device-local rather than
/// per-diver, and SettingsNotifier awaits a database round-trip before it
/// reads SharedPreferences, which would make the first frames render at 100%
/// before snapping to the stored value. Seeding from SharedPreferences in the
/// constructor makes the correct zoom available on frame one.
class DisplayZoomNotifier extends StateNotifier<double> {
  DisplayZoomNotifier(this._prefs)
    : super(
        DisplayZoom.clampValue(
          _prefs.getDouble(SettingsKeys.displayZoom) ??
              DisplayZoom.defaultValue,
        ),
      );

  final SharedPreferences _prefs;

  Future<void> setZoom(double value) async {
    final clamped = DisplayZoom.clampValue(value);
    if (clamped == state) return;
    state = clamped;
    await _prefs.setDouble(SettingsKeys.displayZoom, clamped);
  }

  /// Moves one [DisplayZoom.step] in [direction] (+1 larger, -1 smaller).
  Future<void> stepBy(int direction) =>
      setZoom(state + direction * DisplayZoom.step);

  Future<void> reset() => setZoom(DisplayZoom.defaultValue);
}

final displayZoomNotifierProvider =
    StateNotifierProvider<DisplayZoomNotifier, double>((ref) {
      return DisplayZoomNotifier(ref.watch(sharedPreferencesProvider));
    });
