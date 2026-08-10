import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media/presentation/providers/site_media_providers.dart';
import 'package:submersion/features/media/presentation/widgets/site_media_section.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

import '../../../../helpers/mock_providers.dart';

void main() {
  Future<Widget> host({
    VoidCallback? onPhotos,
    VoidCallback? onDoc,
    Map<Dive, List<MediaItem>> divePhotos = const {},
  }) async {
    final base = await getBaseOverrides();
    return ProviderScope(
      overrides: [
        ...base,
        mediaForSiteProvider(
          'site-1',
        ).overrideWith((ref) async => const <MediaItem>[]),
        mediaFromDivesAtSiteProvider(
          'site-1',
        ).overrideWith((ref) async => divePhotos),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SiteMediaSection(
              siteId: 'site-1',
              onAddPhotosPressed: onPhotos,
              onAddDocumentPressed: onDoc,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('empty state renders site empty message', (tester) async {
    await tester.pumpWidget(await host(onPhotos: () {}, onDoc: () {}));
    await tester.pumpAndSettle();
    expect(
      find.text('No maps, photos, or documents attached to this site'),
      findsOneWidget,
    );
  });

  testWidgets('add menu exposes photos and document actions', (tester) async {
    var photos = 0;
    var docs = 0;
    await tester.pumpWidget(
      await host(onPhotos: () => photos++, onDoc: () => docs++),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_photo_alternate));
    await tester.pumpAndSettle();
    expect(find.text('Add photos or videos'), findsOneWidget);
    await tester.tap(find.text('Add document'));
    await tester.pumpAndSettle();
    expect(docs, 1);
    expect(photos, 0);
  });

  testWidgets('dive photos group hidden when no dives have media', (
    tester,
  ) async {
    await tester.pumpWidget(await host(onPhotos: () {}, onDoc: () {}));
    await tester.pumpAndSettle();
    expect(find.byType(ExpansionTile), findsNothing);
  });

  testWidgets('dive photos group shows collapsed header with count', (
    tester,
  ) async {
    final dive = Dive(id: 'dive-1', dateTime: DateTime(2026, 3, 1));
    final photo = MediaItem(
      id: 'm1',
      diveId: 'dive-1',
      mediaType: MediaType.photo,
      takenAt: DateTime(2026, 3, 1),
      createdAt: DateTime(2026, 3, 1),
      updatedAt: DateTime(2026, 3, 1),
    );
    await tester.pumpWidget(
      await host(
        onPhotos: () {},
        onDoc: () {},
        divePhotos: {
          dive: [photo],
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Photos from dives here (1)'), findsOneWidget);
    // Collapsed by default: no grid tiles rendered.
    expect(find.byType(GridView), findsNothing);
  });
}
