import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:submersion/core/providers/provider.dart';

import 'package:submersion/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:submersion/features/equipment/domain/entities/service_clock_status.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// Compact banner listing only genuinely urgent items: overdue service
/// and expired insurance. Hidden otherwise.
class UrgentBanner extends ConsumerWidget {
  const UrgentBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(dashboardAlertsProvider);
    final alerts = alertsAsync.valueOrNull;
    if (alerts == null) return const SizedBox.shrink();

    final overdue = alerts.serviceClocksDue
        .where((c) => c.status.severity == ServiceClockSeverity.overdue)
        .toList();
    final urgent = overdue.isNotEmpty || alerts.insuranceExpired;
    if (!urgent) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final lines = <String>[
      for (final clock in overdue)
        context.l10n.dashboard_gauges_gearOverdue(clock.item.name),
      if (alerts.insuranceExpired)
        context.l10n.dashboard_gauges_insuranceExpired,
    ];
    return Card(
      margin: EdgeInsets.zero,
      color: scheme.errorContainer,
      child: InkWell(
        onTap: () => context.go('/gear'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.dashboard_urgent_title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: scheme.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    for (final line in lines)
                      Text(
                        line,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onErrorContainer,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
