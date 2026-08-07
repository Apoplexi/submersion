// `show Locale` on purpose: flutter/widgets.dart exports a Visibility widget
// that collides with the app's Visibility enum.
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/constants/enums.dart';
import 'package:submersion/core/constants/units.dart';
import 'package:submersion/core/domain/visibility/visibility_scale.dart';
import 'package:submersion/core/utils/unit_formatter.dart';
import 'package:submersion/features/dive_log/presentation/formatters/visibility_display.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

void main() {
  const metric = UnitFormatter(AppSettings(depthUnit: DepthUnit.meters));
  const imperial = UnitFormatter(AppSettings(depthUnit: DepthUnit.feet));

  late AppLocalizations en;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('visibilityBandName', () {
    test('names every band', () {
      expect(visibilityBandName(VisibilityBand.excellent, en), 'Excellent');
      expect(visibilityBandName(VisibilityBand.good, en), 'Good');
      expect(visibilityBandName(VisibilityBand.moderate, en), 'Moderate');
      expect(visibilityBandName(VisibilityBand.poor, en), 'Poor');
    });
  });

  group('formatMeasuredVisibility', () {
    test('shows the distance and the calibrated adjective', () {
      final text = formatMeasuredVisibility(
        6,
        VisibilityScale.coldWater,
        en,
        metric,
      );
      expect(text, contains('Good'));
      expect(text, contains('6'));
    });

    test('the same distance re-labels under a different calibration', () {
      // The whole point of storing the measurement: only the adjective moves.
      final cold = formatMeasuredVisibility(
        6,
        VisibilityScale.coldWater,
        en,
        metric,
      );
      final tropical = formatMeasuredVisibility(
        6,
        VisibilityScale.tropical,
        en,
        metric,
      );
      expect(cold, contains('Good'));
      expect(tropical, contains('Moderate'));
    });

    test('imperial converts the distance but not the band', () {
      final text = formatMeasuredVisibility(
        6,
        VisibilityScale.coldWater,
        en,
        imperial,
      );
      // 6 m is roughly 20 ft; the band is decided on the metric value.
      expect(text, contains('20'));
      expect(text, contains('ft'));
      expect(text, contains('Good'));
    });

    test('a 12 m cold-water day reads Excellent', () {
      expect(
        formatMeasuredVisibility(12, VisibilityScale.coldWater, en, metric),
        contains('Excellent'),
      );
    });
  });

  group('formatLegacyVisibilityBand', () {
    test('renders a bounded band as a range, never an adjective', () {
      final text = formatLegacyVisibilityBand(Visibility.moderate, en, metric)!;
      expect(text, contains('5'));
      expect(text, contains('15'));
      expect(text, isNot(contains('Moderate')));
    });

    test('uses over phrasing for the unbounded top band', () {
      final text = formatLegacyVisibilityBand(
        Visibility.excellent,
        en,
        metric,
      )!;
      expect(text, contains('over'));
      expect(text, contains('30'));
      expect(text, isNot(contains('Excellent')));
    });

    test('uses under phrasing for the unbounded bottom band', () {
      final text = formatLegacyVisibilityBand(Visibility.poor, en, metric)!;
      expect(text, contains('under'));
      expect(text, contains('5'));
      expect(text, isNot(contains('Poor')));
    });

    test('converts the bounds to the diver units', () {
      final text = formatLegacyVisibilityBand(
        Visibility.moderate,
        en,
        imperial,
      )!;
      // 5 m and 15 m in feet, at the same rounding the formatter uses.
      expect(text, contains(imperial.convertDepth(5).toStringAsFixed(0)));
      expect(text, contains(imperial.convertDepth(15).toStringAsFixed(0)));
      expect(text, contains('ft'));
    });

    test('unknown has no band to render', () {
      expect(
        formatLegacyVisibilityBand(Visibility.unknown, en, metric),
        isNull,
      );
    });
  });
}
