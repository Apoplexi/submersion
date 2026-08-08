import 'package:submersion/features/dive_log/domain/entities/dive.dart';

/// Real UTC offsets range from -12:00 to +14:00.
const int _kMinOffsetMinutes = -720;
const int _kMaxOffsetMinutes = 840;

/// Converts a real-UTC instant into the app's wall-clock-as-UTC epoch
/// seconds, using an EXPLICIT offset.
///
/// Deliberately distinct from `toWallClockEpochSeconds` in
/// track_point_codec.dart, which uses the running device's local zone. That
/// is correct while recording (the device IS the recorder) and wrong on
/// import (the device is wherever the diver happens to be sitting). Import a
/// Cozumel track in Seattle with the recording-time helper and every fix
/// lands two hours off, silently matching zero dives.
int toWallClockEpochSecondsAt(DateTime realUtc, int tzOffsetMinutes) {
  return realUtc
          .add(Duration(minutes: tzOffsetMinutes))
          .millisecondsSinceEpoch ~/
      1000;
}

/// Best guess at the offset a track was recorded under, from dives logged
/// around the same time.
///
/// Dive entry times are already wall-clock-as-UTC, so the difference between
/// a dive's stored entry and the track's real-UTC first fix IS the offset.
/// Returns null when nothing plausible can be inferred - the import review
/// step then asks rather than guessing.
int? inferOffsetFromDives(DateTime firstFixUtc, List<Dive> dives) {
  if (dives.isEmpty) return null;

  Dive? nearest;
  var smallestGap = const Duration(days: 1);
  for (final dive in dives) {
    final gap = dive.effectiveEntryTime.difference(firstFixUtc).abs();
    if (gap < smallestGap) {
      smallestGap = gap;
      nearest = dive;
    }
  }
  if (nearest == null) return null;

  final impliedMinutes = nearest.effectiveEntryTime
      .difference(firstFixUtc)
      .inMinutes;

  // Snap to a quarter hour: every real-world zone is a multiple of 15.
  final snapped = (impliedMinutes / 15).round() * 15;

  if (snapped < _kMinOffsetMinutes || snapped > _kMaxOffsetMinutes) {
    return null;
  }
  return snapped;
}
