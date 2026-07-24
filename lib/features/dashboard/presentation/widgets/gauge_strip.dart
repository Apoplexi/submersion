import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:submersion/core/providers/provider.dart';

import 'package:submersion/features/dashboard/presentation/providers/gauge_providers.dart';
import 'package:submersion/features/equipment/domain/entities/service_clock_status.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// Always-on status chips: gear service clocks, insurance, no-fly,
/// dive currency. Neutral when fine, tinted when due or overdue.
class GaugeStrip extends ConsumerWidget {
  const GaugeStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gaugesAsync = ref.watch(dashboardGaugesProvider);
    return gaugesAsync.when(
      data: (g) => _buildStrip(context, g),
      loading: () => const SizedBox(height: 40),
      // Always-on block: contained error with a retry affordance instead
      // of vanishing.
      error: (_, _) => Align(
        alignment: Alignment.centerLeft,
        child: _chip(
          context,
          icon: Icons.refresh,
          label: context.l10n.dashboard_gauges_retry,
          tone: _Tone.neutral,
          onTap: () => ref.invalidate(dashboardGaugesProvider),
        ),
      ),
    );
  }

  Widget _buildStrip(BuildContext context, DashboardGauges g) {
    final l10n = context.l10n;
    final chips = <Widget>[];

    if (!g.hasGear) {
      chips.add(
        _chip(
          context,
          icon: Icons.add,
          label: l10n.dashboard_gauges_addGear,
          tone: _Tone.neutral,
          onTap: () => context.go('/gear'),
        ),
      );
    } else {
      for (final gauge in g.gearGauges) {
        final (label, tone) = switch (gauge.status.severity) {
          ServiceClockSeverity.overdue => (
            l10n.dashboard_gauges_gearOverdue(gauge.itemName),
            _Tone.alert,
          ),
          ServiceClockSeverity.dueSoon => (
            l10n.dashboard_gauges_gearDueIn(
              gauge.itemName,
              gauge.status.daysUntilDue ?? 0,
            ),
            _Tone.warn,
          ),
          ServiceClockSeverity.ok => (
            l10n.dashboard_gauges_gearOk(gauge.itemName),
            _Tone.ok,
          ),
        };
        chips.add(
          _chip(
            context,
            icon: Icons.build_outlined,
            label: label,
            tone: tone,
            onTap: () => context.go('/gear'),
          ),
        );
      }
    }

    final insurance = g.insurance;
    if (insurance == null || insurance.expiryDate == null) {
      chips.add(
        _chip(
          context,
          icon: Icons.health_and_safety_outlined,
          label: l10n.dashboard_gauges_noInsurance,
          tone: _Tone.neutral,
        ),
      );
    } else if (insurance.isExpired) {
      chips.add(
        _chip(
          context,
          icon: Icons.health_and_safety_outlined,
          label: l10n.dashboard_gauges_insuranceExpired,
          tone: _Tone.alert,
        ),
      );
    } else if (insurance.isExpiringSoon) {
      chips.add(
        _chip(
          context,
          icon: Icons.health_and_safety_outlined,
          label: l10n.dashboard_gauges_insuranceExpires(
            DateFormat.yMMMd(
              Localizations.localeOf(context).toString(),
            ).format(insurance.expiryDate!),
          ),
          tone: _Tone.warn,
        ),
      );
    } else {
      chips.add(
        _chip(
          context,
          icon: Icons.health_and_safety_outlined,
          label: l10n.dashboard_gauges_insuranceOk,
          tone: _Tone.ok,
        ),
      );
    }

    final noFly = g.noFlyStatus;
    final now = DateTime.now().toUtc();
    if (noFly != null && noFly.isActiveAt(now)) {
      final remaining = noFly.remaining(now);
      chips.add(
        _chip(
          context,
          icon: Icons.flight_outlined,
          label: l10n.dashboard_gauges_noFlyRemaining(
            remaining.inHours.toString(),
            (remaining.inMinutes % 60).toString().padLeft(2, '0'),
          ),
          tone: _Tone.warn,
        ),
      );
    } else {
      chips.add(
        _chip(
          context,
          icon: Icons.flight_outlined,
          label: l10n.dashboard_gauges_noFlyClear,
          tone: _Tone.ok,
        ),
      );
    }

    final days = g.daysSinceLastDive;
    chips.add(
      _chip(
        context,
        icon: Icons.scuba_diving,
        label: days == null
            ? l10n.dashboard_gauges_noDivesYet
            : days == 0
            ? l10n.dashboard_gauges_lastDiveToday
            : l10n.dashboard_gauges_lastDiveDays(days),
        tone: _Tone.neutral,
      ),
    );

    return Wrap(spacing: 8, runSpacing: 8, children: chips);
  }

  Widget _chip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required _Tone tone,
    VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final (bg, fg) = switch (tone) {
      _Tone.alert => (scheme.errorContainer, scheme.onErrorContainer),
      _Tone.warn => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      _Tone.ok => (scheme.secondaryContainer, scheme.onSecondaryContainer),
      _Tone.neutral => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
    };
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: fg),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Tone { neutral, ok, warn, alert }
