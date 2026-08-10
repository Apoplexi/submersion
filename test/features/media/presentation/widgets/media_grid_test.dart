import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/media/presentation/widgets/media_grid.dart';

void main() {
  testWidgets('MediaEmptyState renders icon and message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MediaEmptyState(icon: Icons.map_outlined, message: 'No media'),
        ),
      ),
    );
    expect(find.text('No media'), findsOneWidget);
    expect(find.byIcon(Icons.map_outlined), findsOneWidget);
  });

  Widget header({required int selectedCount, VoidCallback? onUnlink}) {
    return MaterialApp(
      home: Scaffold(
        body: MediaSelectionHeader(
          selectedCount: selectedCount,
          totalCount: 3,
          onSelectAll: () {},
          onCancel: () {},
          onUnlinkSelected: onUnlink ?? () {},
          selectedCountLabel: '$selectedCount selected',
          selectAllLabel: 'Select all',
          cancelTooltip: 'Cancel',
          unlinkTooltip: 'Unlink',
        ),
      ),
    );
  }

  testWidgets('MediaSelectionHeader disables unlink at zero selection', (
    tester,
  ) async {
    await tester.pumpWidget(header(selectedCount: 0));
    final button = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.delete_outline),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('MediaSelectionHeader enables unlink with a selection', (
    tester,
  ) async {
    var fired = 0;
    await tester.pumpWidget(header(selectedCount: 1, onUnlink: () => fired++));
    await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline));
    expect(fired, 1);
    // Select-all appears while not everything is selected.
    expect(find.text('Select all'), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);
  });
}
