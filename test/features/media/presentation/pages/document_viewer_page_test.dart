import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:submersion/features/media/data/services/asset_resolution_service.dart';
import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media/presentation/pages/document_viewer_page.dart';
import 'package:submersion/features/media/presentation/providers/resolved_asset_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

MediaItem _doc({String? originDeviceId}) => MediaItem(
  id: 'doc-1',
  siteId: 'site-1',
  mediaType: MediaType.document,
  originalFilename: 'reef-map.pdf',
  originDeviceId: originDeviceId,
  takenAt: DateTime(2026),
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Widget _host(MediaItem item) => ProviderScope(
  overrides: [
    resolvedFullResolutionProvider(item).overrideWith(
      (ref) async =>
          const ResolvedAssetResult(status: ResolutionStatus.unavailable),
    ),
  ],
  child: MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: DocumentViewerPage(item: item),
  ),
);

void main() {
  testWidgets('unavailable document shows the unavailable state', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_doc()));
    await tester.pumpAndSettle();
    expect(find.text('reef-map.pdf'), findsOneWidget); // app bar title
    expect(
      find.text('This document is not available on this device'),
      findsOneWidget,
    );
    // No origin device known: the hint stays hidden.
    expect(find.textContaining('added from'), findsNothing);
  });

  testWidgets('origin-device hint shown when originDeviceId present', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_doc(originDeviceId: 'device-2')));
    await tester.pumpAndSettle();
    expect(find.textContaining('added from'), findsOneWidget);
  });
}
