import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dive_3d/application/spatial_providers.dart';
import 'package:submersion/features/dive_3d/domain/spatial/reckoned_path.dart';
import 'package:submersion/features/dive_3d/domain/spatial/spatial_geometry_service.dart';
import 'package:submersion/features/dive_3d/presentation/pages/spatial_site_page.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

ReckonedPath _path() => const ReckonedPath(
  points: [
    ReckonedPoint(east: 0, north: 0, depth: 5, timeSeconds: 0),
    ReckonedPoint(east: 40, north: 20, depth: 18, timeSeconds: 600),
  ],
  reconstructed: true,
  minEast: 0,
  maxEast: 40,
  minNorth: 0,
  maxNorth: 20,
  maxDepth: 18,
  durationSeconds: 600,
);

Widget page(SpatialSceneResult? result) => ProviderScope(
  overrides: [spatialGeometryProvider.overrideWith((ref, id) async => result)],
  child: const MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: SpatialSitePage(diveId: 'd1'),
  ),
);

void main() {
  final synthesized = SpatialSceneResult(
    scene: const SpatialGeometryService().build(_path(), siteMaxDepth: 30),
  );
  final real = SpatialSceneResult(
    scene: const SpatialGeometryService().build(_path(), siteMaxDepth: 30),
    bathymetrySourceId: 'gmrt',
    bathymetryResolutionMeters: 61,
  );

  testWidgets('real terrain shows the provenance chip, not synthesized', (
    tester,
  ) async {
    await tester.pumpWidget(page(real));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('GMRT'), findsOneWidget);
    expect(find.text('Synthesized seafloor'), findsNothing);
    expect(find.text('Estimated path (dead reckoning)'), findsOneWidget);
  });

  testWidgets('fallback shows the synthesized chip', (tester) async {
    await tester.pumpWidget(page(synthesized));
    await tester.pump();
    await tester.pump();
    expect(find.text('Synthesized seafloor'), findsOneWidget);
    expect(find.textContaining('GMRT'), findsNothing);
  });

  testWidgets('no path renders the message, never a spinner', (tester) async {
    await tester.pumpWidget(page(null));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('Not enough data to reconstruct the dive path'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
