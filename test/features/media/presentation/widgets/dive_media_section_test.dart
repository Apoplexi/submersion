import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media/presentation/providers/media_providers.dart';
import 'package:submersion/features/media/presentation/widgets/dive_media_section.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

import '../../../../helpers/mock_providers.dart';

void main() {
  test('showInOsFileManagerLabel returns OS-appropriate label', () {
    final label = showInOsFileManagerLabel();
    if (Platform.isMacOS) {
      expect(label, 'Show in Finder');
    } else if (Platform.isWindows) {
      expect(label, 'Show in Explorer');
    } else {
      // Linux / iOS / Android fallback.
      expect(label, 'Show in Files');
    }
  });

  Future<Widget> host({
    VoidCallback? onAdd,
    VoidCallback? onAddDocument,
  }) async {
    final base = await getBaseOverrides();
    return ProviderScope(
      overrides: [
        ...base,
        mediaForDiveProvider(
          'dive-1',
        ).overrideWith((ref) async => const <MediaItem>[]),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: DiveMediaSection(
              diveId: 'dive-1',
              onAddPressed: onAdd,
              onAddDocumentPressed: onAddDocument,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('add menu shows document action when callback provided', (
    tester,
  ) async {
    var photos = 0;
    var docs = 0;
    await tester.pumpWidget(
      await host(onAdd: () => photos++, onAddDocument: () => docs++),
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

  testWidgets('plain add button preserved when no document callback', (
    tester,
  ) async {
    var photos = 0;
    await tester.pumpWidget(await host(onAdd: () => photos++));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_photo_alternate));
    await tester.pumpAndSettle();
    expect(photos, 1); // fired directly, no menu
    expect(find.text('Add document'), findsNothing);
  });
}
