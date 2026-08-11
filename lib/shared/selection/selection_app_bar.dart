import 'package:flutter/material.dart';

import 'package:submersion/l10n/l10n_extension.dart';
import 'package:submersion/shared/selection/bulk_action.dart';
import 'package:submersion/shared/selection/selection_controller.dart';

/// Which container the selection bar is rendered into.
enum SelectionBarShell {
  /// The surface owns the window chrome, so the bar is a real [AppBar].
  appBar,

  /// The surface is a pane or an embedded section, so the bar is a plain
  /// container placed above the list.
  pane,
}

/// The contextual bar shown while a surface is in selection mode.
///
/// One content builder, two shells. The baseline controls -- select all,
/// deselect all, delete -- are injected here rather than declared per surface,
/// so no list can ship without them. Surfaces contribute only their extras.
///
/// The action set and its ordering are computed once in [_buildControls] and
/// are identical in both shells; only the split between inline icons and the
/// overflow menu depends on [maxInlineActions]. That is what stops the pane
/// variant from quietly offering fewer actions than the full-width one.
class SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  final SelectionController controller;

  /// Ids the surface will accept actions on, already filtered to exclude
  /// non-selectable rows. Select-all uses exactly this list.
  final List<String> selectableIds;

  /// Surface-specific extras: merge, export, bulk edit, and so on.
  final List<BulkAction> actions;

  final SelectionBarShell shell;

  /// Invoked by the baseline delete control.
  ///
  /// Null only for surfaces that have no true delete -- the dive media section
  /// unlinks media from a dive without destroying files, so a trash control
  /// there would misdescribe what it does. When null the delete control is
  /// omitted entirely rather than rendered disabled, so the bar never shows a
  /// dead button. Every surface that can delete must pass this.
  final VoidCallback? onDelete;

  /// How many extras render as inline icons before the rest overflow.
  final int maxInlineActions;

  const SelectionAppBar({
    super.key,
    required this.controller,
    required this.selectableIds,
    required this.actions,
    required this.shell,
    required this.onDelete,
    this.maxInlineActions = 3,
  });

  /// Whether this surface offers a delete at all.
  bool get _hasDelete => onDelete != null;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, state, _) {
        final count = state.count;
        final title = Text(context.l10n.common_selection_countSelected(count));
        final leading = IconButton(
          key: const ValueKey('selection_exit'),
          icon: const Icon(Icons.close),
          tooltip: context.l10n.common_selection_exitTooltip,
          onPressed: controller.exit,
        );
        final trailing = _buildControls(context, count, state.checkedIds);

        switch (shell) {
          case SelectionBarShell.appBar:
            return AppBar(leading: leading, title: title, actions: trailing);
          case SelectionBarShell.pane:
            return Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: SizedBox(
                height: kToolbarHeight,
                child: Row(
                  children: [
                    leading,
                    const SizedBox(width: 8),
                    Expanded(child: title),
                    ...trailing,
                  ],
                ),
              ),
            );
        }
      },
    );
  }

  /// Baseline controls plus extras, in a fixed order, identical in both
  /// shells.
  List<Widget> _buildControls(
    BuildContext context,
    int count,
    Set<String> checkedIds,
  ) {
    final allChecked =
        count >= selectableIds.length && selectableIds.isNotEmpty;
    final inline = actions.take(maxInlineActions).toList();
    final overflow = actions.skip(maxInlineActions).toList();

    return [
      IconButton(
        key: const ValueKey('selection_select_all'),
        icon: const Icon(Icons.select_all),
        tooltip: context.l10n.common_selection_selectAllTooltip,
        onPressed: allChecked
            ? null
            : () => controller.selectAll(selectableIds),
      ),
      IconButton(
        key: const ValueKey('selection_deselect_all'),
        icon: const Icon(Icons.deselect),
        tooltip: context.l10n.common_selection_deselectAllTooltip,
        onPressed: count == 0 ? null : controller.deselectAll,
      ),
      for (final action in inline)
        IconButton(
          key: ValueKey('selection_action_${action.id}'),
          icon: Icon(action.icon),
          tooltip: action.label,
          color: action.isDestructive
              ? Theme.of(context).colorScheme.error
              : null,
          onPressed: action.isEnabledForSelection(count, checkedIds)
              ? action.onInvoke
              : null,
        ),
      if (_hasDelete)
        IconButton(
          key: const ValueKey('selection_delete'),
          icon: const Icon(Icons.delete_outline),
          tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
          color: Theme.of(context).colorScheme.error,
          onPressed: count == 0 ? null : onDelete,
        ),
      if (overflow.isNotEmpty)
        PopupMenuButton<String>(
          key: const ValueKey('selection_overflow'),
          itemBuilder: (context) => [
            for (final action in overflow)
              PopupMenuItem<String>(
                value: action.id,
                enabled: action.isEnabledForSelection(count, checkedIds),
                child: ListTile(
                  leading: Icon(action.icon),
                  title: Text(action.label),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
          ],
          onSelected: (id) {
            for (final action in overflow) {
              if (action.id == id) {
                action.onInvoke();
                return;
              }
            }
          },
        ),
    ];
  }
}
