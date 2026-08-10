import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media/presentation/pages/site_media_viewer_page.dart';
import 'package:submersion/features/media/presentation/providers/site_media_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

void main() {
  testWidgets('shows empty message when site has no photos', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaForSiteProvider(
            'site-1',
          ).overrideWith((ref) async => const <MediaItem>[]),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SiteMediaViewerPage(
            siteId: 'site-1',
            initialMediaId: 'x',
            scope: SiteViewerScope.attachments,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No photos available'), findsOneWidget);
  });

  testWidgets('documents are filtered out of the pager list', (tester) async {
    final doc = MediaItem(
      id: 'doc-1',
      siteId: 'site-1',
      mediaType: MediaType.document,
      originalFilename: 'map.pdf',
      takenAt: DateTime(2026),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          mediaForSiteProvider('site-1').overrideWith((ref) async => [doc]),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SiteMediaViewerPage(
            siteId: 'site-1',
            initialMediaId: 'doc-1',
            scope: SiteViewerScope.attachments,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // A document-only attachment list leaves the pager empty.
    expect(find.text('No photos available'), findsOneWidget);
  });
}
