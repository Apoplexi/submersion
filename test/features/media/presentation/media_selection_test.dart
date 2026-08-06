import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/media/data/services/media_source_resolver_registry.dart';
import 'package:submersion/features/media/domain/entities/media_item.dart';
import 'package:submersion/features/media/domain/entities/media_library_filter.dart';
import 'package:submersion/features/media/domain/entities/media_source_type.dart';
import 'package:submersion/features/media/domain/services/media_source_resolver.dart';
import 'package:submersion/features/media/domain/value_objects/media_source_data.dart';
import 'package:submersion/features/media/domain/value_objects/media_source_metadata.dart';
import 'package:submersion/features/media/domain/value_objects/verify_result.dart';
import 'package:submersion/features/media/presentation/pages/media_library_view.dart';
import 'package:submersion/features/media/presentation/providers/media_library_providers.dart';
import 'package:submersion/features/media/presentation/providers/media_resolver_providers.dart';
import 'package:submersion/features/media/presentation/providers/media_selection_provider.dart';
import 'package:submersion/features/media/presentation/widgets/media_library_grid.dart';
import 'package:submersion/features/media_store/data/media_deletion_coordinator.dart';
import 'package:submersion/features/media_store/presentation/providers/media_store_providers.dart';
import 'package:submersion/features/settings/data/repositories/app_settings_repository.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';

class _UnavailableResolver implements MediaSourceResolver {
  @override
  MediaSourceType get sourceType => MediaSourceType.localFile;
  @override
  bool canResolveOnThisDevice(MediaItem item) => true;
  @override
  Future<MediaSourceData> resolve(MediaItem item) async =>
      const UnavailableData(kind: UnavailableKind.notFound);
  @override
  Future<MediaSourceData> resolveThumbnail(
    MediaItem item, {
    required Size target,
  }) => resolve(item);
  @override
  Future<MediaSourceMetadata?> extractMetadata(MediaItem item) async => null;
  @override
  Future<VerifyResult> verify(MediaItem item) async => VerifyResult.available;
}

class _SeededLibraryNotifier extends StateNotifier<MediaLibraryState>
    implements MediaLibraryNotifier {
  _SeededLibraryNotifier(super.state);

  @override
  Future<void> loadFirstPage() async {}

  @override
  Future<void> loadMore() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSettingsRepo extends AppSettingsRepository {
  @override
  Future<String?> getRawSetting(String key) async => null;

  @override
  Future<void> setRawSetting(String key, String value) async {}
}

class _RecordingDeletionCoordinator implements MediaDeletionCoordinator {
  final List<String> deleted = [];

  @override
  Future<void> deleteMultipleMedia(List<String> ids) async {
    deleted.addAll(ids);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaLibraryEntry entry(String id) => MediaLibraryEntry(
  item: MediaItem(
    id: id,
    mediaType: MediaType.photo,
    sourceType: MediaSourceType.localFile,
    filePath: '/tmp/$id',
    localPath: '/tmp/$id',
    takenAt: DateTime(2026, 6, 1),
    createdAt: DateTime(2026, 6, 1),
    updatedAt: DateTime(2026, 6, 1),
  ),
);

void main() {
  group('MediaSelectionNotifier', () {
    test('toggle adds then removes an id; clear empties', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(mediaSelectionProvider.notifier);

      notifier.toggle('a');
      expect(container.read(mediaSelectionProvider), {'a'});
      notifier.toggle('b');
      expect(container.read(mediaSelectionProvider), {'a', 'b'});
      notifier.toggle('a');
      expect(container.read(mediaSelectionProvider), {'b'});
      notifier.clear();
      expect(container.read(mediaSelectionProvider), isEmpty);
    });
  });

  group('selection UI', () {
    late _RecordingDeletionCoordinator coordinator;

    Widget host(List<MediaLibraryEntry> entries) {
      coordinator = _RecordingDeletionCoordinator();
      return ProviderScope(
        overrides: [
          mediaLibraryNotifierProvider.overrideWith(
            (ref) =>
                _SeededLibraryNotifier(MediaLibraryState(entries: entries)),
          ),
          appSettingsRepositoryProvider.overrideWithValue(_FakeSettingsRepo()),
          mediaDeletionCoordinatorProvider.overrideWithValue(coordinator),
          mediaSourceResolverRegistryProvider.overrideWithValue(
            MediaSourceResolverRegistry({
              MediaSourceType.localFile: _UnavailableResolver(),
            }),
          ),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: MediaLibraryView()),
        ),
      );
    }

    testWidgets('long-press enters selection mode and shows the bar', (
      tester,
    ) async {
      await tester.pumpWidget(host([entry('a'), entry('b')]));
      await tester.pumpAndSettle();

      await tester.longPress(find.byType(MediaLibraryTile).first);
      await tester.pumpAndSettle();

      expect(find.text('1 selected'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
    });

    testWidgets('delete confirms then calls the deletion chain and clears', (
      tester,
    ) async {
      await tester.pumpWidget(host([entry('a'), entry('b')]));
      await tester.pumpAndSettle();

      await tester.longPress(find.byType(MediaLibraryTile).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(MediaLibraryTile).at(1));
      await tester.pumpAndSettle();
      expect(find.text('2 selected'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      // Confirm dialog
      expect(find.text('Delete 2 items?'), findsOneWidget);
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(coordinator.deleted.toSet(), {'a', 'b'});
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MediaLibraryView)),
      );
      expect(container.read(mediaSelectionProvider), isEmpty);
    });

    testWidgets('tap in selection mode toggles instead of opening viewer', (
      tester,
    ) async {
      await tester.pumpWidget(host([entry('a'), entry('b')]));
      await tester.pumpAndSettle();

      await tester.longPress(find.byType(MediaLibraryTile).first);
      await tester.pumpAndSettle();
      // Tap the already-selected tile: deselects, bar disappears.
      await tester.tap(find.byType(MediaLibraryTile).first);
      await tester.pumpAndSettle();
      expect(find.text('Delete'), findsNothing);
    });
  });
}
