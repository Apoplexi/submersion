import 'package:flutter/foundation.dart';

import 'package:submersion/shared/selection/selection_state.dart';

/// Inclusive id span between [anchorId] and [targetId] within [orderedIds].
///
/// Order-independent: extending backwards selects the same range. Returns an
/// empty list when either id is absent, so a stale anchor cannot select a
/// wrong span.
List<String> idsInRange(
  List<String> orderedIds,
  String anchorId,
  String targetId,
) {
  final anchorIndex = orderedIds.indexOf(anchorId);
  final targetIndex = orderedIds.indexOf(targetId);
  if (anchorIndex < 0 || targetIndex < 0) return const [];

  final lo = anchorIndex < targetIndex ? anchorIndex : targetIndex;
  final hi = anchorIndex < targetIndex ? targetIndex : anchorIndex;
  return [for (var i = lo; i <= hi; i++) orderedIds[i]];
}

/// Owns the multi-selection state machine for one list or grid surface.
///
/// Deliberately not a Riverpod provider: selection prunes to the visible set
/// and does not survive leaving the surface, so it is ephemeral view state.
/// A plain [ValueNotifier] is testable without a ProviderContainer.
class SelectionController extends ValueNotifier<SelectionState> {
  SelectionController() : super(SelectionState.inactive);

  /// Enter selection mode deliberately, with nothing checked.
  ///
  /// No-op when already active, so tapping Select twice does not clear the
  /// user's work.
  void enterExplicit() {
    if (value.isActive) return;
    value = const SelectionState(
      checkedIds: <String>{},
      isActive: true,
      enteredExplicitly: true,
      anchorId: null,
    );
  }

  /// Enter selection mode as a side effect of long-press or modifier-click,
  /// checking [id]. Behaves as [toggle] when the mode is already active.
  void enterImplicit(String id) {
    if (value.isActive) {
      toggle(id);
      return;
    }
    value = SelectionState(
      checkedIds: {id},
      isActive: true,
      enteredExplicitly: false,
      anchorId: id,
    );
  }

  /// Check or uncheck [id], moving the range anchor to it.
  ///
  /// Unchecking the last item ends an implicitly entered mode.
  void toggle(String id) {
    final next = Set<String>.from(value.checkedIds);
    if (!next.remove(id)) next.add(id);

    if (next.isEmpty && !value.enteredExplicitly) {
      exit();
      return;
    }
    value = value.copyWith(checkedIds: next, anchorId: id);
  }

  /// Check every item between the anchor and [targetId] in [orderedIds].
  ///
  /// The anchor is the controller's current anchor, else [fallbackAnchorId]
  /// (the row highlighted in the detail pane), else [targetId] itself. The
  /// anchor never moves during extension, so consecutive shift-clicks extend
  /// from the original origin rather than walking it forward.
  void extendTo(
    String targetId,
    List<String> orderedIds, {
    String? fallbackAnchorId,
  }) {
    if (!orderedIds.contains(targetId)) return;

    final anchor = value.anchorId ?? fallbackAnchorId ?? targetId;
    final next = Set<String>.from(value.checkedIds)
      ..addAll(idsInRange(orderedIds, anchor, targetId));

    value = SelectionState(
      checkedIds: next,
      isActive: true,
      enteredExplicitly: value.isActive ? value.enteredExplicitly : false,
      anchorId: anchor,
    );
  }

  /// Leave selection mode and discard the selection.
  void exit() {
    value = SelectionState.inactive;
  }
}
