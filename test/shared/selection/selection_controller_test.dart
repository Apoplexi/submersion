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

  group('idsInRange', () {
    const ordered = ['a', 'b', 'c', 'd', 'e'];

    test('is inclusive of both ends', () {
      expect(idsInRange(ordered, 'b', 'd'), ['b', 'c', 'd']);
    });

    test('is order-independent', () {
      expect(idsInRange(ordered, 'd', 'b'), ['b', 'c', 'd']);
    });

    test('returns the single id when anchor equals target', () {
      expect(idsInRange(ordered, 'c', 'c'), ['c']);
    });

    test('returns empty when an id is not present', () {
      expect(idsInRange(ordered, 'z', 'c'), isEmpty);
      expect(idsInRange(ordered, 'c', 'z'), isEmpty);
    });
  });

  group('SelectionController.extendTo', () {
    const ordered = ['a', 'b', 'c', 'd', 'e'];

    test(
      'activates implicitly and checks the range from the fallback anchor',
      () {
        final controller = SelectionController();
        controller.extendTo('d', ordered, fallbackAnchorId: 'b');
        expect(controller.value.isActive, isTrue);
        expect(controller.value.enteredExplicitly, isFalse);
        expect(controller.value.checkedIds, {'b', 'c', 'd'});
        expect(controller.value.anchorId, 'b');
      },
    );

    test('checks only the target when there is no anchor to fall back on', () {
      final controller = SelectionController();
      controller.extendTo('d', ordered);
      expect(controller.value.checkedIds, {'d'});
      expect(controller.value.anchorId, 'd');
    });

    test('keeps the anchor fixed across consecutive extends', () {
      final controller = SelectionController();
      controller.enterImplicit('b');
      controller.extendTo('d', ordered);
      expect(controller.value.checkedIds, {'b', 'c', 'd'});
      controller.extendTo('c', ordered);
      expect(controller.value.anchorId, 'b');
      expect(controller.value.checkedIds, containsAll({'b', 'c', 'd'}));
    });

    test('adds to an existing selection rather than replacing it', () {
      final controller = SelectionController();
      controller.enterImplicit('a');
      controller.toggle('e');
      // toggle moved the anchor to 'e', so the range runs e -> c and the
      // fallback anchor is ignored. 'a' survives because extendTo adds.
      controller.extendTo('c', ordered, fallbackAnchorId: 'b');
      expect(controller.value.checkedIds, {'a', 'c', 'd', 'e'});
    });

    test('ignores the fallback anchor once the controller has its own', () {
      final controller = SelectionController();
      controller.enterImplicit('d');
      controller.extendTo('e', ordered, fallbackAnchorId: 'a');
      expect(controller.value.checkedIds, {'d', 'e'});
    });

    test('ignores a target that is not in the visible list', () {
      final controller = SelectionController();
      controller.enterImplicit('a');
      controller.extendTo('zz', ordered);
      expect(controller.value.checkedIds, {'a'});
    });
  });
}
