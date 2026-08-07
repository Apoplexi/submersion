import 'package:flutter/material.dart';

import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/core/utils/unit_formatter.dart';
import 'package:submersion/features/dive_planner/presentation/providers/dive_planner_providers.dart';
import 'package:submersion/features/planner/presentation/providers/plan_canvas_providers.dart';
import 'package:submersion/features/planner/presentation/widgets/plan_status_chips.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// Selector for the ghosted contingency: Base / +depth / +time / both.
/// Hidden when the plan has no segments.
class ContingencyChips extends ConsumerWidget {
  const ContingencyChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(divePlanNotifierProvider);
    if (state.segments.isEmpty) return const SizedBox.shrink();
    final selected = ref.watch(selectedDeviationProvider);
    final units = UnitFormatter(ref.watch(settingsProvider));

    final depthLabel =
        '+${units.formatDepth(state.deviationDepthDelta, decimals: 0)}';
    final timeLabel = '+${state.deviationTimeMinutes}′';

    void select(String? key) =>
        ref.read(selectedDeviationProvider.notifier).state = key;

    Widget chip(String? key, String label) => InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => select(key),
      child: PlanChip(label: label, emphasized: selected == key),
    );

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        chip(null, context.l10n.plannerCanvas_contingency_base),
        chip('deeper', depthLabel),
        chip('longer', timeLabel),
        chip('both', '$depthLabel $timeLabel'),
      ],
    );
  }
}
