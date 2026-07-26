import 'package:flutter/material.dart';

import 'package:submersion/features/reef/domain/entities/reef_data_status.dart';
import 'package:submersion/features/reef/domain/entities/reef_habitat.dart';

/// One row of the reef section: reef presence and threat classification.
class ReefHabitatCard extends StatelessWidget {
  final ReefPart<ReefHabitat> part;

  const ReefHabitatCard({super.key, required this.part});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final String text;
    switch (part.status) {
      case ReefDataStatus.ok:
        final threat = part.value!.threatLevel;
        text = threat == null
            ? 'On a coral reef'
            : 'On a coral reef, threat level $threat';
      case ReefDataStatus.empty:
        text = 'No mapped coral reef at this location';
      case ReefDataStatus.unavailable:
        text = 'Could not check reef habitat right now';
    }

    return ListTile(
      leading: Icon(Icons.waves, color: scheme.primary),
      title: Text('Reef habitat', style: theme.textTheme.titleSmall),
      subtitle: Text(text),
      dense: true,
    );
  }
}
