import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/constants/enums.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/marine_life/domain/entities/species.dart';
import 'package:submersion/features/marine_life/presentation/pages/species_manage_page.dart';
import 'package:submersion/features/marine_life/presentation/providers/species_providers.dart';

import '../../../../helpers/selection_contract.dart';
import '../../../../helpers/test_app.dart';

Species _species({
  required String id,
  required String name,
  bool isBuiltIn = false,
}) => Species(
  id: id,
  commonName: name,
  category: SpeciesCategory.fish,
  isBuiltIn: isBuiltIn,
);

/// Mutable source for the contract test's filter step.
final _visibleSpeciesProvider = StateProvider<List<Species>>((ref) => const []);

void main() {
  Widget host({
    required List<Species> species,
    Map<String, int> sightingCounts = const {},
  }) {
    return testApp(
      locale: const Locale('en'),
      overrides: [
        _visibleSpeciesProvider.overrideWith((ref) => species),
        speciesListNotifierProvider.overrideWith(
          (ref) => _MockSpeciesNotifier(ref.watch(_visibleSpeciesProvider)),
        ),
        speciesSightingCountsProvider.overrideWith(
          (ref) async => sightingCounts,
        ),
      ],
      child: const SpeciesManagePage(),
    );
  }

  group('SpeciesManagePage selection', () {
    testWidgets('satisfies the shared selection contract', (tester) async {
      final all = [
        _species(id: 's1', name: 'Aaa fish'),
        _species(id: 's2', name: 'Bbb fish'),
        _species(id: 's3', name: 'Ccc fish'),
      ];

      await verifySelectionContract(
        tester,
        build: () => host(species: all),
        selectButton: find.byKey(const ValueKey('enter_selection')),
        firstRow: find.text('Aaa fish'),
        applyFilter: (tester) async {
          final container = ProviderScope.containerOf(
            tester.element(find.byType(SpeciesManagePage)),
          );
          container.read(_visibleSpeciesProvider.notifier).state = [all.first];
        },
        visibleAfterFilter: 1,
      );
    });

    testWidgets('built-in species render no checkbox', (tester) async {
      await tester.pumpWidget(
        host(
          species: [
            _species(id: 'b1', name: 'Built-in fish', isBuiltIn: true),
            _species(id: 'c1', name: 'Custom fish'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('enter_selection')));
      await tester.pumpAndSettle();

      expect(
        find.byType(Checkbox),
        findsOneWidget,
        reason: 'only the custom species is selectable',
      );
    });

    testWidgets('a species with sightings renders no checkbox and is '
        'excluded from select-all', (tester) async {
      await tester.pumpWidget(
        host(
          species: [
            _species(id: 'c1', name: 'Unseen fish'),
            _species(id: 'c2', name: 'Seen fish'),
          ],
          // deleteSpecies throws for a referenced species, so the UI must not
          // let one be checked in the first place.
          sightingCounts: const {'c2': 12},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('enter_selection')));
      await tester.pumpAndSettle();
      expect(find.byType(Checkbox), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('selection_select_all')));
      await tester.pumpAndSettle();

      expect(
        find.text('1 selected'),
        findsOneWidget,
        reason: 'select-all must skip species the repository refuses to delete',
      );
    });
  });
}

class _MockSpeciesNotifier extends StateNotifier<AsyncValue<List<Species>>>
    implements SpeciesListNotifier {
  _MockSpeciesNotifier(List<Species> species) : super(AsyncValue.data(species));

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
