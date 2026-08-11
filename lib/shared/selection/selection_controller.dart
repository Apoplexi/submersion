import 'package:flutter/foundation.dart';

import 'package:submersion/shared/selection/selection_state.dart';

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

  /// Leave selection mode and discard the selection.
  void exit() {
    value = SelectionState.inactive;
  }
}
