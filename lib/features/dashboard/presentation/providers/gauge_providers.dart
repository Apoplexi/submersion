import 'package:submersion/core/constants/enums.dart';
import 'package:submersion/core/providers/provider.dart';

import 'package:submersion/features/dashboard/presentation/providers/dashboard_providers.dart';
import 'package:submersion/features/divers/domain/entities/diver.dart';
import 'package:submersion/features/divers/presentation/providers/diver_providers.dart';
import 'package:submersion/features/equipment/domain/entities/service_clock_status.dart';
import 'package:submersion/features/equipment/presentation/providers/equipment_providers.dart';
import 'package:submersion/features/safety/domain/services/no_fly_service.dart';
import 'package:submersion/features/safety/presentation/providers/no_fly_providers.dart';

/// The worst service clock for one equipment type, shown as one chip.
class GearGauge {
  final EquipmentType type;
  final String itemName;
  final ServiceClockStatus status;

  const GearGauge({
    required this.type,
    required this.itemName,
    required this.status,
  });
}

/// Always-on status values for the dashboard gauge strip.
class DashboardGauges {
  final List<GearGauge> gearGauges;
  final bool hasGear;
  final DiverInsurance? insurance;
  final NoFlyStatus? noFlyStatus;
  final int? daysSinceLastDive;

  const DashboardGauges({
    required this.gearGauges,
    required this.hasGear,
    required this.insurance,
    required this.noFlyStatus,
    required this.daysSinceLastDive,
  });
}

int _severityRank(ServiceClockSeverity s) => switch (s) {
  ServiceClockSeverity.overdue => 2,
  ServiceClockSeverity.dueSoon => 1,
  ServiceClockSeverity.ok => 0,
};

/// Reduces per-item service clocks to the single worst clock per
/// equipment type. Severity wins; ties resolve to the earlier dueDate
/// (null dueDates sort last).
List<GearGauge> worstGaugePerType(List<EquipmentClocks> clocks) {
  final best = <EquipmentType, GearGauge>{};
  for (final entry in clocks) {
    for (final status in entry.statuses) {
      final candidate = GearGauge(
        type: entry.item.type,
        itemName: entry.item.name,
        status: status,
      );
      final current = best[entry.item.type];
      if (current == null) {
        best[entry.item.type] = candidate;
        continue;
      }
      final rankNew = _severityRank(status.severity);
      final rankCur = _severityRank(current.status.severity);
      if (rankNew > rankCur) {
        best[entry.item.type] = candidate;
      } else if (rankNew == rankCur) {
        final newDue = status.dueDate;
        final curDue = current.status.dueDate;
        if (newDue != null && (curDue == null || newDue.isBefore(curDue))) {
          best[entry.item.type] = candidate;
        }
      }
    }
  }
  return best.values.toList();
}

/// Gear chips actually shown on the strip: only types whose worst clock
/// is due soon or overdue, worst first (overdue before due-soon, then
/// earliest due date, undated last), capped at [cap].
List<GearGauge> dueGearGauges(List<EquipmentClocks> clocks, {int cap = 6}) {
  final due = worstGaugePerType(
    clocks,
  ).where((g) => g.status.severity != ServiceClockSeverity.ok).toList();
  due.sort((a, b) {
    final bySeverity =
        _severityRank(b.status.severity) - _severityRank(a.status.severity);
    if (bySeverity != 0) return bySeverity;
    final ad = a.status.dueDate;
    final bd = b.status.dueDate;
    if (ad == null && bd == null) return 0;
    if (ad == null) return 1;
    if (bd == null) return -1;
    return ad.compareTo(bd);
  });
  return due.take(cap).toList();
}

/// Always-on gauges: due/overdue gear clocks (capped), insurance, no-fly,
/// days since last dive.
final dashboardGaugesProvider = FutureProvider<DashboardGauges>((ref) async {
  final clocks = await ref.watch(activeEquipmentClocksProvider.future);
  final diver = await ref.watch(currentDiverProvider.future);
  final noFly = await ref.watch(noFlyStatusProvider.future);
  final daysSince = await ref.watch(daysSinceLastDiveProvider.future);

  return DashboardGauges(
    gearGauges: dueGearGauges(clocks),
    hasGear: clocks.isNotEmpty,
    insurance: diver?.insurance,
    noFlyStatus: noFly,
    daysSinceLastDive: daysSince,
  );
});
