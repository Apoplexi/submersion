import 'package:xml/xml.dart';

import 'package:submersion/features/gps_log/data/services/track_import/parsed_track.dart';

/// Parses a KML `<gx:Track>` into a [ParsedTrack].
///
/// Only the timestamped gx:Track form is supported. A plain `<LineString>`
/// carries geometry with no times, and a track without times can be neither
/// matched to dives nor colorized - the same rule the GPX parser applies.
ParsedTrack parseKml(String xml) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(xml);
  } on XmlException catch (e) {
    throw TrackParseException('Not valid XML: ${e.message}');
  }

  final whens = document.findAllElements('when').toList();
  // Match on the local name so an unprefixed document still parses, while
  // real producers emit gx:coord.
  final coords = document.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 'coord')
      .toList();

  if (whens.isEmpty || coords.isEmpty) {
    throw const TrackParseException(
      'No <gx:Track> with timestamps found. A plain LineString has no times '
      'and cannot be imported.',
    );
  }
  if (whens.length != coords.length) {
    throw TrackParseException(
      'Mismatched <when> (${whens.length}) and <gx:coord> '
      '(${coords.length}) counts',
    );
  }

  final fixes = <ParsedFix>[];
  for (var i = 0; i < whens.length; i++) {
    final time = DateTime.tryParse(whens[i].innerText.trim());
    if (time == null) {
      throw TrackParseException('Unparseable time: ${whens[i].innerText}');
    }

    // gx:coord is "lon lat alt" - the REVERSE of GPX's lat/lon attributes.
    // Reading it backwards silently relocates the track.
    final parts = coords[i].innerText.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) {
      throw TrackParseException('Malformed coord: ${coords[i].innerText}');
    }
    final lon = double.tryParse(parts[0]);
    final lat = double.tryParse(parts[1]);
    if (lat == null || lon == null) {
      throw TrackParseException('Unparseable coord: ${coords[i].innerText}');
    }
    validateCoordinate(lat, lon);

    fixes.add((utc: time.toUtc(), lat: lat, lon: lon, accuracy: null));
  }

  fixes.sort((a, b) => a.utc.compareTo(b.utc));

  return ParsedTrack(
    name: document.findAllElements('name').firstOrNull?.innerText.trim(),
    fixes: List.unmodifiable(fixes),
  );
}
