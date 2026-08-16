import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:submersion/core/constants/enums.dart';
import 'package:submersion/features/equipment/presentation/utils/equipment_type_icon.dart';

void main() {
  test('every equipment type resolves to an icon', () {
    for (final type in EquipmentType.values) {
      expect(equipmentTypeIcon(type), isA<IconData>(), reason: type.name);
    }
  });

  test('a DPV shows the scooter glyph everywhere', () {
    expect(equipmentTypeIcon(EquipmentType.dpv), Icons.electric_scooter);
  });

  test('only the catch-all type gets the generic glyph', () {
    // The list and detail pages used to fall through to a generic icon for
    // every type their switch had not caught up with (rebreather, smb, reel,
    // knife, hood, gloves, boots, and any new type). A shared exhaustive
    // helper means "generic" is now a deliberate choice for `other` alone.
    final generic = equipmentTypeIcon(EquipmentType.other);
    for (final type in EquipmentType.values) {
      if (type == EquipmentType.other) continue;
      expect(
        equipmentTypeIcon(type),
        isNot(generic),
        reason: '${type.name} should have its own glyph',
      );
    }
  });

  test('the two exposure suits deliberately share one glyph', () {
    expect(
      equipmentTypeIcon(EquipmentType.wetsuit),
      equipmentTypeIcon(EquipmentType.drysuit),
    );
  });
}
