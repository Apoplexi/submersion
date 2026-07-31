import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/tide/entities/tide_extremes.dart';
import 'package:submersion/features/tides/presentation/widgets/tide_times_table.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

void main() {
  testWidgets(
    'renders wall-clock-as-UTC tide times without a device-local shift (#222)',
    (tester) async {
      // Dive timestamps are stored wall-clock-as-UTC: the digits the diver
      // saw, flagged UTC. Formatting must print them verbatim; .toLocal()
      // shifts them by the MACHINE's UTC offset (the reported -7h in PDT).
      // On a UTC machine this test passes either way; on any other timezone
      // the pre-fix code renders a shifted time and this fails.
      final extremes = [
        TideExtreme(
          type: TideExtremeType.high,
          time: DateTime.utc(2026, 1, 15, 10, 30),
          heightMeters: 1.2,
        ),
        TideExtreme(
          type: TideExtremeType.low,
          time: DateTime.utc(2026, 1, 15, 16, 45),
          heightMeters: 0.3,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: TideTimesTable(
              extremes: extremes,
              now: DateTime.utc(2026, 1, 15, 9),
              showPast: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('10:30'), findsWidgets);
      expect(find.textContaining('16:45'), findsWidgets);
    },
  );
}
