import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the macOS entitlements the app needs at runtime.
///
/// These are plain-file assertions rather than platform tests so they run on
/// the Linux CI/coverage host: an entitlement can only be verified by the OS on
/// a signed, sandboxed macOS build, which CI does not execute. A missing key is
/// invisible until a real user plugs in real hardware, so the file itself is
/// the regression surface.
void main() {
  /// The sandboxed macOS builds. `ReleaseNoSandbox.entitlements` is
  /// deliberately excluded: it sets `com.apple.security.app-sandbox` to false,
  /// so sandbox hardware entitlements are inert there.
  const sandboxedEntitlements = <String>[
    'macos/Runner/DebugProfile.entitlements',
    'macos/Runner/Release.entitlements',
  ];

  String read(String path) {
    final file = File(path);
    expect(file.existsSync(), isTrue, reason: '$path is missing');
    return file.readAsStringSync();
  }

  group('macOS sandboxed entitlements', () {
    for (final path in sandboxedEntitlements) {
      test('$path declares the serial-port entitlement (issue #291)', () {
        // Without com.apple.security.device.serial, a sandboxed app is denied
        // open(2) on /dev/cu.* with EPERM, so every USB-serial dive computer
        // download fails with "Failed to open serial port". IOKit enumeration
        // is NOT gated the same way, so the port is still discovered and the
        // failure looks like a driver problem rather than a permission one.
        expect(
          read(path),
          contains('<key>com.apple.security.device.serial</key>'),
          reason:
              'Sandboxed macOS builds cannot open /dev/cu.* serial devices '
              'without com.apple.security.device.serial. Removing it silently '
              'breaks all USB-cable dive computer downloads (issue #291).',
        );
      });

      test('$path keeps the sandbox enabled', () {
        // Sanity anchor for the test above: if a build ever turns the sandbox
        // off, the serial assertion stops meaning what it claims to mean.
        expect(
          read(path),
          contains('<key>com.apple.security.app-sandbox</key>'),
          reason: '$path is expected to be a sandboxed build',
        );
      });
    }
  });
}
