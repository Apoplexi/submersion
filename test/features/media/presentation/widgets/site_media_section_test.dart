import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:submersion/features/dive_log/domain/entities/dive.dart';
import 'package:submersion/features/media/data/repositories/media_repository.dart';
import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media/presentation/pages/site_media_viewer_page.dart';
import 'package:submersion/features/media/presentation/providers/site_media_providers.dart';
import 'package:submersion/features/media/presentation/widgets/media_grid.dart';
import 'package:submersion/features/media/presentation/widgets/site_media_section.dart';

// `Override` is not exported from flutter_riverpod's public barrel; the
// shared test helper re-types it for widget tests.
import '../../../../helpers/mock_providers.dart' show Override;
import '../support/media_widget_harness.dart';

/// Repository stub so the notifier under test never reaches the database.
///
/// [SiteMediaListNotifier]'s constructor eagerly loads the site's media;
/// widget tests have no `DatabaseService` behind it, so the load is served
/// from here instead of throwing on every construction.
class _StubMediaRepository extends MediaRepository {
  @override
  Future<List<MediaItem>> getMediaForSite(String siteId) async =>
      const <MediaItem>[];
}

/// Records the ids the section asks to unlink, and can fail on demand.
///
/// [deleteCalls] is owned by the test rather than the notifier: the provider
/// is lazy, so a flow that never unlinks never constructs one.
class _RecordingSiteMediaNotifier extends SiteMediaListNotifier {
  _RecordingSiteMediaNotifier(
    Ref ref, {
    required this.deleteCalls,
    this.failWith,
  }) : super(_StubMediaRepository(), ref, 'site-1');

  final List<List<String>> deleteCalls;
  final Object? failWith;

  @override
  Future<void> deleteMultipleMedia(List<String> ids) async {
    deleteCalls.add(List<String>.of(ids));
    if (failWith != null) throw failWith!;
  }
}

void main() {
  final photoA = testMediaItem(
    id: 'm1',
    siteId: 'site-1',
    originalFilename: 'entry.png',
    takenAt: DateTime(2026, 3, 1, 9),
  );
  final photoB = testMediaItem(
    id: 'm2',
    siteId: 'site-1',
    originalFilename: 'mooring.png',
    takenAt: DateTime(2026, 3, 1, 10),
  );

  /// Hosts [SiteMediaSection] for 'site-1' with the attachments provider
  /// resolved to [attachments] (or stuck loading / failing instead).
  Future<Widget> host({
    VoidCallback? onPhotos,
    VoidCallback? onDoc,
    void Function(MediaItem)? onOpenDocument,
    Map<Dive, List<MediaItem>> divePhotos = const {},
    List<MediaItem> attachments = const [],
    Future<List<MediaItem>>? pendingAttachments,
    Object? attachmentsError,
    List<Override> extraOverrides = const [],
  }) async {
    return mediaTestApp(
      overrides: [
        mediaForSiteProvider('site-1').overrideWith((ref) {
          if (pendingAttachments != null) return pendingAttachments;
          if (attachmentsError != null) throw attachmentsError;
          return attachments;
        }),
        mediaFromDivesAtSiteProvider(
          'site-1',
        ).overrideWith((ref) async => divePhotos),
        ...extraOverrides,
      ],
      home: Scaffold(
        body: SingleChildScrollView(
          child: SiteMediaSection(
            siteId: 'site-1',
            onAddPhotosPressed: onPhotos,
            onAddDocumentPressed: onDoc,
            onOpenDocument: onOpenDocument,
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

  testWidgets('add menu routes the photos entry to its own callback', (
    tester,
  ) async {
    var photos = 0;
    var docs = 0;
    await tester.pumpWidget(
      await host(onPhotos: () => photos++, onDoc: () => docs++),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_photo_alternate));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add photos or videos'));
    await tester.pumpAndSettle();
    expect(photos, 1);
    expect(docs, 0);
  });

  testWidgets('the add menu is hidden when neither action is wired', (
    tester,
  ) async {
    await tester.pumpWidget(await host());
    await tester.pumpAndSettle();
    expect(find.text('Site Media'), findsOneWidget);
    expect(find.byIcon(Icons.add_photo_alternate), findsNothing);
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

  group('attachments grid', () {
    testWidgets('renders one thumbnail tile per attachment', (tester) async {
      await tester.pumpWidget(await host(attachments: [photoA, photoB]));
      await tester.pumpAndSettle();

      expect(find.byType(MediaThumbnailTile), findsNWidgets(2));
      // The grid replaces the empty state entirely.
      expect(
        find.text('No maps, photos, or documents attached to this site'),
        findsNothing,
      );
      final tiles = tester
          .widgetList<MediaThumbnailTile>(find.byType(MediaThumbnailTile))
          .toList();
      expect(tiles.map((t) => t.item.id), ['m1', 'm2']);
      // Not in selection mode, so nothing is dimmed or checked.
      expect(tiles.every((t) => !t.isSelectionMode), isTrue);
      expect(find.byIcon(Icons.check), findsNothing);
    });

    testWidgets('tapping a photo tile opens the attachments viewer', (
      tester,
    ) async {
      await tester.pumpWidget(await host(attachments: [photoA, photoB]));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(MediaThumbnailTile).at(1));
      await tester.pumpAndSettle();

      expect(find.byType(SiteMediaViewerPage), findsOneWidget);
      final viewer = tester.widget<SiteMediaViewerPage>(
        find.byType(SiteMediaViewerPage),
      );
      expect(viewer.siteId, 'site-1');
      expect(viewer.initialMediaId, 'm2');
      expect(viewer.scope, SiteViewerScope.attachments);
    });

    testWidgets('tapping a document tile hands off instead of opening the '
        'viewer', (tester) async {
      final doc = testMediaItem(
        id: 'doc-1',
        siteId: 'site-1',
        mediaType: MediaType.document,
        originalFilename: 'site-map.pdf',
      );
      final opened = <MediaItem>[];
      await tester.pumpWidget(
        await host(attachments: [photoA, doc], onOpenDocument: opened.add),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(MediaThumbnailTile).at(1));
      await tester.pumpAndSettle();

      expect(opened.map((m) => m.id), ['doc-1']);
      expect(find.byType(SiteMediaViewerPage), findsNothing);
    });
  });

  group('selection mode', () {
    /// Long-presses the first attachment tile to enter selection mode.
    Future<void> enterSelection(WidgetTester tester) async {
      await tester.longPress(find.byType(MediaThumbnailTile).first);
      await tester.pumpAndSettle();
    }

    testWidgets('long-pressing a tile shows the selection header', (
      tester,
    ) async {
      await tester.pumpWidget(await host(attachments: [photoA, photoB]));
      await tester.pumpAndSettle();
      // Normal header before the long press.
      expect(find.text('Site Media'), findsOneWidget);

      await enterSelection(tester);

      expect(find.byType(MediaSelectionHeader), findsOneWidget);
      expect(find.text('1 selected'), findsOneWidget);
      // The normal header (and its add menu) yields to the selection header.
      expect(find.text('Site Media'), findsNothing);
      expect(find.byIcon(Icons.add_photo_alternate), findsNothing);
      // The anchor tile is the selected one.
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('select all extends the selection to every attachment', (
      tester,
    ) async {
      await tester.pumpWidget(await host(attachments: [photoA, photoB]));
      await tester.pumpAndSettle();
      await enterSelection(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Select All'));
      await tester.pumpAndSettle();

      expect(find.text('2 selected'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNWidgets(2));
      // Select-all hides once nothing is left to select.
      expect(find.widgetWithText(TextButton, 'Select All'), findsNothing);
    });

    testWidgets('cancelling returns to the normal header', (tester) async {
      await tester.pumpWidget(await host(attachments: [photoA, photoB]));
      await tester.pumpAndSettle();
      await enterSelection(tester);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(MediaSelectionHeader), findsNothing);
      expect(find.text('Site Media'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNothing);
    });
  });

  group('unlink', () {
    late List<List<String>> deleteCalls;

    /// Pumps the section with two attachments, both selected, and the
    /// unlink confirmation dialog open.
    Future<void> openUnlinkDialog(
      WidgetTester tester, {
      Object? failWith,
    }) async {
      deleteCalls = [];
      await tester.pumpWidget(
        await host(
          attachments: [photoA, photoB],
          extraOverrides: [
            siteMediaListNotifierProvider('site-1').overrideWith(
              (ref) => _RecordingSiteMediaNotifier(
                ref,
                deleteCalls: deleteCalls,
                failWith: failWith,
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.byType(MediaThumbnailTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Select All'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline));
      await tester.pumpAndSettle();
    }

    testWidgets('the confirmation names the site, not the dive', (
      tester,
    ) async {
      await openUnlinkDialog(tester);

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Remove 2 attachments?'), findsOneWidget);
      expect(
        find.text(
          'The selected items will be removed from this site. Files in '
          'your photo library or on disk are not deleted.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('cancelling dismisses without deleting anything', (
      tester,
    ) async {
      await openUnlinkDialog(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(deleteCalls, isEmpty);
      // The selection survives a cancelled unlink.
      expect(find.text('2 selected'), findsOneWidget);
    });

    testWidgets('confirming unlinks the selected ids and reports success', (
      tester,
    ) async {
      await openUnlinkDialog(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Unlink'));
      await tester.pumpAndSettle();

      expect(deleteCalls, [
        ['m1', 'm2'],
      ]);
      expect(find.text('Removed 2 attachments'), findsOneWidget);
      // Selection mode exits once the unlink lands.
      expect(find.byType(MediaSelectionHeader), findsNothing);
      expect(find.text('Site Media'), findsOneWidget);
    });

    testWidgets('a failing unlink surfaces the error and keeps the '
        'selection', (tester) async {
      await openUnlinkDialog(tester, failWith: Exception('row locked'));

      await tester.tap(find.widgetWithText(TextButton, 'Unlink'));
      await tester.pumpAndSettle();

      expect(
        find.text('Failed to unlink: Exception: row locked'),
        findsOneWidget,
      );
      expect(find.text('Removed 2 attachments'), findsNothing);
      expect(find.text('2 selected'), findsOneWidget);
    });
  });

  group('async states', () {
    testWidgets('a still-loading attachment list shows a spinner', (
      tester,
    ) async {
      final pending = Completer<List<MediaItem>>();
      addTearDown(() => pending.complete(const <MediaItem>[]));

      await tester.pumpWidget(await host(pendingAttachments: pending.future));
      // No settle: the progress indicator animates forever.
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(MediaThumbnailTile), findsNothing);
      expect(
        find.text('No maps, photos, or documents attached to this site'),
        findsNothing,
      );
    });

    testWidgets('a failing attachment query shows the error text', (
      tester,
    ) async {
      await tester.pumpWidget(
        await host(attachmentsError: Exception('disk unreadable')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Error loading media'), findsOneWidget);
      expect(find.byType(MediaThumbnailTile), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });

  group('dive photos group expanded', () {
    final dive = Dive(id: 'dive-1', dateTime: DateTime(2026, 3, 1));
    final divePhoto = testMediaItem(
      id: 'dp-1',
      diveId: 'dive-1',
      originalFilename: 'grouper.png',
      takenAt: DateTime(2026, 3, 1, 11),
    );

    testWidgets('expanding renders the dive photo tiles', (tester) async {
      await tester.pumpWidget(
        await host(
          divePhotos: {
            dive: [divePhoto],
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(MediaThumbnailTile), findsNothing);

      await tester.tap(find.text('Photos from dives here (1)'));
      await tester.pumpAndSettle();

      expect(find.byType(GridView), findsOneWidget);
      final tile = tester.widget<MediaThumbnailTile>(
        find.byType(MediaThumbnailTile),
      );
      expect(tile.item.id, 'dp-1');
      // The dive-photo group is read-only: no selection affordances.
      expect(tile.isSelectionMode, isFalse);
      expect(tile.semanticsLabel, 'Dive photo');
    });

    testWidgets('tapping a dive photo opens the viewer in divePhotos scope', (
      tester,
    ) async {
      await tester.pumpWidget(
        await host(
          divePhotos: {
            dive: [divePhoto],
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photos from dives here (1)'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(MediaThumbnailTile));
      await tester.pumpAndSettle();

      final viewer = tester.widget<SiteMediaViewerPage>(
        find.byType(SiteMediaViewerPage),
      );
      expect(viewer.siteId, 'site-1');
      expect(viewer.initialMediaId, 'dp-1');
      expect(viewer.scope, SiteViewerScope.divePhotos);
    });
  });
}
