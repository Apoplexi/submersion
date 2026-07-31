import 'package:flutter/material.dart';

/// A text action for [AppBar.actions] that stays visible on every theme.
///
/// A bare [TextButton] takes its foreground from `colorScheme.primary`,
/// which some full themes (Tropical, Console) set to the same color as the
/// app bar background, rendering the label invisible (#736). This widget
/// pins the foreground to the app bar's own foreground color instead.
class AppBarTextAction extends StatelessWidget {
  const AppBarTextAction({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground =
        theme.appBarTheme.foregroundColor ?? theme.colorScheme.onSurface;
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(foregroundColor: foreground),
      child: Text(label),
    );
  }
}
