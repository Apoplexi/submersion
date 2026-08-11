import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Asserts the app-wide selection contract against one surface.
///
/// Every selectable list and grid calls this, so a regression on any single
/// page fails loudly instead of drifting the way the hand-written per-page
/// implementations did.
///
/// [build] returns a fully wired widget for the surface under test.
/// [selectButton] finds the surface's Select affordance.
/// [firstRow] finds the first selectable row.
/// [applyFilter] narrows the surface so pruning can be observed, leaving
/// [visibleAfterFilter] rows on screen.
/// Whether this surface renders its checked state as [Checkbox] widgets.
///
/// List surfaces do. Grid surfaces such as the dive media section draw a check
/// badge over the thumbnail instead, so they opt out of that one assertion
/// while still being held to the rest of the contract.
enum CheckedIndicator { checkbox, custom }

Future<void> verifySelectionContract(
  WidgetTester tester, {
  required Widget Function() build,
  required Finder selectButton,
  required Finder firstRow,
  required Future<void> Function(WidgetTester tester) applyFilter,
  required int visibleAfterFilter,
  CheckedIndicator indicator = CheckedIndicator.checkbox,
}) async {
  // The Select affordance is visible without any hidden gesture.
  await tester.pumpWidget(build());
  await tester.pumpAndSettle();
  expect(
    selectButton,
    findsOneWidget,
    reason: 'surface must expose a visible Select affordance',
  );

  // Tapping it enters the mode with nothing checked, and checkboxes appear.
  await tester.tap(selectButton);
  await tester.pumpAndSettle();
  expect(
    find.byKey(const ValueKey('selection_exit')),
    findsOneWidget,
    reason: 'tapping Select must enter selection mode',
  );
  if (indicator == CheckedIndicator.checkbox) {
    expect(
      find.byType(Checkbox),
      findsWidgets,
      reason: 'selection mode must render checkboxes in the leading slot',
    );
  }
  expect(
    checkedCount(tester),
    0,
    reason: 'entering via the Select button must check nothing',
  );

  // Select all, then deselect all, drive the count.
  await tester.tap(find.byKey(const ValueKey('selection_select_all')));
  await tester.pumpAndSettle();
  expect(
    checkedCount(tester),
    greaterThan(0),
    reason: 'select all must check at least one row',
  );

  await tester.tap(find.byKey(const ValueKey('selection_deselect_all')));
  await tester.pumpAndSettle();
  expect(
    checkedCount(tester),
    0,
    reason: 'deselect all must clear every checkbox',
  );
  expect(
    find.byKey(const ValueKey('selection_exit')),
    findsOneWidget,
    reason: 'an explicitly entered mode must survive deselect all',
  );

  // Tapping a row toggles it.
  await tester.tap(firstRow);
  await tester.pumpAndSettle();
  expect(
    checkedCount(tester),
    1,
    reason: 'tapping a row in selection mode must check it',
  );

  // Escape exits.
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  expect(
    find.byKey(const ValueKey('selection_exit')),
    findsNothing,
    reason: 'Escape must exit selection mode',
  );

  // Filtering prunes the selection to what remains visible.
  await tester.tap(selectButton);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('selection_select_all')));
  await tester.pumpAndSettle();

  await applyFilter(tester);
  await tester.pumpAndSettle();
  expect(
    checkedCount(tester),
    lessThanOrEqualTo(visibleAfterFilter),
    reason: 'filtering must prune checked ids that left the visible set',
  );
}

/// Number of checked items, read from the selection bar's own count.
///
/// The bar is the one element every selectable surface renders, so this works
/// for grids that draw check badges as well as lists that draw checkboxes.
/// Callers must pin the locale to `en`, which the contract already assumes.
int checkedCount(WidgetTester tester) {
  final pattern = RegExp(r'^(\d+) selected$');
  for (final widget in tester.widgetList<Text>(find.byType(Text))) {
    final data = widget.data;
    if (data == null) continue;
    final match = pattern.firstMatch(data);
    if (match != null) return int.parse(match.group(1)!);
  }
  return 0;
}
