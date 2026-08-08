import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/gps_log/data/services/track_import/csv_track_parser.dart';
import 'package:submersion/features/gps_log/data/services/track_import/parsed_track.dart';

String _fixture() =>
    File('test/fixtures/gps_tracks/sample.csv').readAsStringSync();

void main() {
  group('readCsvHeaders', () {
    test('returns the header row', () {
      expect(readCsvHeaders(_fixture()), [
        'timestamp',
        'latitude',
        'longitude',
        'accuracy',
      ]);
    });

    test('throws on an empty file', () {
      expect(() => readCsvHeaders(''), throwsA(isA<TrackParseException>()));
    });
  });

  group('guessCsvMapping', () {
    test('recognises the common header names', () {
      final mapping = guessCsvMapping([
        'timestamp',
        'latitude',
        'longitude',
        'accuracy',
      ]);
      expect(mapping!.timeIndex, 0);
      expect(mapping.latIndex, 1);
      expect(mapping.lonIndex, 2);
      expect(mapping.accuracyIndex, 3);
    });

    test('recognises abbreviated headers case-insensitively', () {
      final mapping = guessCsvMapping(['Time', 'Lat', 'Lon']);
      expect(mapping!.timeIndex, 0);
      expect(mapping.latIndex, 1);
      expect(mapping.lonIndex, 2);
      expect(mapping.accuracyIndex, isNull);
    });

    test('returns null when a required column cannot be identified', () {
      expect(guessCsvMapping(['a', 'b', 'c']), isNull);
    });

    test('returns null when only latitude is missing', () {
      expect(guessCsvMapping(['time', 'longitude']), isNull);
    });
  });

  group('parseCsv', () {
    const mapping = CsvColumnMapping(
      timeIndex: 0,
      latIndex: 1,
      lonIndex: 2,
      accuracyIndex: 3,
    );

    test('parses every data row', () {
      expect(parseCsv(_fixture(), mapping).fixes.length, 3);
    });

    test('parses times as real UTC', () {
      final first = parseCsv(_fixture(), mapping).fixes.first;
      expect(first.utc, DateTime.utc(2026, 5, 22, 13));
      expect(first.utc.isUtc, isTrue);
    });

    test('leaves accuracy null for a blank cell', () {
      final fixes = parseCsv(_fixture(), mapping).fixes;
      expect(fixes[0].accuracy, closeTo(5.0, 1e-9));
      expect(fixes[1].accuracy, isNull);
    });

    test('rejects a row with an unparseable coordinate', () {
      const bad = 'time,lat,lon\n2026-05-22T13:00:00Z,north,-87.0\n';
      expect(
        () => parseCsv(
          bad,
          const CsvColumnMapping(timeIndex: 0, latIndex: 1, lonIndex: 2),
        ),
        throwsA(isA<TrackParseException>()),
      );
    });

    test('rejects a row with an unparseable time', () {
      const bad = 'time,lat,lon\nyesterday,20.5,-87.0\n';
      expect(
        () => parseCsv(
          bad,
          const CsvColumnMapping(timeIndex: 0, latIndex: 1, lonIndex: 2),
        ),
        throwsA(isA<TrackParseException>()),
      );
    });

    test('rejects a file with a header but no data rows', () {
      expect(
        () => parseCsv(
          'time,lat,lon\n',
          const CsvColumnMapping(timeIndex: 0, latIndex: 1, lonIndex: 2),
        ),
        throwsA(isA<TrackParseException>()),
      );
    });

    test('skips a trailing blank line rather than failing on it', () {
      const withBlank = 'time,lat,lon\n2026-05-22T13:00:00Z,20.5,-87.0\n\n';
      final track = parseCsv(
        withBlank,
        const CsvColumnMapping(timeIndex: 0, latIndex: 1, lonIndex: 2),
      );
      expect(track.fixes.length, 1);
    });

    test('honours a non-default column order', () {
      const reordered = 'lat,lon,time\n20.5,-87.0,2026-05-22T13:00:00Z\n';
      final track = parseCsv(
        reordered,
        const CsvColumnMapping(timeIndex: 2, latIndex: 0, lonIndex: 1),
      );
      expect(track.fixes.single.lat, closeTo(20.5, 1e-9));
      expect(track.fixes.single.utc, DateTime.utc(2026, 5, 22, 13));
    });
  });
}
