import 'package:submersion/core/constants/enums.dart';
import 'package:submersion/core/domain/visibility/visibility_scale.dart';
import 'package:submersion/core/utils/unit_formatter.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

/// On-screen rendering of a dive's visibility.
///
/// Two shapes exist because two kinds of data exist. A dive logged from v144
/// carries a measured distance, so it can be shown as a distance plus the
/// adjective the diver's calibration assigns. A dive logged earlier carries
/// only a coarse bucket, so it can only be shown as the range that bucket
/// covers.
///
/// The enum `displayName` values remain the locale-independent strings used
/// for data interchange; everything here honours the active locale and the
/// diver's unit settings.

/// Localized name for a calibrated band.
String visibilityBandName(VisibilityBand band, AppLocalizations l10n) =>
    switch (band) {
      VisibilityBand.excellent => l10n.enum_visibilityBand_excellent,
      VisibilityBand.good => l10n.enum_visibilityBand_good,
      VisibilityBand.moderate => l10n.enum_visibilityBand_moderate,
      VisibilityBand.poor => l10n.enum_visibilityBand_poor,
    };

/// Renders a measured distance together with the adjective [scale] assigns it,
/// for example "20ft · Excellent".
///
/// [meters] is the stored metric value; [units] converts it for display. The
/// band is always decided on the metric value, so switching units never
/// changes the adjective.
String formatMeasuredVisibility(
  double meters,
  VisibilityScale scale,
  AppLocalizations l10n,
  UnitFormatter units,
) {
  final distance = units.formatDistance(meters);
  final band = visibilityBandName(scale.bandFor(meters), l10n);
  return '$distance · $band';
}

/// Renders a pre-v144 bucket as the distance range it actually means, for
/// example "5-15m".
///
/// Deliberately never returns an adjective. The stored bucket only tells us
/// the dive fell somewhere in this range, so applying the diver's calibration
/// would assert something we cannot know. Returns null for
/// [Visibility.unknown], which carries no range at all.
String? formatLegacyVisibilityBand(
  Visibility legacy,
  AppLocalizations l10n,
  UnitFormatter units,
) {
  final min = legacy.bandMinM;
  final max = legacy.bandMaxM;
  if (min == null && max == null) return null;

  final unit = units.depthSymbol;
  String value(double meters) => units.convertDepth(meters).toStringAsFixed(0);

  if (min == null) return l10n.visibility_range_under(value(max!), unit);
  if (max == null) return l10n.visibility_range_over(value(min), unit);
  return l10n.visibility_range_between(value(min), value(max), unit);
}
