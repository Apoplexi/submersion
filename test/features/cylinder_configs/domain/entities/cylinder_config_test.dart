import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/constants/enums.dart';
import 'package:submersion/features/cylinder_configs/domain/entities/cylinder_config.dart';
import 'package:submersion/features/cylinder_configs/domain/entities/cylinder_config_item.dart';

void main() {
  final now = DateTime.utc(2026, 8, 5);

  CylinderConfigItem item({
    String id = 'i1',
    TankRole role = TankRole.bailout,
    double o2 = 21,
  }) => CylinderConfigItem(
    id: id,
    configId: 'c1',
    tankRole: role,
    o2Percent: o2,
    createdAt: now,
    updatedAt: now,
  );

  test('a config with an equipmentId is owned by a unit', () {
    final owned = CylinderConfig(
      id: 'c1',
      name: 'JJ trimix',
      equipmentId: 'rb-1',
      createdAt: now,
      updatedAt: now,
    );
    expect(owned.isOwnedByUnit, isTrue);

    final generic = owned.copyWith(clearEquipmentId: true);
    expect(generic.isOwnedByUnit, isFalse);
    expect(generic.name, 'JJ trimix');
  });

  test('items default to air and back gas is not assumed', () {
    final i = item();
    expect(i.o2Percent, 21);
    expect(i.hePercent, 0);
    expect(i.tankRole, TankRole.bailout);
    expect(i.volumeL, isNull);
    expect(i.tankMaterial, isNull);
    expect(i.defaultStartPressureBar, isNull);
    expect(i.label, isNull);
  });

  test('equality is by value, so provider rebuilds are stable', () {
    expect(item(), equals(item()));
    expect(item(o2: 32), isNot(equals(item())));
  });

  test('timestamps are excluded from equality', () {
    final a = item();
    final b = a.copyWith(updatedAt: now.add(const Duration(days: 1)));
    expect(a, equals(b));
  });

  test('copyWith replaces the item list wholesale', () {
    final config = CylinderConfig(
      id: 'c1',
      name: 'Doubles + 50',
      createdAt: now,
      updatedAt: now,
      items: [item(id: 'a')],
    );
    final updated = config.copyWith(
      items: [
        item(id: 'a'),
        item(id: 'b'),
      ],
    );
    expect(config.items.length, 1);
    expect(updated.items.length, 2);
  });

  test('clear flags null out optional item fields', () {
    final full = item().copyWith(
      volumeL: 11.1,
      workingPressureBar: 207,
      tankMaterial: TankMaterial.aluminum,
      defaultStartPressureBar: 200,
      label: 'Bailout 1',
    );
    expect(full.volumeL, 11.1);

    final cleared = full.copyWith(
      clearVolumeL: true,
      clearWorkingPressureBar: true,
      clearTankMaterial: true,
      clearDefaultStartPressureBar: true,
      clearLabel: true,
    );
    expect(cleared.volumeL, isNull);
    expect(cleared.workingPressureBar, isNull);
    expect(cleared.tankMaterial, isNull);
    expect(cleared.defaultStartPressureBar, isNull);
    expect(cleared.label, isNull);
    // Gas is not clearable: it always has a concrete value.
    expect(cleared.o2Percent, 21);
  });
}
