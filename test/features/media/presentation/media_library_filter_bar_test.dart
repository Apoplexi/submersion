import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/dive_sites/domain/entities/dive_site.dart';
import 'package:submersion/features/dive_sites/presentation/providers/site_providers.dart';
import 'package:submersion/features/media/domain/entities/media_library_filter.dart';
import 'package:submersion/features/media/presentation/providers/media_library_providers.dart';
import 'package:submersion/features/media/presentation/widgets/media_library_filter_bar.dart';
import 'package:submersion/features/trips/domain/entities/trip.dart';
import 'package:submersion/features/trips/presentation/providers/trip_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

void main() {
  const site = DiveSite(id: 'site-1', name: 'Blue Hole');
  final trip = Trip(
    id: 'trip-1',
    name: 'Red Sea 2026',
    startDate: DateTime(2026, 6, 1),
    endDate: DateTime(2026, 6, 14),
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  Widget host() {
    return ProviderScope(
      overrides: [
        sitesProvider.overrideWith((ref) async => [site]),
        allTripsProvider.overrideWith((ref) async => [trip]),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: MediaLibraryFilterBar()),
      ),
    );
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(MediaLibraryFilterBar)),
      );

  testWidgets('site chip opens picker and writes siteId to the filter', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Site'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blue Hole'));
    await tester.pumpAndSettle();

    expect(
      containerOf(tester).read(mediaLibraryFilterProvider).siteId,
      'site-1',
    );
    // The chip now shows the chosen site name.
    expect(find.text('Blue Hole'), findsOneWidget);
  });

  testWidgets('trip chip opens picker and writes tripId to the filter', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Trip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Red Sea 2026'));
    await tester.pumpAndSettle();

    expect(
      containerOf(tester).read(mediaLibraryFilterProvider).tripId,
      'trip-1',
    );
  });

  testWidgets('clearing an active chip resets just that field', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Site'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Blue Hole'));
    await tester.pumpAndSettle();

    // The active chip renders a per-chip clear (delete) affordance.
    await tester.tap(find.byIcon(Icons.clear).first);
    await tester.pumpAndSettle();
    expect(containerOf(tester).read(mediaLibraryFilterProvider).siteId, isNull);
  });

  testWidgets('clear-filters chip appears when filtered and resets all', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('Clear filters'), findsNothing);

    await tester.tap(find.text('Trip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Red Sea 2026'));
    await tester.pumpAndSettle();
    expect(find.text('Clear filters'), findsOneWidget);

    await tester.ensureVisible(find.text('Clear filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(
      containerOf(tester).read(mediaLibraryFilterProvider),
      MediaLibraryFilter.none,
    );
  });
}
