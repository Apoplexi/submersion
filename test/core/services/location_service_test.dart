import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/services/location_service.dart';

void main() {
  group('Nominatim URIs pin English results (#214)', () {
    test('reverse geocode URI carries accept-language=en', () {
      final uri = LocationService.buildReverseGeocodeUri(36.0, -5.6);
      expect(
        uri.queryParameters['accept-language'],
        'en',
        reason:
            'without a pinned language Nominatim answers in the request '
            'locale, splitting statistics into Spain/Spanien/España rows',
      );
      expect(uri.queryParameters['lat'], '36.0');
      expect(uri.queryParameters['lon'], '-5.6');
    });

    test('forward geocode URI carries accept-language=en', () {
      final uri = LocationService.buildForwardGeocodeUri('Blue Hole');
      expect(uri.queryParameters['accept-language'], 'en');
      expect(uri.queryParameters['q'], 'Blue Hole');
    });
  });
}
