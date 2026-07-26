import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'package:submersion/core/constants/units.dart';
import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/reef/domain/entities/reef_data_status.dart';
import 'package:submersion/features/reef/domain/entities/reef_health.dart';
import 'package:submersion/features/reef/domain/services/bleaching_alert_level.dart';
import 'package:submersion/features/settings/presentation/providers/settings_providers.dart';

/// One row of the reef section: thermal stress and bleaching risk.
///
/// Degree Heating Weeks is rendered next to the alert level, never behind a
/// tap. The level is an instantaneous classification while the damage it
/// implies is cumulative, so a reef mid-mortality can read "Bleaching Watch".
class ReefHealthCard extends ConsumerWidget {
  final ReefPart<ReefHealth> part;

  const ReefHealthCard({super.key, required this.part});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (part.status == ReefDataStatus.unavailable) {
      return ListTile(
        leading: Icon(Icons.thermostat, color: scheme.primary),
        title: Text('Reef health', style: theme.textTheme.titleSmall),
        subtitle: const Text('Could not check reef health right now'),
        dense: true,
      );
    }
    if (part.status == ReefDataStatus.empty) {
      return ListTile(
        leading: Icon(Icons.thermostat, color: scheme.primary),
        title: Text('Reef health', style: theme.textTheme.titleSmall),
        subtitle: const Text('No reef health data for this location'),
        dense: true,
      );
    }

    final health = part.value!;
    final tempUnit = ref.watch(temperatureUnitProvider);

    final lines = <String>[];
    final level = health.alertLevel;
    if (level != null) lines.add(_levelLabel(level));
    if (health.degreeHeatingWeeks != null) {
      lines.add(
        'Degree Heating Weeks '
        '${health.degreeHeatingWeeks!.toStringAsFixed(1)} C-weeks',
      );
    }
    if (health.sst != null) {
      final value = TemperatureUnit.celsius.convert(health.sst!, tempUnit);
      lines.add('Sea surface ${value.toStringAsFixed(1)}${tempUnit.symbol}');
    }
    lines.add(
      'As of ${DateFormat.yMMMd().format(health.observedAt.toLocal())}',
    );

    return ListTile(
      leading: Icon(Icons.thermostat, color: scheme.primary),
      title: Text('Reef health', style: theme.textTheme.titleSmall),
      subtitle: Text(lines.join('\n')),
      isThreeLine: true,
      dense: true,
    );
  }

  String _levelLabel(BleachingAlertLevel level) => switch (level) {
    BleachingAlertLevel.noStress => 'No thermal stress',
    BleachingAlertLevel.watch => 'Bleaching watch',
    BleachingAlertLevel.warning => 'Bleaching warning',
    BleachingAlertLevel.alertLevel1 => 'Bleaching alert level 1',
    BleachingAlertLevel.alertLevel2 => 'Bleaching alert level 2',
    BleachingAlertLevel.alertLevel3 => 'Bleaching alert level 3',
    BleachingAlertLevel.alertLevel4 => 'Bleaching alert level 4',
    BleachingAlertLevel.alertLevel5 => 'Bleaching alert level 5',
  };
}
