import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/features/planner/domain/services/plan_name_generator.dart';

void main() {
  final date = DateTime(2026, 7, 25);

  group('generateDefaultPlanName', () {
    test('combines site, depth, and date', () {
      expect(
        generateDefaultPlanName(
          siteName: 'Blue Hole',
          depthLabel: '40m',
          date: date,
          fallbackLabel: 'Dive Plan',
        ),
        'Blue Hole 40m - Jul 25',
      );
    });

    test('omits the depth when no depth label is supplied', () {
      expect(
        generateDefaultPlanName(
          siteName: 'Blue Hole',
          depthLabel: null,
          date: date,
          fallbackLabel: 'Dive Plan',
        ),
        'Blue Hole - Jul 25',
      );
    });

    test('omits the site when no site name is supplied', () {
      expect(
        generateDefaultPlanName(
          siteName: null,
          depthLabel: '40m',
          date: date,
          fallbackLabel: 'Dive Plan',
        ),
        '40m - Jul 25',
      );
    });

    test('falls back to the supplied label when site and depth are absent', () {
      expect(
        generateDefaultPlanName(
          siteName: null,
          depthLabel: null,
          date: date,
          fallbackLabel: 'Dive Plan',
        ),
        'Dive Plan - Jul 25',
      );
    });

    test('treats a blank site name as absent', () {
      expect(
        generateDefaultPlanName(
          siteName: '   ',
          depthLabel: null,
          date: date,
          fallbackLabel: 'Dive Plan',
        ),
        'Dive Plan - Jul 25',
      );
    });

    test('trims surrounding whitespace on the site name', () {
      expect(
        generateDefaultPlanName(
          siteName: '  Blue Hole  ',
          depthLabel: '40m',
          date: date,
          fallbackLabel: 'Dive Plan',
        ),
        'Blue Hole 40m - Jul 25',
      );
    });
  });
}
