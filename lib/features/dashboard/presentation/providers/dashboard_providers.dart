import 'package:submersion/core/providers/provider.dart';

import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/dive_log/presentation/providers/dive_providers.dart';
import 'package:submersion/features/divers/domain/entities/diver.dart';
import 'package:submersion/features/divers/presentation/providers/diver_providers.dart';
import 'package:submersion/features/equipment/presentation/providers/equipment_providers.dart';
import 'package:submersion/features/safety/domain/services/no_fly_service.dart';
import 'package:submersion/features/safety/presentation/providers/no_fly_providers.dart';
import 'package:submersion/features/statistics/data/repositories/statistics_repository.dart';
import 'package:submersion/features/statistics/presentation/providers/statistics_providers.dart';

/// Dashboard alerts data class
class DashboardAlerts {
  /// Per-clock service alerts from the service ledger (overdue/due-soon).
  final List<DueClock> serviceClocksDue;
  final bool insuranceExpiringSoon;
  final bool insuranceExpired;
  final DateTime? insuranceExpiryDate;
  final String? insuranceProvider;

  /// Active flying-after-diving restriction (null when clear).
  final NoFlyStatus? noFlyStatus;

  const DashboardAlerts({
    this.serviceClocksDue = const [],
    required this.insuranceExpiringSoon,
    required this.insuranceExpired,
    this.insuranceExpiryDate,
    this.insuranceProvider,
    this.noFlyStatus,
  });

  /// Whether an unexpired flying-after-diving restriction is in effect right
  /// now. [noFlyStatus] is a cached snapshot that can elapse while the
  /// dashboard stays mounted, so every consumer must re-check it against the
  /// clock instead of treating a non-null value as active.
  bool get hasActiveNoFly =>
      noFlyStatus != null && noFlyStatus!.isActiveAt(DateTime.now().toUtc());

  bool get hasAlerts =>
      serviceClocksDue.isNotEmpty ||
      insuranceExpiringSoon ||
      insuranceExpired ||
      hasActiveNoFly;

  int get alertCount {
    int count = serviceClocksDue.length;
    if (insuranceExpiringSoon || insuranceExpired) count++;
    if (hasActiveNoFly) count++;
    return count;
  }
}

/// Recent dives shown on the home tab (newest 3).
///
/// Self-invalidates on any `dives`-table write -- a dive computer import or an
/// iCloud sync applying remote changes directly to the DB -- so the home tab
/// reflects new dives without an app restart (issue #217).
///
/// Discovery is SQL-bounded (`getDiveSummaries(limit: 3)`); only the three
/// winners hydrate as full [Dive]s. The dashboard no longer forces
/// `getAllDives()` on the first home frame (WS4, large-DB performance).
final recentDivesProvider = FutureProvider<List<Dive>>((ref) async {
  final repository = ref.watch(diveRepositoryProvider);
  ref.invalidateSelfWhen(repository.watchDivesChanges());

  final currentDiverId = ref.watch(currentDiverIdProvider);
  final summaries = await repository.getDiveSummaries(
    diverId: currentDiverId,
    limit: 3,
  );
  final recent = <Dive>[];
  for (final summary in summaries) {
    final dive = await repository.getDiveById(summary.id);
    if (dive != null) recent.add(dive);
  }

  // Pre-load downsampled profiles so DiveListTile mini charts render
  // immediately (the batch cache is shared with the paginated dive list).
  if (recent.isNotEmpty) {
    final cache = ref.read(batchProfileCacheProvider);
    final uncached = recent
        .map((d) => d.id)
        .where((id) => !cache.containsKey(id))
        .toList();
    if (uncached.isNotEmpty) {
      final profiles = await repository.getBatchProfileSummaries(uncached);
      ref.read(batchProfileCacheProvider.notifier).state = {
        ...cache,
        ...profiles,
      };
    }
  }

  return recent;
});

/// Dashboard alerts provider - combines equipment and insurance alerts
final dashboardAlertsProvider = FutureProvider<DashboardAlerts>((ref) async {
  final clocksDue = await ref.watch(dueClocksProvider.future);
  final diver = await ref.watch(currentDiverProvider.future);
  final noFlyStatus = await ref.watch(noFlyStatusProvider.future);

  return DashboardAlerts(
    serviceClocksDue: clocksDue,
    insuranceExpiringSoon: diver?.insurance.isExpiringSoon ?? false,
    insuranceExpired: diver?.insurance.isExpired ?? false,
    insuranceExpiryDate: diver?.insurance.expiryDate,
    insuranceProvider: diver?.insurance.provider,
    noFlyStatus: noFlyStatus,
  );
});

/// Current diver provider (re-exported for convenience)
final dashboardDiverProvider = FutureProvider<Diver?>((ref) async {
  return ref.watch(currentDiverProvider.future);
});

/// Days since last dive provider
final daysSinceLastDiveProvider = FutureProvider<int?>((ref) async {
  final recentDives = await ref.watch(recentDivesProvider.future);
  if (recentDives.isEmpty) return null;

  final lastDive = recentDives.first.effectiveEntryTime;
  final now = DateTime.now();
  final diveDay = DateTime(lastDive.year, lastDive.month, lastDive.day);
  final today = DateTime(now.year, now.month, now.day);
  return today.difference(diveDay).inDays;
});

/// Monthly dive count provider (dives in current month): one SQL COUNT.
final monthlyDiveCountProvider = FutureProvider<int>((ref) async {
  final repository = ref.watch(diveRepositoryProvider);
  ref.invalidateSelfWhen(repository.watchDivesChanges());
  final currentDiverId = ref.watch(currentDiverIdProvider);
  final now = DateTime.now();
  return repository.countDivesSince(
    DateTime(now.year, now.month, 1),
    diverId: currentDiverId,
  );
});

/// Year-to-date dive count provider: one SQL COUNT.
final yearToDateDiveCountProvider = FutureProvider<int>((ref) async {
  final repository = ref.watch(diveRepositoryProvider);
  ref.invalidateSelfWhen(repository.watchDivesChanges());
  final currentDiverId = ref.watch(currentDiverIdProvider);
  final now = DateTime.now();
  return repository.countDivesSince(
    DateTime(now.year, 1, 1),
    diverId: currentDiverId,
  );
});

/// Personal records data class
class PersonalRecords {
  final Dive? deepestDive;
  final Dive? longestDive;
  final Dive? coldestDive;
  final Dive? warmestDive;
  final String? mostVisitedSiteId;
  final String? mostVisitedSiteName;
  final int? mostVisitedSiteCount;

  const PersonalRecords({
    this.deepestDive,
    this.longestDive,
    this.coldestDive,
    this.warmestDive,
    this.mostVisitedSiteId,
    this.mostVisitedSiteName,
    this.mostVisitedSiteCount,
  });

  bool get hasRecords =>
      deepestDive != null ||
      longestDive != null ||
      coldestDive != null ||
      warmestDive != null ||
      mostVisitedSiteName != null;
}

/// Personal records provider.
///
/// Winner SELECTION runs in SQL (six small indexed statements via
/// [DiveRepository.getPersonalRecordIds], including the full
/// effectiveRuntime resolution order for the longest dive); only the
/// handful of distinct winner dives hydrate as full [Dive]s, instead of
/// loading and scanning the entire table (WS4, large-DB performance).
final personalRecordsProvider = FutureProvider<PersonalRecords>((ref) async {
  final repository = ref.watch(diveRepositoryProvider);
  ref.invalidateSelfWhen(repository.watchDivesChanges());
  final currentDiverId = ref.watch(currentDiverIdProvider);

  final winners = await repository.getPersonalRecordIds(
    diverId: currentDiverId,
  );

  final ids = <String>{
    if (winners.deepestId != null) winners.deepestId!,
    if (winners.longestId != null) winners.longestId!,
    if (winners.coldestId != null) winners.coldestId!,
    if (winners.warmestId != null) winners.warmestId!,
  };
  final divesById = <String, Dive>{};
  for (final id in ids) {
    final dive = await repository.getDiveById(id);
    if (dive != null) divesById[id] = dive;
  }

  return PersonalRecords(
    deepestDive: divesById[winners.deepestId],
    longestDive: divesById[winners.longestId],
    coldestDive: divesById[winners.coldestId],
    warmestDive: divesById[winners.warmestId],
    mostVisitedSiteId: winners.mostVisitedSiteId,
    mostVisitedSiteName: winners.mostVisitedSiteName,
    mostVisitedSiteCount: winners.mostVisitedSiteCount,
  );
});

/// A GPS pin for the recent-sites mini map.
class RecentSitePin {
  final String? siteName;
  final double latitude;
  final double longitude;

  const RecentSitePin({
    required this.siteName,
    required this.latitude,
    required this.longitude,
  });
}

/// Distinct GPS-bearing sites among the last 10 dives.
final recentSitesProvider = FutureProvider<List<RecentSitePin>>((ref) async {
  final repository = ref.watch(diveRepositoryProvider);
  ref.invalidateSelfWhen(repository.watchDivesChanges());
  final currentDiverId = ref.watch(currentDiverIdProvider);
  final summaries = await repository.getDiveSummaries(
    diverId: currentDiverId,
    limit: 10,
  );
  final seen = <String>{};
  final pins = <RecentSitePin>[];
  for (final summary in summaries) {
    final lat = summary.siteLatitude;
    final lng = summary.siteLongitude;
    if (lat == null || lng == null) continue;
    if (seen.add('$lat,$lng')) {
      pins.add(
        RecentSitePin(
          siteName: summary.siteName,
          latitude: lat,
          longitude: lng,
        ),
      );
    }
  }
  return pins;
});

/// This year vs last year, for the year-in-review card.
class YearInReview {
  final int year;
  final YearStats current;
  final YearStats previous;

  const YearInReview({
    required this.year,
    required this.current,
    required this.previous,
  });
}

/// This year vs last year. Null when both years are empty.
final yearInReviewProvider = FutureProvider<YearInReview?>((ref) async {
  ref.watch(statisticsVersionProvider);
  final repository = ref.watch(statisticsRepositoryProvider);
  final diverId = ref.watch(currentDiverIdProvider);
  final year = DateTime.now().year;
  final current = await repository.getYearStats(year, diverId: diverId);
  final previous = await repository.getYearStats(year - 1, diverId: diverId);
  if (current.diveCount == 0 && previous.diveCount == 0) return null;
  return YearInReview(year: year, current: current, previous: previous);
});

/// Dives from this month/day in prior years ("on this day").
final onThisDayProvider = FutureProvider<List<Dive>>((ref) async {
  final repository = ref.watch(diveRepositoryProvider);
  ref.invalidateSelfWhen(repository.watchDivesChanges());
  final currentDiverId = ref.watch(currentDiverIdProvider);
  final now = DateTime.now();
  final ids = await repository.getOnThisDayDiveIds(
    month: now.month,
    day: now.day,
    excludeYear: now.year,
    diverId: currentDiverId,
  );
  final dives = <Dive>[];
  for (final id in ids) {
    final dive = await repository.getDiveById(id);
    if (dive != null) dives.add(dive);
  }
  return dives;
});

/// Quick stats data class for dashboard
class DashboardQuickStats {
  final String? topBuddyName;
  final int? topBuddyDiveCount;
  final int countriesVisited;
  final int speciesDiscovered;

  const DashboardQuickStats({
    this.topBuddyName,
    this.topBuddyDiveCount,
    this.countriesVisited = 0,
    this.speciesDiscovered = 0,
  });
}

/// Quick stats provider for dashboard.
///
/// Deliberately UNFILTERED: the home dashboard has no filter UI, so it must
/// not inherit whatever filter is active on the (unrelated) Statistics tab.
/// [topBuddiesProvider], [countriesVisitedProvider], and
/// [uniqueSpeciesCountProvider] themselves stay filter-aware -- they also
/// back the Statistics Social/Geographic/Marine-Life pages -- so this reads
/// the shared repository directly instead of watching those providers, and
/// re-implements their diver scoping (but not their filter scoping).
/// [statisticsVersionProvider] is watched explicitly to preserve the
/// dive-mutation reactivity that used to arrive transitively through those
/// three providers.
final dashboardQuickStatsProvider = FutureProvider<DashboardQuickStats>((
  ref,
) async {
  ref.watch(statisticsVersionProvider);
  final repository = ref.watch(statisticsRepositoryProvider);
  final diverId = ref.watch(currentDiverIdProvider);

  // Get top buddy
  final topBuddies = await repository.getTopBuddies(diverId: diverId);
  final topBuddy = topBuddies.isNotEmpty ? topBuddies.first : null;

  // Get countries visited
  final countries = await repository.getCountriesVisited(diverId: diverId);

  // Get species count
  final speciesCount = await repository.getUniqueSpeciesCount(diverId: diverId);

  return DashboardQuickStats(
    topBuddyName: topBuddy?.name,
    topBuddyDiveCount: topBuddy?.count,
    countriesVisited: countries.length,
    speciesDiscovered: speciesCount,
  );
});
