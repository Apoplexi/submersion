import 'package:xml/xml.dart';

import 'package:submersion/features/gps_log/data/services/track_import/parsed_track.dart';

/// Parses a GPX 1.0 or 1.1 document into a [ParsedTrack].
///
/// Requires a `<time>` on every `<trkpt>`. The schema makes it optional, but a
/// track without timestamps can be neither matched to dives nor colorized by
/// speed or elapsed time, so accepting one would mean threading a nullable
/// timestamp through every downstream feature to serve a file nobody can use.
ParsedTrack parseGpx(String xml) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(xml);
  } on XmlException catch (e) {
    throw TrackParseException('Not valid XML: ${e.message}');
  }

  // findAllElements without a namespace matches regardless of the default
  // xmlns, which differs between GPX 1.0 and 1.1 producers.
  final trackPoints = document.findAllElements('trkpt').toList();
  if (trackPoints.isEmpty) {
    throw const TrackParseException('No <trkpt> elements found');
  }

  final fixes = <ParsedFix>[];
  var anyZoned = false;
  for (final node in trackPoints) {
    final latText = node.getAttribute('lat');
    final lonText = node.getAttribute('lon');
    if (latText == null || lonText == null) {
      throw const TrackParseException('<trkpt> missing lat or lon');
    }
    final lat = double.tryParse(latText);
    final lon = double.tryParse(lonText);
    if (lat == null || lon == null) {
      throw TrackParseException('Unparseable coordinate: $latText, $lonText');
    }
    validateCoordinate(lat, lon);

    final timeText = node.findElements('time').firstOrNull?.innerText.trim();
    if (timeText == null || timeText.isEmpty) {
      throw const TrackParseException(
        'Every track point needs a <time>; this file has points without one',
      );
    }
    final parsed = parseFixTime(timeText);
    if (parsed == null) {
      throw TrackParseException('Unparseable time: $timeText');
    }
    if (parsed.zoned) anyZoned = true;

    final hdopText = node.findElements('hdop').firstOrNull?.innerText.trim();

    fixes.add((
      utc: parsed.time,
      lat: lat,
      lon: lon,
      accuracy: hdopText == null ? null : double.tryParse(hdopText),
    ));
  }

  fixes.sort((a, b) => a.utc.compareTo(b.utc));

  return ParsedTrack(
    name: document.findAllElements('name').firstOrNull?.innerText.trim(),
    fixes: List.unmodifiable(fixes),
    timesAreWallClock: !anyZoned,
  );
}
