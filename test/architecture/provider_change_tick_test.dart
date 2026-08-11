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
  'lib/features/certifications/presentation/providers/certification_providers.dart::certificationByIdProvider',
  'lib/features/certifications/presentation/providers/certification_providers.dart::certificationSearchProvider',
  'lib/features/certifications/presentation/providers/certification_providers.dart::certificationsByAgencyProvider',
  'lib/features/certifications/presentation/providers/certification_providers.dart::expiredCertificationsProvider',
  'lib/features/certifications/presentation/providers/certification_providers.dart::expiringCertificationsProvider',
  'lib/features/dive_centers/presentation/providers/dive_center_providers.dart::diveCenterByIdProvider',
  'lib/features/dive_centers/presentation/providers/dive_center_providers.dart::diveCenterCountriesProvider',
  'lib/features/dive_centers/presentation/providers/dive_center_providers.dart::diveCenterSearchProvider',
  'lib/features/dive_centers/presentation/providers/dive_center_providers.dart::diveCentersByCountryProvider',
  'lib/features/dive_centers/presentation/providers/dive_center_providers.dart::diveCentersWithCoordinatesProvider',
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
  'lib/features/settings/presentation/providers/settings_providers.dart::shareByDefaultProvider',
  'lib/features/tags/presentation/providers/tag_providers.dart::tagProvider',
  'lib/features/tags/presentation/providers/tag_providers.dart::tagSearchProvider',
  'lib/features/tags/presentation/providers/tag_providers.dart::tagsForDiveProvider',
  'lib/features/universal_import/presentation/providers/csv_preset_providers.dart::userCsvPresetsProvider',
};
