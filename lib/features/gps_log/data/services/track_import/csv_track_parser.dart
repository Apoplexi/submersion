import 'dart:convert';

import 'package:submersion/features/gps_log/data/services/track_import/parsed_track.dart';

/// Which CSV column holds which field.
///
/// CSV has no schema, so unlike GPX and KML this cannot be inferred with
/// confidence. [guessCsvMapping] proposes one; the import review step
/// presents it for confirmation rather than applying it silently.
class CsvColumnMapping {
  final int timeIndex;
  final int latIndex;
  final int lonIndex;
  final int? accuracyIndex;

  const CsvColumnMapping({
    required this.timeIndex,
    required this.latIndex,
    required this.lonIndex,
    this.accuracyIndex,
  });
}

const _kTimeHeaders = {'time', 'timestamp', 'datetime', 'date_time', 'utc'};
const _kLatHeaders = {'lat', 'latitude', 'y'};
const _kLonHeaders = {'lon', 'lng', 'long', 'longitude', 'x'};
const _kAccuracyHeaders = {'accuracy', 'hdop', 'precision', 'error'};

/// The header row, trimmed.
List<String> readCsvHeaders(String csv) {
  final lines = const LineSplitter().convert(csv);
  if (lines.isEmpty || lines.first.trim().isEmpty) {
    throw const TrackParseException('File is empty');
  }
  return [for (final h in lines.first.split(',')) h.trim()];
}

/// Proposes a mapping from common header names, or null when the required
/// three cannot be identified.
CsvColumnMapping? guessCsvMapping(List<String> headers) {
  int? find(Set<String> candidates) {
    for (var i = 0; i < headers.length; i++) {
      if (candidates.contains(headers[i].toLowerCase().trim())) return i;
    }
    return null;
  }

  final time = find(_kTimeHeaders);
  final lat = find(_kLatHeaders);
  final lon = find(_kLonHeaders);
  if (time == null || lat == null || lon == null) return null;

  return CsvColumnMapping(
    timeIndex: time,
    latIndex: lat,
    lonIndex: lon,
    accuracyIndex: find(_kAccuracyHeaders),
  );
}

ParsedTrack parseCsv(String csv, CsvColumnMapping mapping) {
  final lines = const LineSplitter().convert(csv);
  if (lines.length < 2) {
    throw const TrackParseException('File has a header but no data rows');
  }

  final fixes = <ParsedFix>[];
  for (var i = 1; i < lines.length; i++) {
    final line = lines[i].trim();
    // Trailing newlines are normal; a blank line is not an error.
    if (line.isEmpty) continue;

    final cells = line.split(',');
    String? cell(int? index) {
      if (index == null || index >= cells.length) return null;
      final value = cells[index].trim();
      return value.isEmpty ? null : value;
    }

    final timeText = cell(mapping.timeIndex);
    final time = timeText == null ? null : DateTime.tryParse(timeText);
    if (time == null) {
      throw TrackParseException('Row ${i + 1}: unparseable time "$timeText"');
    }

    final lat = double.tryParse(cell(mapping.latIndex) ?? '');
    final lon = double.tryParse(cell(mapping.lonIndex) ?? '');
    if (lat == null || lon == null) {
      throw TrackParseException('Row ${i + 1}: unparseable coordinate');
    }
    validateCoordinate(lat, lon);

    fixes.add((
      utc: time.toUtc(),
      lat: lat,
      lon: lon,
      accuracy: double.tryParse(cell(mapping.accuracyIndex) ?? ''),
    ));
  }

  if (fixes.isEmpty) {
    throw const TrackParseException('No usable data rows');
  }
  fixes.sort((a, b) => a.utc.compareTo(b.utc));
  return ParsedTrack(fixes: List.unmodifiable(fixes));
}
