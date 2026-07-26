import 'package:flutter/material.dart';

import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/dive_sites/domain/entities/dive_site.dart';
import 'package:submersion/features/marine_life/data/services/species_seed_service.dart';
import 'package:submersion/features/marine_life/domain/entities/species.dart';
import 'package:submersion/features/marine_life/presentation/providers/species_providers.dart';
import 'package:submersion/features/marine_life/presentation/utils/species_category_color.dart';
import 'package:submersion/features/marine_life/presentation/utils/species_category_icon.dart';
import 'package:submersion/features/reef/domain/entities/reef_data_status.dart';
import 'package:submersion/features/reef/presentation/providers/reef_providers.dart';

/// Species recorded near a dive site, shown beneath Spotted and Expected.
///
/// Records matching the built-in catalog render with a common name, icon and
/// colour and can be added to the Expected list in one tap. Unmatched records
/// are the regional long tail and show scientific names only.
class NearbySpeciesTier extends ConsumerWidget {
  final String siteId;
  final GeoPoint location;

  const NearbySpeciesTier({
    super.key,
    required this.siteId,
    required this.location,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final snapshotAsync = ref.watch(reefSnapshotProvider(location));

    return snapshotAsync.maybeWhen(
      data: (snapshot) {
        final part = snapshot.species;
        if (part.status != ReefDataStatus.ok || part.value!.isEmpty) {
          return const SizedBox.shrink();
        }
        final species = part.value!;

        return FutureBuilder<List<Species>>(
          future: SpeciesSeedService.loadBundledSpecies(),
          builder: (context, catalogSnapshot) {
            final catalog = catalogSnapshot.data ?? const <Species>[];
            final byId = {for (final s in catalog) s.id: s};

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Recorded nearby', style: theme.textTheme.labelLarge),
                const SizedBox(height: 8),
                for (final match in species.matched)
                  if (byId[match.speciesId] case final Species s)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        iconForSpeciesCategory(s.category),
                        color: colorForSpeciesCategory(
                          s.category,
                          theme.brightness,
                        ),
                      ),
                      title: Text(s.commonName),
                      subtitle: s.scientificName == null
                          ? null
                          : Text(s.scientificName!),
                      trailing: IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        tooltip: 'Add to expected species',
                        onPressed: () => ref
                            .read(
                              siteExpectedSpeciesNotifierProvider(
                                siteId,
                              ).notifier,
                            )
                            .addSpecies(s.id),
                      ),
                    ),
                for (final name in species.unmatchedNames)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.help_outline),
                    title: Text(name, style: theme.textTheme.bodyMedium),
                  ),
              ],
            );
          },
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}
