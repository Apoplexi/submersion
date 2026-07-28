import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/local_cache_database.dart';
import 'package:submersion/core/services/local_cache_database_service.dart';
import 'package:submersion/features/bathymetry/application/bathymetry_providers.dart';
import 'package:submersion/features/bathymetry/data/bathymetry_repository.dart';
import 'package:submersion/features/dive_sites/domain/entities/dive_site.dart';

void main() {
  tearDown(() => LocalCacheDatabaseService.instance.resetForTesting());

  test('repository provider is null when the cache DB is uninitialized', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(bathymetryRepositoryProvider), isNull);
  });

  test('repository provider builds once the cache DB exists', () {
    final db = LocalCacheDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    LocalCacheDatabaseService.instance.setTestDatabase(db);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(
      container.read(bathymetryRepositoryProvider),
      isA<BathymetryRepository>(),
    );
  });

  test(
    'grid provider yields null (not an error) without a repository',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final grid = await container.read(
        bathymetryGridProvider(
          BathymetryRepository.quantize(const GeoPoint(12.16, -68.29)),
        ).future,
      );
      expect(grid, isNull);
    },
  );
}
