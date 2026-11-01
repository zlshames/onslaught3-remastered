import 'package:meta/meta.dart';

import '../data/descriptor_defs.dart';
import '../data/mod_editor_defs.dart';

/// One value the mod editor offers, with its item, its descriptor and the
/// value the unmodded data has.
@immutable
class ModField {
  const ModField({
    required this.item,
    required this.def,
    required this.descriptor,
    required this.defaultValue,
  });

  final ModItemDef item;
  final ModFieldDef def;
  final ValueDescriptor descriptor;

  /// The value without any mod (from the data, which is what games use).
  final Object? defaultValue;

  /// `TurretBlue.weapon_damage`.
  String get id => '${item.id}.${def.asset}';
  ModValueType get type => def.type;
}
