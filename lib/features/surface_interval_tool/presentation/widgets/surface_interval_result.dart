import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:submersion/features/surface_interval_tool/presentation/providers/surface_interval_providers.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// Display card showing the calculated minimum surface interval result.
/// Shows the minimum time needed between dives and current safety status.
class SurfaceIntervalResult extends ConsumerWidget {
  const SurfaceIntervalResult({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final minInterval = ref.watch(siMinimumIntervalProvider);
    final currentInterval = ref.watch(siSurfaceIntervalProvider);
    final ndlIsSafe = ref.watch(siSecondDiveIsSafeProvider);
    final gasIsSafe = ref.watch(siGasMixesAreSafeProvider);
    final ndl = ref.watch(siSecondDiveNdlProvider);

    // The card only reads as safe when the diver has both off-gassed enough
    // and picked a mix they can actually breathe at the planned depth.
    final isSafe = ndlIsSafe && gasIsSafe;

    // Format interval as hours:minutes
    final hours = minInterval ~/ 60;
    final minutes = minInterval % 60;
    final intervalText = hours > 0 ? '${hours}h ${minutes}m' : '$minutes min';

    // Format NDL for display
    String ndlText;
    if (ndl < 0) {
      ndlText = context.l10n.surfaceInterval_result_inDeco;
    } else {
      final ndlMinutes = ndl ~/ 60;
      ndlText = context.l10n.surfaceInterval_result_ndlMinutes(ndlMinutes);
    }

    // Current interval display
    final currentHours = currentInterval ~/ 60;
    final currentMinutes = currentInterval % 60;
    final currentText = currentHours > 0
        ? '${currentHours}h ${currentMinutes}m'
        : '$currentMinutes min';

    return Semantics(
      label: context.l10n.surfaceInterval_result_semantics(
        intervalText,
        currentText,
        ndlText,
        // Oxygen is the acute risk, so it leads when both are wrong.
        !gasIsSafe
            ? context.l10n.surfaceInterval_result_gasUnsafe
            : ndlIsSafe
            ? context.l10n.surfaceInterval_result_safeToDive
            : context.l10n.surfaceInterval_result_notYetSafe,
      ),
      child: Card(
        color: isSafe
            ? colorScheme.primaryContainer
            : colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Status Icon
              ExcludeSemantics(
                child: Icon(
                  isSafe ? Icons.check_circle : Icons.warning,
                  size: 48,
                  color: isSafe
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: 12),

              // Main Result
              Text(
                context.l10n.surfaceInterval_result_minimumInterval,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: isSafe
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                intervalText,
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isSafe
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onErrorContainer,
                ),
              ),
              const SizedBox(height: 16),

              // Divider
              Divider(
                color: isSafe
                    ? colorScheme.onPrimaryContainer.withValues(alpha: 0.2)
                    : colorScheme.onErrorContainer.withValues(alpha: 0.2),
              ),
              const SizedBox(height: 16),

              // Current interval vs minimum
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildInfoColumn(
                    context: context,
                    label: context.l10n.surfaceInterval_result_currentInterval,
                    value: currentText,
                    isSafe: isSafe,
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: isSafe
                        ? colorScheme.onPrimaryContainer.withValues(alpha: 0.2)
                        : colorScheme.onErrorContainer.withValues(alpha: 0.2),
                  ),
                  _buildInfoColumn(
                    context: context,
                    label: context.l10n.surfaceInterval_result_ndlForSecondDive,
                    value: ndlText,
                    isSafe: isSafe,
                  ),
                ],
              ),

              if (!gasIsSafe) ...[
                const SizedBox(height: 16),
                _ResultNotice(
                  icon: Icons.warning_amber,
                  message: context.l10n.surfaceInterval_result_gasUnsafe,
                ),
              ],

              if (!ndlIsSafe) ...[
                const SizedBox(height: 16),
                _ResultNotice(
                  icon: Icons.info_outline,
                  message: context.l10n.surfaceInterval_result_increaseInterval,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoColumn({
    required BuildContext context,
    required String label,
    required String value,
    required bool isSafe,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textColor = isSafe
        ? colorScheme.onPrimaryContainer
        : colorScheme.onErrorContainer;

    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: textColor.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
      ],
    );
  }
}

/// An explanatory banner inside the result card telling the diver what to fix.
class _ResultNotice extends StatelessWidget {
  const _ResultNotice({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          ExcludeSemantics(
            child: Icon(icon, size: 20, color: colorScheme.onErrorContainer),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
