import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/bathymetry/application/bathymetry_providers.dart';
import 'package:submersion/features/bathymetry/domain/bathymetry_grid.dart';
import 'package:submersion/features/bathymetry/presentation/bathymetry_overlay_providers.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';

class _TestSettingsNotifier extends StateNotifier<AppSettings>
    implements SettingsNotifier {
  _TestSettingsNotifier() : super(const AppSettings());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

BathymetryGrid grid() => BathymetryGrid(
  originLat: 10,
  originLon: 20,
  cellSizeLatDeg: 0.001,
  cellSizeLonDeg: 0.001,
  rows: 3,
  cols: 3,
  depthsMeters: const [5, 5, 5, 25, 25, 25, 45, 45, 45],
  sourceId: 'test',
  resolutionMeters: 100,
  fetchedAt: DateTime.utc(2026, 8, 15),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const cell = (lat: 10.0, lon: 20.0);

  ProviderContainer container({BathymetryGrid? g}) {
    final c = ProviderContainer(
      overrides: [
        bathymetryGridProvider.overrideWith((ref, cell) async => g),
        settingsProvider.overrideWith((ref) => _TestSettingsNotifier()),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('renders and caches the identical bytes instance per cell', () async {
    final c = container(g: grid());
    final first = await c.read(bathymetryOverlayProvider(cell).future);
    final second = await c.read(bathymetryOverlayProvider(cell).future);
    expect(first, isNotNull);
    // Reference identity is load-bearing: MemoryImage keys the ImageCache
    // by Uint8List identity, so a fresh allocation per read never caches.
    expect(identical(first!.pngBytes, second!.pngBytes), isTrue);
  });

  test('null grid yields null overlay', () async {
    final c = container(g: null);
    expect(await c.read(bathymetryOverlayProvider(cell).future), isNull);
  });
}
