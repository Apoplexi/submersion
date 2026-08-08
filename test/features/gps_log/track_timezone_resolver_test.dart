import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/gps_log/data/services/track_import/track_timezone_resolver.dart';

Dive _dive(DateTime entryWallClock) =>
    Dive(id: 'd', diveNumber: 1, dateTime: entryWallClock, maxDepth: 30.0);

void main() {
  group('toWallClockEpochSecondsAt', () {
    test('is identity for a zero offset', () {
      final utc = DateTime.utc(2026, 5, 22, 13);
      expect(
        toWallClockEpochSecondsAt(utc, 0),
        utc.millisecondsSinceEpoch ~/ 1000,
      );
    });

    test('shifts a negative offset back to local wall clock', () {
      // 13:00 real UTC in UTC-5 reads 08:00 on the wall.
      final result = toWallClockEpochSecondsAt(
        DateTime.utc(2026, 5, 22, 13),
        -300,
      );
      final wall = DateTime.fromMillisecondsSinceEpoch(
        result * 1000,
        isUtc: true,
      );
      expect(wall.hour, 8);
      expect(wall.day, 22);
    });

    test('shifts a positive offset forward', () {
      // 00:00 real UTC in UTC+8 reads 08:00 the same day.
      final result = toWallClockEpochSecondsAt(DateTime.utc(2026, 5, 22), 480);
      final wall = DateTime.fromMillisecondsSinceEpoch(
        result * 1000,
        isUtc: true,
      );
      expect(wall.hour, 8);
      expect(wall.day, 22);
    });

    test('rolls the date backwards when the offset crosses midnight', () {
      // 02:00 real UTC in UTC-5 reads 21:00 the previous day.
      final result = toWallClockEpochSecondsAt(
        DateTime.utc(2026, 5, 22, 2),
        -300,
      );
      final wall = DateTime.fromMillisecondsSinceEpoch(
        result * 1000,
        isUtc: true,
      );
      expect(wall.day, 21);
      expect(wall.hour, 21);
    });

    test('round-trips against the export conversion', () {
      // realUtcFrom is the inverse used by GPX export; the pair must compose
      // to identity or an export/re-import cycle drifts.
      final utc = DateTime.utc(2026, 5, 22, 13, 45, 30);
      const offset = -300;
      final wall = toWallClockEpochSecondsAt(utc, offset);
      final back = DateTime.fromMillisecondsSinceEpoch(
        wall * 1000,
        isUtc: true,
      ).subtract(const Duration(minutes: offset));
      expect(back, utc);
    });
  });

  group('inferOffsetFromDives', () {
    test('returns null when there are no dives', () {
      expect(
        inferOffsetFromDives(DateTime.utc(2026, 5, 22, 13), const []),
        isNull,
      );
    });

    test('infers the offset from the nearest dive on the same day', () {
      // Dive entry wall clock 08:30; first fix 13:00 real UTC => -270 min.
      final offset = inferOffsetFromDives(DateTime.utc(2026, 5, 22, 13), [
        _dive(DateTime.utc(2026, 5, 22, 8, 30)),
      ]);
      expect(offset, -270);
    });

    test('snaps a near-miss to a whole quarter hour', () {
      // 08:32 implies -268; real zones are multiples of 15.
      final offset = inferOffsetFromDives(DateTime.utc(2026, 5, 22, 13), [
        _dive(DateTime.utc(2026, 5, 22, 8, 32)),
      ]);
      expect(offset! % 15, 0);
    });

    test('returns null when no dive is within a day of the track', () {
      expect(
        inferOffsetFromDives(DateTime.utc(2026, 5, 22, 13), [
          _dive(DateTime.utc(2026, 8, 1, 8)),
        ]),
        isNull,
      );
    });

    test('rejects an implied offset outside the real range', () {
      // A dive 20 hours off implies an impossible zone; better to admit we
      // do not know than to store a fiction.
      expect(
        inferOffsetFromDives(DateTime.utc(2026, 5, 22, 13), [
          _dive(DateTime.utc(2026, 5, 21, 17)),
        ]),
        isNull,
      );
    });

    test('picks the nearest dive when several are in range', () {
      final offset = inferOffsetFromDives(DateTime.utc(2026, 5, 22, 13), [
        _dive(DateTime.utc(2026, 5, 22, 3)),
        _dive(DateTime.utc(2026, 5, 22, 8, 30)),
      ]);
      expect(offset, -270);
    });
  });
}
