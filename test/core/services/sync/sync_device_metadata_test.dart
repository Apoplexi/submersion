import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/services/sync/sync_device_metadata.dart';

void main() {
  group('sanitizeDeviceName', () {
    test('keeps a real hostname', () {
      expect(
        SyncDeviceMetadata.sanitizeDeviceName('Erics-MacBook-Pro'),
        'Erics-MacBook-Pro',
      );
    });

    test('trims surrounding whitespace', () {
      expect(
        SyncDeviceMetadata.sanitizeDeviceName('  Erics-iPhone  '),
        'Erics-iPhone',
      );
    });

    test('treats null, empty and whitespace as absent', () {
      expect(SyncDeviceMetadata.sanitizeDeviceName(null), isNull);
      expect(SyncDeviceMetadata.sanitizeDeviceName(''), isNull);
      expect(SyncDeviceMetadata.sanitizeDeviceName('   '), isNull);
    });

    test('treats localhost as absent regardless of case', () {
      // Android commonly reports 'localhost'; every device claiming the same
      // name is worse than falling back to the device id.
      expect(SyncDeviceMetadata.sanitizeDeviceName('localhost'), isNull);
      expect(SyncDeviceMetadata.sanitizeDeviceName('LocalHost'), isNull);
      expect(SyncDeviceMetadata.sanitizeDeviceName(' localhost '), isNull);
    });
  });
}
