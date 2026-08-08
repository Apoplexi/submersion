import 'package:flutter/material.dart' show DateTimeRange;
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/gps_log/domain/entities/gps_track.dart';
import 'package:submersion/features/gps_log/presentation/providers/gps_log_providers.dart';
import 'package:submersion/features/gps_log/presentation/providers/gps_track_map_providers.dart';

GpsTrack _track(String id, DateTime start) => GpsTrack(
  id: id,
  startTime: start.millisecondsSinceEpoch,
  endTime: start.add(const Duration(hours: 4)).millisecondsSinceEpoch,
);

ProviderContainer _container() {
  final container = ProviderContainer(
    overrides: [
      gpsTracksProvider.overrideWith(
        (ref) async => [
          _track('may', DateTime.utc(2026, 5, 10)),
          _track('june', DateTime.utc(2026, 6, 15)),
          _track('july', DateTime.utc(2026, 7, 20)),
        ],
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('returns every track when no filter is set', () async {
    final container = _container();
    expect((await container.read(filteredTracksProvider.future)).length, 3);
  });

  test('includes only tracks starting inside the range', () async {
    final container = _container();
    container.read(trackDateFilterProvider.notifier).state = DateTimeRange(
      start: DateTime.utc(2026, 6, 1),
      end: DateTime.utc(2026, 6, 30),
    );
    final tracks = await container.read(filteredTracksProvider.future);
    expect(tracks.map((t) => t.id).toList(), ['june']);
  });

  test('includes a track starting exactly on the range end date', () async {
    final container = _container();
    container.read(trackDateFilterProvider.notifier).state = DateTimeRange(
      start: DateTime.utc(2026, 5, 1),
      end: DateTime.utc(2026, 5, 10),
    );
    final tracks = await container.read(filteredTracksProvider.future);
    expect(tracks.map((t) => t.id).toList(), ['may']);
  });

  test('returns empty when the range matches nothing', () async {
    final container = _container();
    container.read(trackDateFilterProvider.notifier).state = DateTimeRange(
      start: DateTime.utc(2025, 1, 1),
      end: DateTime.utc(2025, 12, 31),
    );
    expect(await container.read(filteredTracksProvider.future), isEmpty);
  });

  test('clearing the filter restores every track', () async {
    final container = _container();
    container.read(trackDateFilterProvider.notifier).state = DateTimeRange(
      start: DateTime.utc(2026, 6, 1),
      end: DateTime.utc(2026, 6, 30),
    );
    await container.read(filteredTracksProvider.future);
    container.read(trackDateFilterProvider.notifier).state = null;
    expect((await container.read(filteredTracksProvider.future)).length, 3);
  });
}
