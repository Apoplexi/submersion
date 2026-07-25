import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:submersion/core/theme/display_zoom.dart';
import 'package:submersion/features/settings/presentation/providers/display_zoom_provider.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';

Future<ProviderContainer> _container(Map<String, Object> initial) async {
  SharedPreferences.setMockInitialValues(initial);
  final prefs = await SharedPreferences.getInstance();
  final container = ProviderContainer(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to 100% when nothing is stored', () async {
    final container = await _container({});
    expect(
      container.read(displayZoomNotifierProvider),
      DisplayZoom.defaultValue,
    );
  });

  test('reads the stored value synchronously on first read', () async {
    final container = await _container({'display_zoom': 0.85});
    expect(container.read(displayZoomNotifierProvider), 0.85);
  });

  test('clamps a corrupt stored value', () async {
    final container = await _container({'display_zoom': 0.0});
    expect(container.read(displayZoomNotifierProvider), DisplayZoom.min);
  });

  test('setZoom persists the clamped value', () async {
    final container = await _container({});
    await container.read(displayZoomNotifierProvider.notifier).setZoom(9.9);

    expect(container.read(displayZoomNotifierProvider), DisplayZoom.max);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('display_zoom'), DisplayZoom.max);
  });

  test('stepBy walks the ladder in both directions', () async {
    final container = await _container({'display_zoom': 1.0});
    final notifier = container.read(displayZoomNotifierProvider.notifier);

    await notifier.stepBy(1);
    expect(container.read(displayZoomNotifierProvider), moreOrLessEquals(1.05));

    await notifier.stepBy(-1);
    await notifier.stepBy(-1);
    expect(container.read(displayZoomNotifierProvider), moreOrLessEquals(0.95));
  });

  test('stepBy saturates at the bounds', () async {
    final container = await _container({'display_zoom': DisplayZoom.max});
    final notifier = container.read(displayZoomNotifierProvider.notifier);

    await notifier.stepBy(1);
    expect(container.read(displayZoomNotifierProvider), DisplayZoom.max);
  });

  test('reset returns to the default', () async {
    final container = await _container({'display_zoom': 0.75});
    await container.read(displayZoomNotifierProvider.notifier).reset();
    expect(
      container.read(displayZoomNotifierProvider),
      DisplayZoom.defaultValue,
    );
  });
}
