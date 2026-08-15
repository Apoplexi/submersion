import 'package:flutter/material.dart';
import 'package:submersion/core/constants/enums.dart';
import 'package:submersion/core/icons/mdi_icons.dart';

/// The glyph that stands for [type] everywhere it appears: the equipment list,
/// the equipment detail header, the dive-edit gear row, and the equipment
/// picker sheet.
///
/// The switch is exhaustive on purpose. Four copies of this mapping used to
/// live in those four files, two of them ending in a generic fallback, so a
/// new equipment type silently rendered as a backpack in half the app while
/// the compiler stayed quiet. With no default arm, the next type added to
/// [EquipmentType] is a build error here instead.
IconData equipmentTypeIcon(EquipmentType type) {
  switch (type) {
    case EquipmentType.regulator:
      return Icons.air;
    case EquipmentType.bcd:
      return Icons.checkroom;
    // One glyph for both exposure suits: they are the same silhouette, and
    // the item's own name carries the wet/dry distinction.
    case EquipmentType.wetsuit:
    case EquipmentType.drysuit:
      return Icons.dry_cleaning;
    case EquipmentType.mask:
      return Icons.visibility;
    case EquipmentType.fins:
      return Icons.water;
    case EquipmentType.boots:
      return Icons.hiking;
    case EquipmentType.gloves:
      return Icons.pan_tool;
    case EquipmentType.hood:
      return Icons.face;
    case EquipmentType.tank:
      return MdiIcons.divingScubaTank;
    // A closed circuit recycles the breathing loop; the vendored MdiIcons
    // subset has no rebreather glyph, and the tank glyph already means
    // "tank".
    case EquipmentType.rebreather:
      return Icons.recycling;
    case EquipmentType.transmitter:
      return Icons.sensors;
    case EquipmentType.weights:
      return Icons.fitness_center;
    case EquipmentType.computer:
      return Icons.watch;
    case EquipmentType.light:
      return Icons.flashlight_on;
    case EquipmentType.camera:
      return Icons.camera_alt;
    case EquipmentType.knife:
      return Icons.content_cut;
    case EquipmentType.smb:
      return Icons.flag;
    case EquipmentType.reel:
      return Icons.all_inclusive;
    case EquipmentType.dpv:
      return Icons.electric_scooter;
    case EquipmentType.other:
      return Icons.build;
  }
}
