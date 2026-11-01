import 'package:meta/meta.dart';

import 'json_reader.dart';

/// The widget a mod value is edited with (`ModManager.MOD_*`).
enum ModValueType {
  number,
  integer,
  boolean,
  string,

  /// Parallel key/value entries, such as an upgrade path's cost and amount.
  arrayIndexed,
}

/// One value the mod editor offers: the original's asset name (which keys
/// its descriptor), its type, and where it lives in the data documents.
@immutable
class ModFieldDef {
  const ModFieldDef({
    required this.asset,
    required this.type,
    required this.file,
    required this.path,
    this.keyField,
    this.valueField,
  });

  factory ModFieldDef.fromJson(JsonReader r) {
    r.expectOnlyKeys({'asset', 'type', 'file', 'path', 'keyField', 'valueField'});
    final type = r.oneOf('type', {for (final t in ModValueType.values) t.name}, fallback: 'number');
    final indexed = type == ModValueType.arrayIndexed.name;
    if (indexed && !(r.has('keyField') && r.has('valueField'))) {
      r.issue('an arrayIndexed value needs keyField and valueField');
    }
    return ModFieldDef(
      asset: r.string('asset'),
      type: ModValueType.values.byName(type),
      file: r.string('file'),
      path: r.list('path', (c) => c.asString(), minLength: 1),
      keyField: r.optString('keyField'),
      valueField: r.optString('valueField'),
    );
  }

  /// The original asset name (`weapon_damage`), the key into
  /// `descriptors.json`.
  final String asset;
  final ModValueType type;

  /// The data document the value lives in (`turrets.json`).
  final String file;

  /// Keys from the document root to the value. A step into a list of
  /// records names the record's id, as `ModDelta` patches do.
  final List<String> path;

  /// For [ModValueType.arrayIndexed]: the field names of each entry in the
  /// data (`cost` / `value`).
  final String? keyField;
  final String? valueField;

  Map<String, Object?> toJson() => {
    'asset': asset,
    'type': type.name,
    'file': file,
    'path': path,
    'keyField': ?keyField,
    'valueField': ?valueField,
  };
}

/// A group of values in the editor (`item_library`): a turret, a combo or
/// the game settings.
@immutable
class ModItemDef {
  const ModItemDef({
    required this.id,
    required this.title,
    required this.group,
    required this.fields,
  });

  factory ModItemDef.fromJson(JsonReader r) {
    r.expectOnlyKeys({'id', 'title', 'group', 'fields'});
    return ModItemDef(
      id: r.string('id'),
      title: r.string('title'),
      group: r.string('group'),
      fields: r.list('fields', ModFieldDef.fromJson, minLength: 1),
    );
  }

  /// The original's item key (`TurretBlue`, `Combo_nuke`, `GameSettings`).
  final String id;
  final String title;

  /// Section of the item list (`settings`, `turret`, `modifier`, `super`,
  /// `combo`).
  final String group;

  /// In the order the editor lists them.
  final List<ModFieldDef> fields;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'group': group,
    'fields': [for (final f in fields) f.toJson()],
  };
}

/// `mod_editor.json`: every item and value the mod editor offers, in order.
@immutable
class ModEditorDefs {
  const ModEditorDefs(this.items);

  factory ModEditorDefs.fromJson(JsonReader r) {
    r.expectOnlyKeys({'schemaVersion', 'items'});
    final items = r.list('items', ModItemDef.fromJson);
    final seen = <String>{};
    for (var i = 0; i < items.length; i++) {
      if (!seen.add(items[i].id)) r.child('items').child('$i').issue('duplicate item');
    }
    return ModEditorDefs(List.unmodifiable(items));
  }

  static const int schemaVersion = 1;
  static const ModEditorDefs empty = ModEditorDefs([]);

  final List<ModItemDef> items;

  ModItemDef? item(String id) => items.where((i) => i.id == id).firstOrNull;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'items': [for (final i in items) i.toJson()],
  };
}

/// The value at [path] in a decoded data [document], or `found: false`.
/// A step into a list of records picks the record with that `id`.
({bool found, Object? value}) resolveDataPath(Object? document, List<String> path) {
  Object? at = document;
  for (final key in path) {
    if (at is Map && at.containsKey(key)) {
      at = at[key];
    } else if (at is List) {
      final record = at.where((e) => e is Map && e['id'] == key).firstOrNull;
      if (record == null) return (found: false, value: null);
      at = record;
    } else {
      return (found: false, value: null);
    }
  }
  return (found: true, value: at);
}
