import 'package:flutter/material.dart';

import 'package:submersion/features/dive_log/domain/entities/safety_finding.dart';
import 'package:submersion/features/dive_log/presentation/widgets/profile_highlight_range.dart';

/// Severity accent shared by the finding tile icon and the chart highlight.
/// Follows the safety spec's tone rules (muted, no alarm red): significant
/// maps to tertiary, everything else stays neutral.
Color safetySeverityColor(SafetySeverity severity, ColorScheme colorScheme) {
  return switch (severity) {
    SafetySeverity.significant => colorScheme.tertiary,
    SafetySeverity.info ||
    SafetySeverity.caution => colorScheme.onSurfaceVariant,
  };
}

/// Maps the selected finding to the chart's highlight parameter. Returns null
/// when nothing is selected or the finding has no profile time range.
ProfileHighlightRange? profileHighlightRangeFor(
  SafetyFinding? finding,
  ColorScheme colorScheme,
) {
  if (finding == null) return null;
  final start = finding.startTimestamp;
  final end = finding.endTimestamp;
  if (start == null || end == null) return null;
  return ProfileHighlightRange(
    startTimestamp: start,
    endTimestamp: end,
    color: safetySeverityColor(finding.severity, colorScheme),
  );
}
