import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/theme/full_themes/tropical_theme.dart';
import 'package:submersion/shared/widgets/app_bar_text_action.dart';

void main() {
  Future<void> pump(WidgetTester tester, ThemeData theme, Widget action) {
    return tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(
          appBar: AppBar(title: const Text('Title'), actions: [action]),
        ),
      ),
    );
  }

  Color renderedColor(WidgetTester tester, String label) {
    final paragraph = tester.renderObject<RenderParagraph>(find.text(label));
    return paragraph.text.style!.color!;
  }

  testWidgets('bare TextButton is invisible on the tropical app bar '
      '(the #736 defect this widget exists to avoid)', (tester) async {
    await pump(
      tester,
      tropicalLight,
      TextButton(onPressed: () {}, child: const Text('Save')),
    );
    expect(
      renderedColor(tester, 'Save'),
      tropicalLight.appBarTheme.backgroundColor,
      reason:
          'colorScheme.primary equals the app bar background in the '
          'tropical theme, so a bare TextButton renders invisibly',
    );
  });

  testWidgets('AppBarTextAction stays visible against the tropical app bar', (
    tester,
  ) async {
    await pump(
      tester,
      tropicalLight,
      AppBarTextAction(label: 'Save', onPressed: () {}),
    );
    final color = renderedColor(tester, 'Save');
    expect(color, tropicalLight.appBarTheme.foregroundColor);
    expect(color, isNot(tropicalLight.appBarTheme.backgroundColor));
  });

  testWidgets('AppBarTextAction invokes onPressed', (tester) async {
    var tapped = false;
    await pump(
      tester,
      tropicalLight,
      AppBarTextAction(label: 'Save', onPressed: () => tapped = true),
    );
    await tester.tap(find.text('Save'));
    expect(tapped, isTrue);
  });
}
