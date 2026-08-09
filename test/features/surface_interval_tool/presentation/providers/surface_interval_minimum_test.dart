import 'package:flutter_test/flutter_test.dart';

import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';
import 'package:submersion/features/surface_interval_tool/presentation/providers/surface_interval_providers.dart';

/// Minimal stand-in for [SettingsNotifier] so the deco providers can read
/// gradient factors without touching the database.
class _TestSettingsNotifier extends StateNotifier<AppSettings>
    implements SettingsNotifier {
  _TestSettingsNotifier() : super(const AppSettings());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _createContainer() {
  final container = ProviderContainer(
    overrides: [
      settingsProvider.overrideWith((ref) => _TestSettingsNotifier()),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Sets up a two-dive plan and returns the computed minimum interval.
SiMinimumInterval _planFor(
  ProviderContainer container, {
  required double firstDepth,
  required int firstTime,
  required double secondDepth,
  required int secondTime,
}) {
  container.read(siFirstDiveDepthProvider.notifier).state = firstDepth;
  container.read(siFirstDiveTimeProvider.notifier).state = firstTime;
  container.read(siSecondDiveDepthProvider.notifier).state = secondDepth;
  container.read(siSecondDiveTimeProvider.notifier).state = secondTime;
  return container.read(siMinimumIntervalProvider);
}

void main() {
  group('siMinimumIntervalProvider rejects unreachable second dives', () {
    test('a second dive longer than the best no-stop time is unreachable', () {
      final container = _createContainer();

      // The reported case: two 45 minute dives at 18 m on air. Off-gassing at
      // the surface can only ever restore tissues to their virgin state, and
      // the virgin no-stop time at 18 m on air is around 43 minutes. No surface
      // interval, however long, buys a 45 minute second dive.
      final result = _planFor(
        container,
        firstDepth: 18.0,
        firstTime: 45,
        secondDepth: 18.0,
        secondTime: 45,
      );

      expect(result.isAchievable, isFalse);
      expect(result.minutes, isNull);
      expect(
        result.maxNoStopSeconds,
        lessThan(45 * 60),
        reason: 'the no-stop ceiling is what puts the dive out of reach',
      );
    });

    test('never reports the search bound as if it were an answer', () {
      final container = _createContainer();

      // Deep and long enough that the plan is wildly out of reach. The old
      // binary search returned its own upper bound here, which the result card
      // rendered as a plausible looking "6h 0m".
      final result = _planFor(
        container,
        firstDepth: 40.0,
        firstTime: 20,
        secondDepth: 40.0,
        secondTime: 60,
      );

      expect(result.isAchievable, isFalse);
    });

    test('shortening the second dive turns it into a modest wait', () {
      final container = _createContainer();

      final tooLong = _planFor(
        container,
        firstDepth: 18.0,
        firstTime: 45,
        secondDepth: 18.0,
        secondTime: 45,
      );
      final achievable = _planFor(
        container,
        firstDepth: 18.0,
        firstTime: 45,
        secondDepth: 18.0,
        secondTime: 40,
      );

      // The cliff the diver saw: five fewer minutes underwater swings the
      // answer from "six hours" to about an hour. Only one of these two is a
      // real number, and it is the shorter dive.
      expect(tooLong.isAchievable, isFalse);
      expect(achievable.isAchievable, isTrue);
      expect(achievable.minutes, lessThan(120));
    });
  });

  group('siMinimumIntervalProvider reports reachable second dives', () {
    test('reports zero when the second dive already fits with no wait', () {
      final container = _createContainer();

      final result = _planFor(
        container,
        firstDepth: 18.0,
        firstTime: 20,
        secondDepth: 9.0,
        secondTime: 10,
      );

      expect(result.isAchievable, isTrue);
      expect(
        result.minutes,
        0,
        reason: 'a diver who needs no wait must not be told to wait a minute',
      );
    });

    test('the reported interval really does fit the planned dive', () {
      final container = _createContainer();

      for (final secondTime in [20, 30, 35, 40]) {
        final result = _planFor(
          container,
          firstDepth: 18.0,
          firstTime: 45,
          secondDepth: 18.0,
          secondTime: secondTime,
        );

        expect(
          result.isAchievable,
          isTrue,
          reason: '$secondTime min is doable',
        );
        expect(
          result.maxNoStopSeconds,
          greaterThanOrEqualTo(secondTime * 60),
          reason: 'an achievable plan must sit under the no-stop ceiling',
        );

        // Wind the tool to the interval it just recommended and confirm the
        // second dive actually fits inside the NDL there.
        container.read(siSurfaceIntervalProvider.notifier).state =
            result.minutes!;
        expect(
          container.read(siSecondDiveNdlProvider),
          greaterThanOrEqualTo(secondTime * 60),
          reason: 'the recommended interval must satisfy the requirement',
        );
        expect(container.read(siSecondDiveIsSafeProvider), isTrue);
      }
    });

    test('one minute less than the recommendation is not enough', () {
      final container = _createContainer();

      final result = _planFor(
        container,
        firstDepth: 18.0,
        firstTime: 45,
        secondDepth: 18.0,
        secondTime: 40,
      );

      expect(result.minutes, greaterThan(0));

      container.read(siSurfaceIntervalProvider.notifier).state =
          result.minutes! - 1;
      expect(
        container.read(siSecondDiveIsSafeProvider),
        isFalse,
        reason: 'the answer must be the minimum, not merely a sufficient wait',
      );
    });

    test('nitrox requires a shorter surface interval than air', () {
      final container = _createContainer();

      final air = _planFor(
        container,
        firstDepth: 30.0,
        firstTime: 25,
        secondDepth: 18.0,
        secondTime: 30,
      );

      container.read(siSecondDiveO2Provider.notifier).state = 32.0;
      final nitrox = container.read(siMinimumIntervalProvider);

      expect(air.isAchievable, isTrue);
      expect(nitrox.isAchievable, isTrue);
      expect(air.minutes, greaterThan(0));
      expect(
        nitrox.minutes,
        lessThan(air.minutes!),
        reason: 'A leaner nitrogen mix should shorten the required off-gassing',
      );
    });
  });
}
