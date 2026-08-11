import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/settings/presentation/providers/sync_providers.dart';

void main() {
  group('ReplacePreflight', () {
    test('a null peer count means the listing did not succeed', () {
      const preflight = ReplacePreflight(localDiveCount: 1247);

      expect(preflight.localDiveCount, 1247);
      expect(preflight.peerFileCount, isNull);
      expect(preflight.hasPeerCount, isFalse);
    });

    test('a known peer count is reported', () {
      const preflight = ReplacePreflight(
        localDiveCount: 1247,
        peerFileCount: 2,
      );

      expect(preflight.peerFileCount, 2);
      expect(preflight.hasPeerCount, isTrue);
    });

    test('zero peers is a known count, not an unknown one', () {
      // A solo device must still be able to replace: the dialog says "every
      // other device" only when the listing FAILED, never when it found none.
      const preflight = ReplacePreflight(localDiveCount: 10, peerFileCount: 0);

      expect(preflight.hasPeerCount, isTrue);
    });
  });
}
