import 'package:drift/drift.dart';

import 'package:submersion/core/buoyancy/weight_observation.dart';
import 'package:submersion/core/constants/enums.dart';
import 'package:submersion/core/database/database.dart';
import 'package:submersion/core/services/database_service.dart';

/// Assembles weight-prediction training rows from the dive log.
///
/// Four batch queries (dives, dive_weights, dive_equipment, dive_tanks) --
/// no per-dive N+1. Only dives that recorded any weight qualify.
class WeightHistoryRepository {
  WeightHistoryRepository([AppDatabase? db]) : _dbOverride = db;

  final AppDatabase? _dbOverride;
  AppDatabase get _db => _dbOverride ?? DatabaseService.instance.database;

  /// All dives of [diverId] that recorded any weight, ordered oldest-first.
  Future<List<WeightObservation>> observationsForDiver(String diverId) async {
    final diveRows =
        await (_db.select(_db.dives)
              ..where((d) => d.diverId.equals(diverId))
              ..orderBy([(d) => OrderingTerm.asc(d.diveDateTime)]))
            .get();
    if (diveRows.isEmpty) return const [];

    final diveIds = diveRows.map((d) => d.id).toList();

    final weightRows = await (_db.select(
      _db.diveWeights,
    )..where((w) => w.diveId.isIn(diveIds))).get();
    final equipmentRows = await (_db.select(
      _db.diveEquipment,
    )..where((e) => e.diveId.isIn(diveIds))).get();
    final tankRows = await (_db.select(
      _db.diveTanks,
    )..where((t) => t.diveId.isIn(diveIds))).get();

    final weightsByDive = <String, List<DiveWeight>>{};
    for (final row in weightRows) {
      weightsByDive.putIfAbsent(row.diveId, () => []).add(row);
    }
    final equipmentByDive = <String, List<String>>{};
    for (final row in equipmentRows) {
      equipmentByDive.putIfAbsent(row.diveId, () => []).add(row.equipmentId);
    }
    final tanksByDive = <String, List<ObservedTank>>{};
    for (final row in tankRows) {
      tanksByDive
          .putIfAbsent(row.diveId, () => [])
          .add(
            ObservedTank(
              volumeL: row.volume,
              workingPressureBar: row.workingPressure,
              material: row.tankMaterial != null
                  ? TankMaterial.values.firstWhere(
                      (m) => m.name == row.tankMaterial,
                      orElse: () => TankMaterial.aluminum,
                    )
                  : null,
              presetName: row.presetName,
            ),
          );
    }

    final observations = <WeightObservation>[];
    for (final dive in diveRows) {
      final typedWeights = weightsByDive[dive.id] ?? const [];
      final placement = <String, double>{};
      var carried = 0.0;
      for (final w in typedWeights) {
        carried += w.amountKg;
        placement.update(
          w.weightType,
          (v) => v + w.amountKg,
          ifAbsent: () => w.amountKg,
        );
      }
      if (typedWeights.isEmpty) {
        carried = dive.weightAmount ?? 0.0;
      }
      if (carried <= 0) continue;

      observations.add(
        WeightObservation(
          diveId: dive.id,
          diveDateTime: DateTime.fromMillisecondsSinceEpoch(dive.diveDateTime),
          waterType: dive.waterType != null
              ? WaterType.values.firstWhere(
                  (w) => w.name == dive.waterType,
                  orElse: () => WaterType.salt,
                )
              : null,
          carriedKg: carried,
          placement: placement,
          equipmentIds: equipmentByDive[dive.id] ?? const [],
          tanks: tanksByDive[dive.id] ?? const [],
          feedback: dive.weightingFeedback,
          feedbackKg: dive.weightingFeedbackKg,
        ),
      );
    }
    return observations;
  }
}
