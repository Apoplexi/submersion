import 'package:flutter/material.dart';

import 'package:submersion/shared/selection/selection_leading.dart';

/// Prefixes an arbitrary row widget with a selection checkbox.
///
/// [SelectionLeading] swaps a row's existing leading element for a checkbox,
/// which suits tiles that own one -- a dive number badge, a site avatar. Many
/// rows have no such slot, so the checkbox has to be inserted in front of the
/// whole tile instead. This does that without requiring every tile widget to
/// grow selection parameters of its own.
///
/// The checkbox still animates in and out, because the empty state is a
/// zero-width box handed to the same [SelectionLeading].
class SelectableRow extends StatelessWidget {
  final bool isSelectionMode;
  final bool isChecked;

  /// False for rows that cannot be acted on, such as built-in reference data.
  /// Those keep their full width and render no checkbox.
  final bool isSelectable;

  final ValueChanged<bool>? onChanged;

  final Widget child;

  const SelectableRow({
    super.key,
    required this.isSelectionMode,
    required this.isChecked,
    required this.child,
    this.isSelectable = true,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SelectionLeading(
          isSelectionMode: isSelectionMode,
          isChecked: isChecked,
          isSelectable: isSelectable,
          onChanged: onChanged,
          child: const SizedBox.shrink(),
        ),
        Expanded(child: child),
      ],
    );
  }
}
