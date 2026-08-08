/// One fix as it came out of a file, before any timezone reinterpretation.
typedef ParsedFix = ({DateTime utc, double lat, double lon, double? accuracy});

/// A track as parsed from a file.
///
/// Times are REAL UTC. Conversion to the app's wall-clock-as-UTC convention
/// happens once in the import service, after the track's offset is resolved -
/// never in a parser, which has no way to know that offset.
class ParsedTrack {
  final String? name;
  final List<ParsedFix> fixes;

  const ParsedTrack({this.name, required this.fixes});
}

/// A file could not be understood as a track.
class TrackParseException implements Exception {
  final String message;
  const TrackParseException(this.message);

  @override
  String toString() => 'TrackParseException: $message';
}

/// Rejects coordinates outside the valid range.
void validateCoordinate(double lat, double lon) {
  if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
    throw TrackParseException('Coordinate out of range: $lat, $lon');
  }
}
