import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/dive_log/domain/entities/profile_series_revision.dart';
import 'package:submersion/features/dive_log/presentation/pages/profile_editor_page.dart';
import 'package:submersion/features/dive_log/presentation/providers/dive_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

import '../../../../helpers/mock_providers.dart';

void main() {
  Dive diveWithProfile({required List<DiveProfilePoint> profile}) =>
      createTestDiveWithBottomTime().copyWith(profile: profile);

  group('ProfileEditorPage Revision Selector UI', () {
    testWidgets(
      'revision selector is positioned in AppBar next to Edit Profile title',
      (tester) async {
        final dive = diveWithProfile(
          profile: [
            const DiveProfilePoint(timestamp: 0, depth: 0.0),
            const DiveProfilePoint(timestamp: 60, depth: 12.0),
          ],
        );

        final base = await getBaseOverrides();
        final revisions = [
          ProfileSeriesRevision(
            seriesId: 'series-1',
            diveId: dive.id,
            parentSeriesId: null,
            rootSeriesId: 'series-1',
            contentHash: 'hash-1',
            revisionKind: 'create',
            createdAt: 1000,
            isActive: true,
          ),
        ];

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              ...base,
              diveProvider(dive.id).overrideWith((ref) async => dive),
              profileSeriesHistoryProvider(
                dive.id,
              ).overrideWith((ref) async => revisions),
            ],
            child: MaterialApp(
              locale: const Locale('en'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: ProfileEditorPage(diveId: dive.id),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        // Find AppBar
        final appBar = find.byType(AppBar);
        expect(appBar, findsOneWidget);

        // Verify "Edit Profile" title is in AppBar
        expect(
          find.descendant(of: appBar, matching: find.text('Edit Profile')),
          findsOneWidget,
        );

        // Verify history icon is in AppBar (right of title)
        expect(
          find.descendant(of: appBar, matching: find.byIcon(Icons.history)),
          findsOneWidget,
        );
      },
    );

    testWidgets('revision selector hides when no history available', (
      tester,
    ) async {
      final dive = diveWithProfile(
        profile: [
          const DiveProfilePoint(timestamp: 0, depth: 0.0),
          const DiveProfilePoint(timestamp: 60, depth: 12.0),
        ],
      );

      final base = await getBaseOverrides();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...base,
            diveProvider(dive.id).overrideWith((ref) async => dive),
            profileSeriesHistoryProvider(
              dive.id,
            ).overrideWith((ref) async => const <ProfileSeriesRevision>[]),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ProfileEditorPage(diveId: dive.id),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      // Verify history icon is not shown
      expect(find.byIcon(Icons.history), findsNothing);
    });
  });
}
