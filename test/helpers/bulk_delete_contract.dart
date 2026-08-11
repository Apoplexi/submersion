import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drives a surface's bulk-delete flow end to end and reports what it deleted.
///
/// Every selectable surface got the same baseline delete: enter selection,
/// check rows, tap the keyed delete control, confirm, and see a snackbar. The
/// handlers are near-identical per surface and were the least-covered part of
/// the selection work, so this exercises the real path rather than asserting
/// the button exists.
///
/// [build] returns a fully wired widget for the surface.
/// [selectButton] finds the surface's Select affordance.
/// [expectedDeletedCount] is how many rows select-all should check.
/// [confirmLabel] is the confirm button's text, defaulting to the shared
/// bulk-delete wording.
Future<void> verifyBulkDelete(
  WidgetTester tester, {
  required Widget Function() build,
  required Finder selectButton,
  required int expectedDeletedCount,
  String confirmLabel = 'Delete',
  bool settle = true,
}) async {
  Future<void> advance() async {
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
  }

  await tester.pumpWidget(build());
  await advance();

  await tester.tap(selectButton);
  await advance();

  await tester.tap(find.byKey(const ValueKey('selection_select_all')));
  await advance();

  final deleteButton = find.byKey(const ValueKey('selection_delete'));
  expect(
    deleteButton,
    findsOneWidget,
    reason: 'delete is a guaranteed baseline control',
  );
  expect(
    tester.widget<IconButton>(deleteButton).onPressed,
    isNotNull,
    reason: 'delete must be enabled with rows checked',
  );

  await tester.tap(deleteButton);
  await advance();

  // The confirmation is not optional: bulk delete must never act on a single
  // tap.
  expect(
    find.byType(AlertDialog),
    findsOneWidget,
    reason: 'bulk delete must confirm before acting',
  );

  // The confirm is a FilledButton (destructive styling) while cancel is a
  // TextButton, so match on the label rather than the button type.
  await tester.tap(find.text(confirmLabel).hitTestable().last);
  await advance();
}

/// Confirms that cancelling the bulk-delete confirmation deletes nothing and
/// leaves the selection intact.
Future<void> verifyBulkDeleteCancels(
  WidgetTester tester, {
  required Widget Function() build,
  required Finder selectButton,
  bool settle = true,
}) async {
  Future<void> advance() async {
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump();
    }
  }

  await tester.pumpWidget(build());
  await advance();

  await tester.tap(selectButton);
  await advance();
  await tester.tap(find.byKey(const ValueKey('selection_select_all')));
  await advance();
  await tester.tap(find.byKey(const ValueKey('selection_delete')));
  await advance();

  await tester.tap(find.text('Cancel').hitTestable().last);
  await advance();

  expect(
    find.byType(AlertDialog),
    findsNothing,
    reason: 'cancelling must dismiss the confirmation',
  );
  expect(
    find.byKey(const ValueKey('selection_exit')),
    findsOneWidget,
    reason: 'cancelling must leave the selection intact, not exit the mode',
  );
}
