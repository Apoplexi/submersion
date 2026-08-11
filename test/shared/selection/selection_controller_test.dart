import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/shared/selection/selection_controller.dart';
import 'package:submersion/shared/selection/selection_state.dart';

void main() {
  group('SelectionController entry and exit', () {
    test('starts inactive with nothing checked', () {
      final controller = SelectionController();
      expect(controller.value.isActive, isFalse);
      expect(controller.value.checkedIds, isEmpty);
      expect(controller.value.count, 0);
    });

    test('enterExplicit activates with nothing checked', () {
      final controller = SelectionController();
      controller.enterExplicit();
      expect(controller.value.isActive, isTrue);
      expect(controller.value.enteredExplicitly, isTrue);
      expect(controller.value.checkedIds, isEmpty);
    });

    test('enterImplicit activates and checks the given id', () {
      final controller = SelectionController();
      controller.enterImplicit('b');
      expect(controller.value.isActive, isTrue);
      expect(controller.value.enteredExplicitly, isFalse);
      expect(controller.value.checkedIds, {'b'});
      expect(controller.value.anchorId, 'b');
    });

    test('toggle adds then removes an id', () {
      final controller = SelectionController();
      controller.enterExplicit();
      controller.toggle('a');
      expect(controller.value.checkedIds, {'a'});
      controller.toggle('a');
      expect(controller.value.checkedIds, isEmpty);
    });

    test('implicit entry auto-exits when the last id is unchecked', () {
      final controller = SelectionController();
      controller.enterImplicit('a');
      controller.toggle('a');
      expect(controller.value.isActive, isFalse);
    });

    test('explicit entry stays active at zero checked', () {
      final controller = SelectionController();
      controller.enterExplicit();
      controller.toggle('a');
      controller.toggle('a');
      expect(controller.value.isActive, isTrue);
      expect(controller.value.count, 0);
    });

    test('exit clears everything', () {
      final controller = SelectionController();
      controller.enterImplicit('a');
      controller.toggle('b');
      controller.exit();
      expect(controller.value, SelectionState.inactive);
    });

    test('notifies listeners on each transition', () {
      final controller = SelectionController();
      var notifications = 0;
      controller.addListener(() => notifications++);
      controller.enterExplicit();
      controller.toggle('a');
      controller.exit();
      expect(notifications, 3);
    });
  });
}
