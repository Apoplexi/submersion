import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media/domain/entities/media_library_filter.dart';
import 'package:submersion/features/media/domain/entities/media_source_type.dart';
import 'package:submersion/features/media/presentation/widgets/media_library_grid.dart';
import 'package:submersion/features/media/presentation/widgets/media_library_grouped_list.dart';
import 'package:submersion/features/media/presentation/widgets/media_library_groupers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

MediaLibraryEntry entry(String id) => MediaLibraryEntry(
  item: MediaItem(
    id: id,
    mediaType: MediaType.photo,
    sourceType: MediaSourceType.localFile,
    filePath: '/tmp/$id.jpg',
    takenAt: DateTime.utc(2026, 6, 12),
    createdAt: DateTime.utc(2026, 6, 12),
    updatedAt: DateTime.utc(2026, 6, 12),
  ),
);

MediaLibraryGroup diveGroup({
  String? diveId,
  int? diveNumber,
  String? siteName,
  DateTime? diveDateTime,
  List<MediaLibraryEntry>? entries,
}) => MediaLibraryGroup(
  header: DiveGroupHeader(
    diveId: diveId,
    diveNumber: diveNumber,
    siteName: siteName,
    diveDateTime: diveDateTime,
  ),
  entries: entries ?? [entry('a')],
);

void main() {
  Widget host(
    List<MediaLibraryGroup> groups, {
    bool hasMore = false,
    VoidCallback? onLoadMore,
    void Function(MediaLibraryEntry)? onTileTap,
    Set<String> selectedIds = const {},
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MediaLibraryGroupedList(
          groups: groups,
          hasMore: hasMore,
          onLoadMore: onLoadMore ?? () {},
          onTileTap: onTileTap ?? (_) {},
          selectedIds: selectedIds,
        ),
      ),
    );
  }

  testWidgets('a dive header reads as number and site', (tester) async {
    await tester.pumpWidget(
      host([diveGroup(diveId: 'd1', diveNumber: 9, siteName: 'Blue Hole')]),
    );
    await tester.pump();

    expect(find.text('#9 · Blue Hole'), findsOneWidget);
  });

  testWidgets('a dive with neither number nor site falls back to its date', (
    tester,
  ) async {
    await tester.pumpWidget(
      host([diveGroup(diveId: 'd1', diveDateTime: DateTime.utc(2026, 6, 12))]),
    );
    await tester.pump();

    expect(find.text('Jun 12, 2026'), findsOneWidget);
  });

  testWidgets('a dive with nothing at all renders an empty header', (
    tester,
  ) async {
    await tester.pumpWidget(host([diveGroup(diveId: 'd1')]));
    await tester.pump();

    // No crash, and no stray label text.
    expect(find.byType(MediaLibraryGroupedList), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the unlinked group gets its own localized header', (
    tester,
  ) async {
    await tester.pumpWidget(host([diveGroup()]));
    await tester.pump();

    expect(find.text('Unlinked'), findsOneWidget);
  });

  testWidgets('only linked headers are tappable', (tester) async {
    await tester.pumpWidget(
      host([
        diveGroup(diveId: 'd1', diveNumber: 9),
        diveGroup(entries: [entry('b')]),
      ]),
    );
    await tester.pump();

    // The linked header navigates; the unlinked one has nowhere to go.
    expect(find.byType(InkWell), findsOneWidget);
  });

  testWidgets('a dive header leaves the library beneath the dive detail', (
    tester,
  ) async {
    // Mirrors the real router: :diveId is a CHILD of /dives, so a stack-
    // replacing navigation would synthesize the dive list underneath.
    final router = GoRouter(
      initialLocation: '/media',
      routes: [
        GoRoute(
          path: '/media',
          builder: (context, state) => Scaffold(
            body: MediaLibraryGroupedList(
              groups: [diveGroup(diveId: 'd1', diveNumber: 9)],
              hasMore: false,
              onLoadMore: () {},
              onTileTap: (_) {},
              selectedIds: const {},
            ),
          ),
        ),
        GoRoute(
          path: '/dives',
          builder: (context, state) => const Scaffold(body: Text('Dive List')),
          routes: [
            GoRoute(
              path: ':diveId',
              builder: (context, state) =>
                  Scaffold(appBar: AppBar(), body: const Text('Dive Detail')),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('#9'));
    await tester.pumpAndSettle();
    expect(find.text('Dive Detail'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();

    expect(find.text('#9'), findsOneWidget);
    expect(find.text('Dive List'), findsNothing);
  });

  testWidgets('tiles report taps with their entry', (tester) async {
    MediaLibraryEntry? tapped;
    await tester.pumpWidget(
      host([
        diveGroup(diveId: 'd1', diveNumber: 9, entries: [entry('a')]),
      ], onTileTap: (e) => tapped = e),
    );
    await tester.pump();

    await tester.tap(find.byType(MediaLibraryTile).first);
    await tester.pump();

    expect(tapped?.item.id, 'a');
  });

  testWidgets('scrolling near the end asks for more', (tester) async {
    var loadMoreCalls = 0;
    await tester.pumpWidget(
      host(
        [
          for (var i = 0; i < 30; i++)
            diveGroup(
              diveId: 'd$i',
              diveNumber: i,
              entries: [entry('a$i'), entry('b$i')],
            ),
        ],
        hasMore: true,
        onLoadMore: () => loadMoreCalls++,
      ),
    );
    await tester.pump();

    await tester.drag(
      find.byType(MediaLibraryGroupedList),
      const Offset(0, -4000),
    );
    await tester.pump();

    expect(loadMoreCalls, greaterThan(0));
  });

  testWidgets('load-more stays quiet once the list is exhausted', (
    tester,
  ) async {
    var loadMoreCalls = 0;
    await tester.pumpWidget(
      host([
        for (var i = 0; i < 30; i++)
          diveGroup(diveId: 'd$i', diveNumber: i, entries: [entry('a$i')]),
      ], onLoadMore: () => loadMoreCalls++),
    );
    await tester.pump();

    await tester.drag(
      find.byType(MediaLibraryGroupedList),
      const Offset(0, -4000),
    );
    await tester.pump();

    expect(loadMoreCalls, 0);
  });
}
