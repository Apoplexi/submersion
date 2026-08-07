import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:submersion/features/dive_log/domain/entities/safety_finding.dart';
import 'package:submersion/features/dive_log/presentation/widgets/safety_finding_highlight.dart';

void main() {
  final scheme = ColorScheme.fromSeed(seedColor: Colors.blue);
  final now = DateTime.utc(2026, 8, 7);

  SafetyFinding finding({
    SafetySeverity severity = SafetySeverity.caution,
    int? start = 300,
    int? end = 420,
  }) => SafetyFinding(
    id: 'f1',
    diveId: 'dive-1',
    ruleId: SafetyRuleId.rapidAscent,
    severity: severity,
    startTimestamp: start,
    endTimestamp: end,
    value: 12.0,
    engineVersion: 1,
    createdAt: now,
  );

  group('safetySeverityColor', () {
    test('significant maps to tertiary', () {
      expect(
        safetySeverityColor(SafetySeverity.significant, scheme),
        scheme.tertiary,
      );
    });

    test('info and caution stay neutral', () {
      expect(
        safetySeverityColor(SafetySeverity.info, scheme),
        scheme.onSurfaceVariant,
      );
      expect(
        safetySeverityColor(SafetySeverity.caution, scheme),
        scheme.onSurfaceVariant,
      );
    });
  });

  group('profileHighlightRangeFor', () {
    test('maps a finding to its range and severity color', () {
      final range = profileHighlightRangeFor(
        finding(severity: SafetySeverity.significant),
        scheme,
      );
      expect(range, isNotNull);
      expect(range!.startTimestamp, 300);
      expect(range.endTimestamp, 420);
      expect(range.color, scheme.tertiary);
    });

    test('returns null for a null finding', () {
      expect(profileHighlightRangeFor(null, scheme), isNull);
    });

    test('returns null when either timestamp is missing', () {
      expect(profileHighlightRangeFor(finding(start: null), scheme), isNull);
      expect(profileHighlightRangeFor(finding(end: null), scheme), isNull);
    });
  });
}
