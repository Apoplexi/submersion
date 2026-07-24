import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';

Dive _diveWithEntryTime(DateTime entryTime) => Dive(
  id: 'test-${entryTime.millisecondsSinceEpoch}',
  dateTime: entryTime,
  entryTime: entryTime,
  tanks: const [],
  profile: const [],
  equipment: const [],
  notes: '',
  photoIds: const [],
  sightings: const [],
  weights: const [],
  tags: const [],
);

void main() {
  group('daysSinceLastDiveProvider', () {
    test('returns 0 for a dive that occurred earlier today', () async {
      final now = DateTime.now();
      final todayDive = _diveWithEntryTime(
        DateTime(now.year, now.month, now.day, 8, 0),
      );
      final container = ProviderContainer(
        overrides: [
          recentDivesProvider.overrideWith((ref) async => [todayDive]),
        ],
      );
      addTearDown(container.dispose);

      final days = await container.read(daysSinceLastDiveProvider.future);
      expect(days, 0);
    });

    test(
      'returns 1 for a dive at 11:55 pm yesterday (issue #263 regression)',
      () async {
        final yesterday = DateTime.now().subtract(const Duration(days: 1));
        final lateDive = _diveWithEntryTime(
          DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 55),
        );
        final container = ProviderContainer(
          overrides: [
            recentDivesProvider.overrideWith((ref) async => [lateDive]),
          ],
        );
        addTearDown(container.dispose);

        final days = await container.read(daysSinceLastDiveProvider.future);
        expect(days, 1);
      },
    );

    test('returns 2 for a dive two calendar days ago', () async {
      final twoDaysAgo = DateTime.now().subtract(const Duration(days: 2));
      final oldDive = _diveWithEntryTime(
        DateTime(twoDaysAgo.year, twoDaysAgo.month, twoDaysAgo.day, 12, 0),
      );
      final container = ProviderContainer(
        overrides: [
          recentDivesProvider.overrideWith((ref) async => [oldDive]),
        ],
      );
      addTearDown(container.dispose);

      final days = await container.read(daysSinceLastDiveProvider.future);
      expect(days, 2);
    });

    test('returns null when there are no dives', () async {
      final container = ProviderContainer(
        overrides: [recentDivesProvider.overrideWith((ref) async => [])],
      );
      addTearDown(container.dispose);

      final days = await container.read(daysSinceLastDiveProvider.future);
      expect(days, isNull);
    });
  });
}
