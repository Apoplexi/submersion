import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/services/sync/sync_data_serializer.dart';
import 'package:submersion/core/services/sync/sync_service.dart';

import '../../../helpers/test_database.dart';

void main() {
  late SyncDataSerializer serializer;

  setUp(() async {
    await setUpTestDatabase();
    serializer = SyncDataSerializer();
  });
  tearDown(tearDownTestDatabase);

  Future<void> seedUnit(String id) => serializer.upsertRecord('equipment', {
    'id': id,
    'name': 'JJ-CCR',
    'type': 'rebreather',
    'status': 'active',
    'purchaseCurrency': 'USD',
    'notes': '',
    'isActive': true,
    'createdAt': 1000,
    'updatedAt': 1000,
  });

  Future<void> seedConfig(String id, {String? equipmentId}) =>
      serializer.upsertRecord('cylinderConfigs', {
        'id': id,
        'equipmentId': equipmentId,
        'name': 'JJ trimix',
        'description': '',
        'sortOrder': 0,
        'createdAt': 1000,
        'updatedAt': 1000,
      });

  Future<void> seedItem(
    String id,
    String configId, {
    String role = 'diluent',
    double o2 = 18,
    double he = 45,
  }) => serializer.upsertRecord('cylinderConfigItems', {
    'id': id,
    'configId': configId,
    'sortOrder': 0,
    'tankRole': role,
    'o2Percent': o2,
    'hePercent': he,
    'createdAt': 1000,
    'updatedAt': 1000,
  });

  test('a config and its items export intact', () async {
    await seedUnit('rb-1');
    await seedConfig('c1', equipmentId: 'rb-1');
    await seedItem('i1', 'c1');

    final payload = await serializer.exportData(
      deviceId: 'test-device',
      deletions: const [],
    );

    final configs = payload.data.cylinderConfigs;
    expect(configs.map((c) => c['id']), contains('c1'));
    expect(configs.single['equipmentId'], 'rb-1');

    final items = payload.data.cylinderConfigItems;
    expect(items.map((i) => i['id']), contains('i1'));
    expect(items.single['o2Percent'], 18);
    expect(items.single['hePercent'], 45);
    expect(items.single['tankRole'], 'diluent');
  });

  test('a generic gas plan with no owning unit round-trips', () async {
    await seedConfig('c1');
    await seedItem('i1', 'c1', role: 'backGas', o2: 21, he: 0);

    final payload = await serializer.exportData(
      deviceId: 'test-device',
      deletions: const [],
    );

    expect(payload.data.cylinderConfigs.single['equipmentId'], isNull);
  });

  test('the exported payload survives a JSON round-trip', () async {
    await seedConfig('c1');
    await seedItem('i1', 'c1');

    final payload = await serializer.exportData(
      deviceId: 'test-device',
      deletions: const [],
    );
    final revived = SyncData.fromJson(payload.data.toJson());

    expect(revived.cylinderConfigs.map((c) => c['id']), contains('c1'));
    expect(revived.cylinderConfigItems.map((i) => i['id']), contains('i1'));
  });

  test('parentRefs guards every FK to a deletable parent', () {
    // The merge applies remote records in a deferred-FK transaction. An
    // unguarded FK to a locally-deleted parent dangles and fails the whole
    // sync at COMMIT (SqliteException 787). Merge ORDER is enforced by the
    // inline list in SyncService plus the no-silent-drift check in
    // sync_parent_refs_completeness_test; this pins the guards themselves.
    final configRefs = SyncService.parentRefs['cylinderConfigs']!;
    expect(
      configRefs.map((r) => '${r.field}->${r.parent}:${r.nullable}'),
      containsAll([
        'diverId->divers:true',
        // Nullable by design: deleting a rebreather demotes its configs to
        // generic gas plans rather than destroying them, so the reference is
        // cleared instead of the row being skipped.
        'equipmentId->equipment:true',
      ]),
    );

    final itemRefs = SyncService.parentRefs['cylinderConfigItems']!;
    expect(
      itemRefs.map((r) => '${r.field}->${r.parent}:${r.nullable}'),
      contains('configId->cylinderConfigs:false'),
    );
  });

  test('both entities declare updatedAt so HLC comparison works', () {
    expect(SyncService.entityHasUpdatedAt['cylinderConfigs'], isTrue);
    expect(SyncService.entityHasUpdatedAt['cylinderConfigItems'], isTrue);
  });

  test('deleting a config through the serializer removes it', () async {
    await seedConfig('c1');
    await seedItem('i1', 'c1');

    await serializer.deleteRecord('cylinderConfigItems', 'i1');
    await serializer.deleteRecord('cylinderConfigs', 'c1');

    final payload = await serializer.exportData(
      deviceId: 'test-device',
      deletions: const [],
    );
    expect(payload.data.cylinderConfigs, isEmpty);
    expect(payload.data.cylinderConfigItems, isEmpty);
  });
}
