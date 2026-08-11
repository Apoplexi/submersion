import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'provider_tick_scanner.dart';

/// Guards the project rule that a provider reading a table must self-invalidate
/// on that table's change tick (issue #974).
///
/// Writes reach the database through paths that bypass every notifier:
/// `DiveRepository.bulkDeleteDives` (used by `dive_merge_service` and
/// `dive_consolidation_service`), sync pulls applying remote deletions, and
/// repository-level bulk edits. None of them call `ref.invalidate` on a
/// provider's behalf, so a provider that does not subscribe serves a stale
/// cache until something unrelated happens to invalidate it.
///
/// This test does NOT check WHICH tick a provider subscribes to. When fixing a
/// failure, do not reach for the nearest tick: a junction read such as
/// `BuddyRepository.getDiveIdsForBuddy` lives on the buddy repository but goes
/// stale on a DIVES cascade delete, so it needs `watchDivesChanges()`.
///
/// Known limitation: this checks provider DECLARATIONS, not `Notifier` classes.
/// `DiveListNotifier`, `PaginatedDiveListNotifier`, and `TripListNotifier`
/// subscribe correctly with raw `.listen()` + `ref.onDispose` and are skipped
/// here, because their provider bodies construct a class rather than calling
/// repository methods.
void main() {
  final dartFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart') && !f.path.endsWith('.g.dart'))
      .toList();

  final result = scanForTickViolations(
    repositoryFiles: dartFiles
        .where((f) => f.path.contains('/data/repositories/'))
        .toList(),
    providerFiles: dartFiles,
    relativize: (path) => path.replaceFirst('${Directory.current.path}/', ''),
  );

  test('the scan found the repository, so it cannot pass vacuously', () {
    expect(dartFiles.length, greaterThan(1000));
    expect(result.tickDeclarationCount, greaterThanOrEqualTo(27));
    expect(result.repositoryReadingProviders, greaterThanOrEqualTo(200));
  });

  test('no provider reads a repository without subscribing to a tick', () {
    final actual = result.violations.map((v) => v.key).toSet();

    final unexpected = result.violations
        .where((v) => !_knownViolations.contains(v.key))
        .toList();
    expect(
      unexpected,
      isEmpty,
      reason:
          'New change-tick violations. Each provider below calls a repository '
          'method but never subscribes to a change tick, so it will serve a '
          'stale cache after a merge, a bulk delete, or a sync pull.\n\n'
          'Fix by adding, inside the provider body:\n'
          '  ref.invalidateSelfWhen(repository.watchXChanges());\n\n'
          'Pick the tick for the table the query actually READS, which is not '
          'always the tick owned by the repository the method lives on. A '
          'junction read such as BuddyRepository.getDiveIdsForBuddy needs the '
          'DIVES tick, because it goes stale on a cascade delete that never '
          'writes the buddies table.\n\n'
          'If the provider genuinely cannot go stale (a short-lived autoDispose '
          'read fresh at action time), mark it:\n'
          '  // no-tick: <why a stale cache can never render>\n\n'
          '${unexpected.join('\n')}',
    );

    final fixed = _knownViolations.difference(actual);
    expect(
      fixed,
      isEmpty,
      reason:
          'These providers were fixed but are still listed in '
          '_knownViolations. Delete them from that set:\n'
          '${(fixed.toList()..sort()).join('\n')}',
    );
  });
}

/// Violations present when this test was introduced, being burned down under
/// issue #974. The set is asserted for EXACT equality against the scan, so it
/// only ever gets smaller: a new violation fails the build, and a fix that
/// leaves a stale entry here fails too. When it reaches zero, delete it along
/// with the two references above.
const _knownViolations = <String>{
  'lib/features/bathymetry/application/bathymetry_providers.dart::bathymetryGridProvider',
  'lib/features/buddies/presentation/providers/buddy_providers.dart::buddyByIdProvider',
  'lib/features/buddies/presentation/providers/buddy_providers.dart::buddySearchProvider',
  'lib/features/buddies/presentation/providers/buddy_providers.dart::buddyStatsProvider',
  'lib/features/buddies/presentation/providers/buddy_providers.dart::diveIdsForBuddyProvider',
  'lib/features/certifications/presentation/providers/certification_providers.dart::certificationByIdProvider',
  'lib/features/certifications/presentation/providers/certification_providers.dart::certificationSearchProvider',
  'lib/features/certifications/presentation/providers/certification_providers.dart::certificationsByAgencyProvider',
  'lib/features/certifications/presentation/providers/certification_providers.dart::expiredCertificationsProvider',
  'lib/features/certifications/presentation/providers/certification_providers.dart::expiringCertificationsProvider',
  'lib/features/courses/presentation/providers/course_providers.dart::completedCoursesProvider',
  'lib/features/courses/presentation/providers/course_providers.dart::courseByIdProvider',
  'lib/features/courses/presentation/providers/course_providers.dart::courseDiveCountProvider',
  'lib/features/courses/presentation/providers/course_providers.dart::courseDivesProvider',
  'lib/features/courses/presentation/providers/course_providers.dart::courseForCertificationProvider',
  'lib/features/courses/presentation/providers/course_providers.dart::courseSearchProvider',
  'lib/features/courses/presentation/providers/course_providers.dart::coursesByAgencyProvider',
  'lib/features/courses/presentation/providers/course_providers.dart::inProgressCoursesProvider',
  'lib/features/cylinder_configs/presentation/providers/cylinder_config_providers.dart::cylinderConfigProvider',
  'lib/features/cylinder_configs/presentation/providers/cylinder_config_providers.dart::cylinderConfigsForEquipmentProvider',
  'lib/features/cylinder_configs/presentation/providers/cylinder_config_providers.dart::cylinderConfigsProvider',
  'lib/features/dashboard/presentation/providers/dashboard_providers.dart::dashboardQuickStatsProvider',
  'lib/features/dashboard/presentation/providers/dashboard_providers.dart::yearInReviewProvider',
  'lib/features/dive_centers/presentation/providers/dive_center_providers.dart::diveCenterByIdProvider',
  'lib/features/dive_centers/presentation/providers/dive_center_providers.dart::diveCenterCountriesProvider',
  'lib/features/dive_centers/presentation/providers/dive_center_providers.dart::diveCenterSearchProvider',
  'lib/features/dive_centers/presentation/providers/dive_center_providers.dart::diveCentersByCountryProvider',
  'lib/features/dive_centers/presentation/providers/dive_center_providers.dart::diveCentersWithCoordinatesProvider',
  'lib/features/dive_computer/presentation/providers/download_providers.dart::computerDiveIdsProvider',
  'lib/features/dive_computer/presentation/providers/download_providers.dart::firstSyncCutoffDefaultProvider',
  'lib/features/dive_log/presentation/providers/dive_computer_providers.dart::allDiveComputersProvider',
  'lib/features/dive_log/presentation/providers/dive_computer_providers.dart::diveComputerByIdProvider',
  'lib/features/dive_log/presentation/providers/dive_computer_providers.dart::favoriteDiveComputerProvider',
  'lib/features/dive_log/presentation/providers/dive_computer_providers.dart::primaryComputerIdProvider',
  'lib/features/dive_log/presentation/providers/dive_providers.dart::customFieldKeySuggestionsProvider',
  'lib/features/dive_log/presentation/providers/dive_providers.dart::diveNumberingInfoProvider',
  'lib/features/dive_log/presentation/providers/dive_providers.dart::diveRecordsProvider',
  'lib/features/dive_log/presentation/providers/dive_providers.dart::diveSearchProvider',
  'lib/features/dive_log/presentation/providers/dive_providers.dart::nextDiveNumberProvider',
  'lib/features/dive_log/presentation/providers/dive_providers.dart::orderedDiveIdsProvider',
  'lib/features/dive_log/presentation/providers/profile_analysis_provider.dart::diveComputerEventsProvider',
  'lib/features/dive_log/presentation/providers/profile_analysis_provider.dart::weeklyOtuProvider',
  'lib/features/dive_log/presentation/providers/view_config_providers.dart::tablePresetsProvider',
  'lib/features/dive_sites/presentation/providers/site_providers.dart::siteProvider',
  'lib/features/dive_sites/presentation/providers/site_providers.dart::siteSearchProvider',
  'lib/features/dive_types/presentation/providers/dive_type_providers.dart::builtInDiveTypesProvider',
  'lib/features/dive_types/presentation/providers/dive_type_providers.dart::customDiveTypesProvider',
  'lib/features/dive_types/presentation/providers/dive_type_providers.dart::diveTypeProvider',
  'lib/features/dive_types/presentation/providers/dive_type_providers.dart::diveTypeStatisticsProvider',
  'lib/features/divers/presentation/providers/diver_providers.dart::currentDiverProvider',
  'lib/features/divers/presentation/providers/diver_providers.dart::diverByIdProvider',
  'lib/features/divers/presentation/providers/diver_providers.dart::diverDiveCountProvider',
  'lib/features/divers/presentation/providers/diver_providers.dart::diverTotalBottomTimeProvider',
  'lib/features/divers/presentation/providers/diver_providers.dart::validatedCurrentDiverIdProvider',
  'lib/features/equipment/presentation/providers/equipment_providers.dart::activeEquipmentProvider',
  'lib/features/equipment/presentation/providers/equipment_providers.dart::equipmentDiveCountProvider',
  'lib/features/equipment/presentation/providers/equipment_providers.dart::equipmentItemProvider',
  'lib/features/equipment/presentation/providers/equipment_providers.dart::equipmentSearchProvider',
  'lib/features/equipment/presentation/providers/equipment_providers.dart::equipmentTripCountProvider',
  'lib/features/equipment/presentation/providers/equipment_providers.dart::equipmentTripIdsProvider',
  'lib/features/equipment/presentation/providers/equipment_providers.dart::mostRecentServiceRecordProvider',
  'lib/features/equipment/presentation/providers/equipment_providers.dart::retiredEquipmentProvider',
  'lib/features/equipment/presentation/providers/equipment_providers.dart::serviceRecordByIdProvider',
  'lib/features/equipment/presentation/providers/equipment_providers.dart::serviceRecordCountProvider',
  'lib/features/equipment/presentation/providers/equipment_providers.dart::serviceRecordTotalCostProvider',
  'lib/features/equipment/presentation/providers/equipment_providers.dart::serviceRecordsForEquipmentProvider',
  'lib/features/equipment/presentation/providers/equipment_set_providers.dart::equipmentSetGeofencesProvider',
  'lib/features/equipment/presentation/providers/equipment_set_providers.dart::equipmentSetSelectionInputsProvider',
  'lib/features/gps_log/presentation/providers/gps_track_map_providers.dart::gpsTrackGeometryProvider',
  'lib/features/maps/presentation/providers/offline_map_providers.dart::cachedRegionByIdProvider',
  'lib/features/maps/presentation/providers/offline_map_providers.dart::cachedRegionsProvider',
  'lib/features/marine_life/presentation/providers/species_providers.dart::seedSpeciesProvider',
  'lib/features/marine_life/presentation/providers/species_providers.dart::siteExpectedSpeciesProvider',
  'lib/features/marine_life/presentation/providers/species_providers.dart::siteSpottedSpeciesProvider',
  'lib/features/marine_life/presentation/providers/species_providers.dart::speciesByCategoryProvider',
  'lib/features/marine_life/presentation/providers/species_providers.dart::speciesProvider',
  'lib/features/marine_life/presentation/providers/species_providers.dart::speciesSearchProvider',
  'lib/features/media/presentation/providers/media_providers.dart::allDivePhotoGpsProvider',
  'lib/features/media/presentation/providers/media_providers.dart::divePhotoGpsProvider',
  'lib/features/media/presentation/providers/media_providers.dart::mediaByIdProvider',
  'lib/features/media/presentation/providers/media_providers.dart::mediaCountForDiveProvider',
  'lib/features/media/presentation/providers/media_providers.dart::orphanedMediaProvider',
  'lib/features/media/presentation/providers/media_providers.dart::pendingSuggestionCountProvider',
  'lib/features/media_store/presentation/providers/media_store_providers.dart::mediaBadgeStateProvider',
  'lib/features/media_store/presentation/providers/media_store_providers.dart::mediaStoreRuntimeProvider',
  'lib/features/media_store/presentation/providers/media_store_providers.dart::mediaVerifyRunnerProvider',
  'lib/features/planner/presentation/pages/plan_compare_page.dart::planComparisonProvider',
  'lib/features/planner/presentation/providers/plan_canvas_providers.dart::loggedAverageSacProvider',
  'lib/features/settings/presentation/providers/settings_providers.dart::shareByDefaultProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::ascentDescentRatesProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::bestSitesForMarineLifeProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::bottomTimeTrendProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::countriesVisitedProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::cumulativeDiveCountProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::decoObligationStatsProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::depthProgressionTrendProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::diveTypeDistributionProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::divesByDayOfWeekProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::divesBySeasonProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::divesBySuitThicknessProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::divesByTimeOfDayProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::divesPerTripProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::divesPerYearProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::entryMethodDistributionProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::gasMixDistributionProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::mostCommonSightingsProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::mostUsedGearProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::regionsExploredProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::sacByTankRoleProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::sacRecordsProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::sacTrendProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::soloVsBuddyCountProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::speciesStatisticsProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::surfaceIntervalStatsProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::temperatureByMonthProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::timeAtDepthRangesProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::topBuddiesProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::topDiveCentersProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::uniqueSpeciesCountProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::visibilityDistributionProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::waterTypeDistributionProvider',
  'lib/features/statistics/presentation/providers/statistics_providers.dart::weightTrendProvider',
  'lib/features/tags/presentation/providers/tag_providers.dart::tagProvider',
  'lib/features/tags/presentation/providers/tag_providers.dart::tagSearchProvider',
  'lib/features/tags/presentation/providers/tag_providers.dart::tagsForDiveProvider',
  'lib/features/tank_presets/presentation/providers/tank_preset_providers.dart::customTankPresetsProvider',
  'lib/features/tank_presets/presentation/providers/tank_preset_providers.dart::tankPresetProvider',
  'lib/features/trips/presentation/providers/liveaboard_providers.dart::itineraryDaysProvider',
  'lib/features/trips/presentation/providers/liveaboard_providers.dart::liveaboardDetailsProvider',
  'lib/features/trips/presentation/providers/trip_providers.dart::_equipmentFilteredTripsProvider',
  'lib/features/trips/presentation/providers/trip_providers.dart::allTripsWithStatsProvider',
  'lib/features/trips/presentation/providers/trip_providers.dart::diveIdsForTripProvider',
  'lib/features/trips/presentation/providers/trip_providers.dart::divesForTripProvider',
  'lib/features/trips/presentation/providers/trip_providers.dart::tripByIdProvider',
  'lib/features/trips/presentation/providers/trip_providers.dart::tripForDateProvider',
  'lib/features/trips/presentation/providers/trip_providers.dart::tripSearchProvider',
  'lib/features/trips/presentation/providers/trip_providers.dart::tripWithStatsProvider',
  'lib/features/universal_import/presentation/providers/csv_preset_providers.dart::userCsvPresetsProvider',
};
