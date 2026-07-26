import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/dive_sites/domain/entities/dive_site.dart';
import 'package:submersion/features/reef/domain/entities/nearby_species.dart';
import 'package:submersion/features/reef/domain/entities/reef_data_status.dart';
import 'package:submersion/features/reef/domain/entities/reef_snapshot.dart';
import 'package:submersion/features/reef/presentation/providers/reef_providers.dart';
import 'package:submersion/features/reef/presentation/widgets/nearby_species_tier.dart';

ReefSnapshot _snapshot(ReefPart<NearbySpecies> species) => ReefSnapshot(
  habitat: const ReefPart.empty(),
  health: const ReefPart.empty(),
  protection: const ReefPart.empty(),
  species: species,
);

Widget _harness(GeoPoint location, ReefSnapshot snapshot) => ProviderScope(
  overrides: [
    reefSnapshotProvider(location).overrideWith((ref) async => snapshot),
  ],
  child: MaterialApp(
    home: Scaffold(
      body: NearbySpeciesTier(siteId: 'site-1', location: location),
    ),
  ),
);

void main() {
  testWidgets('renders matched species above unmatched scientific names', (
    tester,
  ) async {
    const location = GeoPoint(12.16, -68.28);
    final snapshot = _snapshot(
      const ReefPart.ok(
        NearbySpecies(
          matched: [
            MatchedNearbySpecies(
              speciesId: 'sp_whale_shark',
              occurrenceCount: 42,
            ),
          ],
          unmatchedNames: ['Aplysina archeri'],
        ),
      ),
    );

    await tester.pumpWidget(_harness(location, snapshot));
    await tester.pumpAndSettle();

    expect(find.textContaining('Recorded nearby'), findsOneWidget);
    expect(find.textContaining('Aplysina archeri'), findsOneWidget);
  });

  testWidgets('renders nothing when no species were recorded nearby', (
    tester,
  ) async {
    const location = GeoPoint(1, 2);
    await tester.pumpWidget(
      _harness(location, _snapshot(const ReefPart.empty())),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ListTile), findsNothing);
    expect(find.textContaining('Recorded nearby'), findsNothing);
  });

  testWidgets('renders nothing when the species provider is unavailable', (
    tester,
  ) async {
    const location = GeoPoint(3, 4);
    await tester.pumpWidget(
      _harness(location, _snapshot(const ReefPart.unavailable())),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Recorded nearby'), findsNothing);
  });
}
