import 'package:submersion/core/utils/coordinates/coordinate_format.dart';
import 'package:submersion/core/utils/coordinates/mgrs_converter.dart';
import 'package:submersion/core/utils/coordinates/utm_converter.dart';

/// Renders a coordinate pair in the diver's chosen notation.
///
/// Grid formats degrade to decimal degrees outside the UTM latitude band
/// rather than returning an error string, so a polar site still shows a
/// usable position.
String formatCoordinates(
  double latitude,
  double longitude,
  CoordinateFormat format,
) {
  switch (format) {
    case CoordinateFormat.decimalDegrees:
    case CoordinateFormat.degreesDecimalMinutes:
    case CoordinateFormat.degreesMinutesSeconds:
      return '${formatLatitude(latitude, format)}, '
          '${formatLongitude(longitude, format)}';
    case CoordinateFormat.utm:
      final utm = latLngToUtm(latitude, longitude);
      if (utm == null) {
        return formatCoordinates(
          latitude,
          longitude,
          CoordinateFormat.decimalDegrees,
        );
      }
      return '${utm.zone}${utm.band} ${utm.easting.round()}E '
          '${utm.northing.round()}N';
    case CoordinateFormat.mgrs:
      final mgrs = latLngToMgrs(latitude, longitude);
      return mgrs ??
          formatCoordinates(
            latitude,
            longitude,
            CoordinateFormat.decimalDegrees,
          );
  }
}

/// Renders a single latitude. Grid formats degrade to decimal degrees.
String formatLatitude(double latitude, CoordinateFormat format) =>
    _formatAxis(latitude, format, isLatitude: true);

/// Renders a single longitude. Grid formats degrade to decimal degrees.
String formatLongitude(double longitude, CoordinateFormat format) =>
    _formatAxis(longitude, format, isLatitude: false);

String _formatAxis(
  double value,
  CoordinateFormat format, {
  required bool isLatitude,
}) {
  final hemisphere = isLatitude
      ? (value >= 0 ? 'N' : 'S')
      : (value >= 0 ? 'E' : 'W');
  final magnitude = value.abs();

  switch (format) {
    case CoordinateFormat.degreesDecimalMinutes:
      var degrees = magnitude.floor();
      var minutes = (magnitude - degrees) * 60;
      // Rounding for display can reach exactly 60; carry instead of printing
      // a minute value that does not exist.
      if (double.parse(minutes.toStringAsFixed(3)) >= 60) {
        minutes = 0;
        degrees += 1;
      }
      return '$degrees° ${minutes.toStringAsFixed(3).padLeft(6, '0')}\' '
          '$hemisphere';

    case CoordinateFormat.degreesMinutesSeconds:
      var degrees = magnitude.floor();
      final minutesFull = (magnitude - degrees) * 60;
      var minutes = minutesFull.floor();
      var seconds = (minutesFull - minutes) * 60;
      if (double.parse(seconds.toStringAsFixed(1)) >= 60) {
        seconds = 0;
        minutes += 1;
      }
      if (minutes >= 60) {
        minutes = 0;
        degrees += 1;
      }
      return '$degrees° ${minutes.toString().padLeft(2, '0')}\' '
          '${seconds.toStringAsFixed(1).padLeft(4, '0')}" $hemisphere';

    case CoordinateFormat.decimalDegrees:
    case CoordinateFormat.utm:
    case CoordinateFormat.mgrs:
      return '${magnitude.toStringAsFixed(6)}° $hemisphere';
  }
}
