import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/dive_log/presentation/widgets/readout_tile.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
    home: Scaffold(body: Center(child: child)),
  );

  testWidgets('renders label and value', (tester) async {
    await tester.pumpWidget(
      wrap(const ReadoutTile(label: 'DEPTH', value: '18.4 m')),
    );
    expect(find.text('DEPTH'), findsOneWidget);
    expect(find.text('18.4 m'), findsOneWidget);
  });

  testWidgets('null value renders an em dash', (tester) async {
    await tester.pumpWidget(
      wrap(const ReadoutTile(label: 'TEMP', value: null)),
    );
    expect(find.text('—'), findsOneWidget);
  });
}
