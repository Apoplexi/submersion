import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:submersion/features/reef/domain/entities/reef_data_status.dart';
import 'package:submersion/features/reef/domain/entities/reef_protection.dart';

/// One row of the reef section: marine protected area identity.
///
/// Activity permissions are intentionally absent. The source encodes them as
/// integers with no published codebook, so divers are sent to the
/// authoritative page rather than shown a guess.
class ReefProtectionCard extends StatelessWidget {
  final ReefPart<List<ReefProtection>> part;

  const ReefProtectionCard({super.key, required this.part});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (part.status == ReefDataStatus.unavailable) {
      return ListTile(
        leading: Icon(Icons.shield_outlined, color: scheme.primary),
        title: Text('Protected area', style: theme.textTheme.titleSmall),
        subtitle: const Text('Could not check protected status right now'),
        dense: true,
      );
    }
    if (part.status == ReefDataStatus.empty) {
      return ListTile(
        leading: Icon(Icons.shield_outlined, color: scheme.primary),
        title: Text('Protected area', style: theme.textTheme.titleSmall),
        subtitle: const Text('Not in a marine protected area'),
        dense: true,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final area in part.value!)
          ListTile(
            leading: Icon(Icons.shield_outlined, color: scheme.primary),
            title: Text(area.siteName, style: theme.textTheme.titleSmall),
            subtitle: Text(_subtitle(area)),
            trailing: area.navigatorLink == null
                ? null
                : TextButton(
                    onPressed: () => launchUrl(
                      Uri.parse(area.navigatorLink!),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: const Text('View regulations'),
                  ),
            dense: true,
          ),
      ],
    );
  }

  String _subtitle(ReefProtection area) {
    final parts = <String>[];
    if (area.country != null && area.country!.isNotEmpty) {
      parts.add(area.country!);
    }
    if (area.iucnCategory != null && area.iucnCategory!.isNotEmpty) {
      parts.add('IUCN ${area.iucnCategory}');
    }
    return parts.join(' - ');
  }
}
