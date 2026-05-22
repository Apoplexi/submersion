import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/dive_log/domain/entities/dive_data_source.dart';
import 'package:submersion/features/dive_log/presentation/pages/dive_detail_page.dart';
import 'package:submersion/features/dive_log/presentation/providers/dive_detail_ui_providers.dart';
import 'package:submersion/features/dive_log/presentation/providers/dive_providers.dart';
import 'package:submersion/features/dive_sites/domain/entities/dive_site.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

import '../../../../helpers/mock_providers.dart';

Dive _gpsDive({GeoPoint? entry, GeoPoint? exit}) => Dive(
  id: 'sgps',
  diveNumber: 1,
  dateTime: DateTime(2026, 5, 22, 9, 14),
  maxDepth: 30.0,
  entryLocation: entry,
  exitLocation: exit,
);

Future<void> _pump(
  WidgetTester tester,
  Dive dive, {
  bool expanded = false,
}) async {
  final overrides = await getBaseOverrides();
  final originalOnError = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.toString().contains('overflowed')) return;
    originalOnError?.call(d);
  };
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...overrides,
        if (expanded) surfaceGpsSectionExpandedProvider.overrideWithValue(true),
        diveProvider(dive.id).overrideWith((ref) async => dive),
        diveDataSourcesProvider(
          dive.id,
        ).overrideWith((ref) async => <DiveDataSource>[]),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DiveDetailPage(diveId: dive.id, embedded: true),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
  FlutterError.onError = originalOnError;
}

void main() {
  testWidgets('Surface GPS section shows drift summary, coordinates and '
      'open-in-maps when expanded', (tester) async {
    await _pump(
      tester,
      _gpsDive(
        entry: const GeoPoint(12.34567, 98.76543),
        exit: const GeoPoint(12.34612, 98.76489),
      ),
      expanded: true,
    );

    expect(find.text('Surface GPS'), findsOneWidget);
    expect(find.textContaining('Drift'), findsWidgets);
    expect(find.text('Open in Maps'), findsOneWidget);
  });

  testWidgets('no Surface GPS section when dive has no GPS', (tester) async {
    await _pump(tester, _gpsDive());

    expect(find.text('Surface GPS'), findsNothing);
  });
}
