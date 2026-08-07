import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:submersion/core/providers/provider.dart';
import 'package:submersion/features/cylinder_configs/domain/entities/cylinder_config.dart';
import 'package:submersion/features/cylinder_configs/presentation/providers/cylinder_config_providers.dart';
import 'package:submersion/features/equipment/presentation/providers/equipment_providers.dart';
import 'package:submersion/l10n/arb/app_localizations.dart';
import 'package:submersion/l10n/l10n_extension.dart';

/// Lists every configuration, grouped by owning rebreather with generic gas
/// plans last.
class CylinderConfigListPage extends ConsumerWidget {
  const CylinderConfigListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final configsAsync = ref.watch(cylinderConfigsProvider);
    final equipmentAsync = ref.watch(allEquipmentProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.cylinderConfigs_title)),
      body: configsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('$error')),
        data: (configs) {
          if (configs.isEmpty) {
            return _EmptyState(l10n: l10n);
          }

          final unitNames = <String, String>{
            for (final item in equipmentAsync.valueOrNull ?? const [])
              item.id: item.name,
          };

          final owned = <String, List<CylinderConfig>>{};
          final generic = <CylinderConfig>[];
          for (final config in configs) {
            final unitId = config.equipmentId;
            if (unitId == null) {
              generic.add(config);
            } else {
              owned.putIfAbsent(unitId, () => []).add(config);
            }
          }

          return ListView(
            children: [
              for (final entry in owned.entries) ...[
                _GroupHeader(
                  label: unitNames[entry.key] ?? l10n.cylinderConfigs_forUnit,
                ),
                for (final config in entry.value) _ConfigTile(config: config),
              ],
              if (generic.isNotEmpty) ...[
                _GroupHeader(label: l10n.cylinderConfigs_gasPlans),
                for (final config in generic) _ConfigTile(config: config),
              ],
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/equipment/cylinder-configs/new'),
        icon: const Icon(Icons.add),
        label: Text(l10n.cylinderConfigs_new),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.propane_tank_outlined,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.cylinderConfigs_empty,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.cylinderConfigs_emptyBody,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _ConfigTile extends StatelessWidget {
  const _ConfigTile({required this.config});

  final CylinderConfig config;

  @override
  Widget build(BuildContext context) {
    final roles = config.items.map((i) => i.tankRole.displayName).join(', ');
    return ListTile(
      title: Text(config.name),
      subtitle: roles.isEmpty ? null : Text(roles),
      trailing: Text('${config.cylinderCount}'),
      onTap: () => context.push('/equipment/cylinder-configs/${config.id}'),
    );
  }
}
