import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/dive_log/presentation/widgets/dive_profile_chart.dart';
import 'package:submersion/features/dive_log/presentation/widgets/profile_highlight_range.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

import '../../../../helpers/mock_providers.dart';

void main() {
  // 10 points, 30 s apart: x axis spans 0..270 s.
  final profile = List.generate(
    10,
    (i) => DiveProfilePoint(
      timestamp: i * 30,
      depth: i < 5 ? i * 3.0 : (10 - i) * 3.0,
    ),
  );

  Future<void> pumpChart(
    WidgetTester tester, {
    ProfileHighlightRange? highlightRange,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith((ref) => MockSettingsNotifier()),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 300,
              child: DiveProfileChart(
                profile: profile,
                highlightRange: highlightRange,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  LineChartData chartData(WidgetTester tester) =>
      tester.widget<LineChart>(find.byType(LineChart).first).data;

  testWidgets('no highlight renders no annotations or highlight lines', (
    tester,
  ) async {
    await pumpChart(tester);
    final data = chartData(tester);
    expect(data.rangeAnnotations.verticalRangeAnnotations, isEmpty);
    expect(data.extraLinesData.verticalLines, isEmpty);
  });

  testWidgets('a range highlight renders a band with two edge lines', (
    tester,
  ) async {
    await pumpChart(
      tester,
      highlightRange: const ProfileHighlightRange(
        startTimestamp: 60,
        endTimestamp: 120,
        color: Colors.teal,
      ),
    );
    final data = chartData(tester);

    final annotations = data.rangeAnnotations.verticalRangeAnnotations;
    expect(annotations, hasLength(1));
    expect(annotations.single.x1, 60);
    expect(annotations.single.x2, 120);

    final lines = data.extraLinesData.verticalLines;
    expect(lines, hasLength(2));
    expect(lines.map((l) => l.x), containsAll([60.0, 120.0]));
  });

  testWidgets('an instant highlight renders a single dashed cursor, no band', (
    tester,
  ) async {
    await pumpChart(
      tester,
      highlightRange: const ProfileHighlightRange(
        startTimestamp: 90,
        endTimestamp: 90,
        color: Colors.teal,
      ),
    );
    final data = chartData(tester);

    expect(data.rangeAnnotations.verticalRangeAnnotations, isEmpty);
    final lines = data.extraLinesData.verticalLines;
    expect(lines, hasLength(1));
    expect(lines.single.x, 90);
    expect(lines.single.dashArray, isNotNull);
  });
}
