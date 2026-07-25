import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:submersion/core/services/cloud_storage/cloud_storage_provider.dart';
import 'package:submersion/core/services/cloud_storage/icloud_storage_provider.dart';

/// Routes getApplicationDocumentsDirectory to a temp dir, so that if the
/// provider ever tries to substitute local storage for the iCloud container the
/// attempt succeeds and the test can catch it.
class _FakePathProvider extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _FakePathProvider(this.docsPath);
  final String docsPath;

  @override
  Future<String?> getApplicationDocumentsPath() async => docsPath;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('app.submersion/icloud_container');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory tempDir;
  late PathProviderPlatform originalPathProvider;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('icloud_provider_test');
    originalPathProvider = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tempDir.path);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    PathProviderPlatform.instance = originalPathProvider;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('ICloudStorageProvider with no reachable ubiquity container', () {
    // The native lookup returns null whenever iCloud cannot serve this app:
    // no iCloud account signed in, or a build without the ubiquity
    // entitlement. The iOS Simulator is permanently in this state.
    setUp(() {
      messenger.setMockMethodCallHandler(channel, (call) async => null);
    });

    test(
      'reports unavailable on iOS instead of substituting local storage',
      () async {
        final provider = ICloudStorageProvider(
          isApplePlatform: true,
          isIOS: true,
        );

        expect(await provider.isAvailable(), isFalse);
      },
    );

    test('leaves no local stand-in directory behind on iOS', () async {
      final provider = ICloudStorageProvider(
        isApplePlatform: true,
        isIOS: true,
      );

      await provider.isAvailable();

      expect(
        Directory(p.join(tempDir.path, 'iCloud')).existsSync(),
        isFalse,
        reason:
            'a local Documents/iCloud folder is not iCloud; syncing into it '
            'strands data where no other device can ever see it',
      );
    });

    test('authenticate throws on iOS rather than reporting success', () async {
      final provider = ICloudStorageProvider(
        isApplePlatform: true,
        isIOS: true,
      );

      await expectLater(
        provider.authenticate(),
        throwsA(isA<CloudStorageException>()),
      );
    });

    test('reports unavailable on macOS', () async {
      final provider = ICloudStorageProvider(
        isApplePlatform: true,
        isIOS: false,
      );

      expect(await provider.isAvailable(), isFalse);
    });
  });

  test('reports unavailable on non-Apple platforms', () async {
    final provider = ICloudStorageProvider(
      isApplePlatform: false,
      isIOS: false,
    );

    expect(await provider.isAvailable(), isFalse);
  });
}
