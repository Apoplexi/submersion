import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:submersion/core/services/local_cache_database_service.dart';
import 'package:submersion/features/bathymetry/data/bathymetry_repository.dart';
import 'package:submersion/features/bathymetry/data/bathymetry_resolver.dart';
import 'package:submersion/features/bathymetry/data/sources/emodnet_source.dart';
import 'package:submersion/features/bathymetry/data/sources/etopo_erddap_source.dart';
import 'package:submersion/features/bathymetry/data/sources/gmrt_source.dart';
import 'package:submersion/features/bathymetry/domain/bathymetry_grid.dart';
import 'package:submersion/features/dive_sites/domain/entities/dive_site.dart';

/// Null when the local cache database is not initialized (early startup,
/// plain widget tests): bathymetry silently degrades to synthesized
/// terrain rather than erroring.
final bathymetryRepositoryProvider = Provider<BathymetryRepository?>((ref) {
  try {
    final db = LocalCacheDatabaseService.instance.database;
    return BathymetryRepository(
      db: db,
      resolver: BathymetryResolver(
        // Tier order: regional survey data first, then global GMRT, then
        // the coarse public-domain fallback.
        sources: [EmodnetSource(), GmrtSource(), EtopoErddapSource()],
      ),
    );
  } on StateError {
    return null;
  }
});

/// The cached/fetched grid for a QUANTIZED coordinate cell. Callers must
/// key the family with [BathymetryRepository.quantize] so every coordinate
/// in a cell shares one entry. Never errors: null means no real terrain.
final bathymetryGridProvider =
    FutureProvider.family<BathymetryGrid?, ({double lat, double lon})>((
      ref,
      cell,
    ) async {
      final repo = ref.watch(bathymetryRepositoryProvider);
      if (repo == null) return null;
      return repo.getGrid(GeoPoint(cell.lat, cell.lon));
    });
