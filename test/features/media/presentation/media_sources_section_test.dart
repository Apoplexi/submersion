import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/database/local_cache_database.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/media/data/repositories/watched_folder_repository.dart';
import 'package:submersion/features/media/data/services/repair/watched_folder_scanner.dart';
import 'package:submersion/features/media/domain/entities/media_source_type.dart';
import 'package:submersion/features/media/presentation/pages/media_sources_section_view.dart';
import 'package:submersion/features/media/presentation/providers/media_library_providers.dart';
import 'package:submersion/features/media/presentation/providers/media_watcher_providers.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

import '../../../support/fake_app_settings_repository.dart';

class _FakeScanner implements WatchedFolderScanner {
  int calls = 0;

  @override
  Future<WatcherScanReport> scan({required DateTime now}) async {
    calls++;
    return const WatcherScanReport(
      filesIndexed: 12,
      rehashed: 3,
      autoRepaired: 2,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late LocalCacheDatabase cacheDb;
  late WatchedFolderRepository watched;
  late FakeAppSettingsRepository settings;
  late _FakeScanner scanner;

  setUp(() {
    cacheDb = LocalCacheDatabase(NativeDatabase.memory());
    watched = WatchedFolderRepository(database: cacheDb);
    settings = FakeAppSettingsRepository();
    scanner = _FakeScanner();
  });
  tearDown(() => cacheDb.close());

  Widget host({
    Map<MediaSourceType, int> counts = const {},
    Future<String?> Function()? picker,
    VoidCallback? onBrowse,
  }) {
    return ProviderScope(
      overrides: [
        sourceCountsProvider.overrideWith((ref) async => counts),
        watchedFolderRepositoryProvider.overrideWithValue(watched),
        watcherScannerProvider.overrideWithValue(scanner),
        appSettingsRepositoryProvider.overrideWithValue(settings),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: MediaSourcesSectionView(
            onBrowseSource: onBrowse ?? () {},
            pickFolderOverride: picker,
          ),
        ),
      ),
    );
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));

  testWidgets('source rows render one labelled row per populated type', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        counts: const {
          MediaSourceType.localFile: 42,
          MediaSourceType.mediaStore: 7,
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Local files'), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text('Cloud media store'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('Photo library'), findsNothing);
  });

  testWidgets('tapping a source row filters the library and browses', (
    tester,
  ) async {
    var browsed = 0;
    await tester.pumpWidget(
      host(
        counts: const {MediaSourceType.mediaStore: 7},
        onBrowse: () => browsed++,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cloud media store'));
    await tester.pumpAndSettle();

    expect(browsed, 1);
    final filter = containerOf(tester).read(mediaLibraryFilterProvider);
    expect(filter.sourceType, MediaSourceType.mediaStore);
  });

  testWidgets('adding a watched root lists it as never scanned', (
    tester,
  ) async {
    await tester.pumpWidget(host(picker: () async => '/nas/Dives'));
    await tester.pumpAndSettle();

    expect(find.text('Scan now'), findsNothing);

    await tester.tap(find.text('Add folder...'));
    await tester.pumpAndSettle();

    expect(find.text('/nas/Dives'), findsOneWidget);
    expect(find.text('Never scanned'), findsOneWidget);
    expect(find.text('Scan now'), findsOneWidget);
    expect(await watched.getRoots(), ['/nas/Dives']);
  });

  testWidgets('a cancelled picker adds nothing', (tester) async {
    await tester.pumpWidget(host(picker: () async => null));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add folder...'));
    await tester.pumpAndSettle();

    expect(await watched.getRoots(), isEmpty);
  });

  testWidgets('removing a root drops it from the list', (tester) async {
    await watched.addRoot('/nas/Dives');
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();
    expect(find.text('/nas/Dives'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pumpAndSettle();

    expect(find.text('/nas/Dives'), findsNothing);
    expect(await watched.getRoots(), isEmpty);
  });

  testWidgets('Scan now runs the scanner and reports what it did', (
    tester,
  ) async {
    await watched.addRoot('/nas/Dives');
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Scan now'));
    await tester.pumpAndSettle();

    expect(scanner.calls, 1);
    expect(find.text('12 files indexed, 2 re-linked'), findsOneWidget);
  });

  testWidgets('toggling auto-apply persists the setting', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isTrue,
    );

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    expect(settings.values['media_watcher_auto_apply'], 'false');
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
  });
}
