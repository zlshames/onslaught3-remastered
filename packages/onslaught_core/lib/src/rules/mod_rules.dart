import '../data/descriptor_defs.dart';
import '../data/game_data.dart';
import '../data/json_reader.dart';
import '../data/mod_delta.dart';
import '../data/mod_editor_defs.dart';
import '../sim/stable_hash.dart';
import 'delta_paths.dart';
import 'mod_fields.dart';

/// The mod editor's rules over the unmodded [base] data
/// (`docs/ONSLAUGHT2_GAME_REFERENCE.md` §12, `mods/ModManager.as`): a mod
/// is a sparse [ModDelta]; each value is checked against its descriptor;
/// a value can be reset on its own, per item, or all at once; an import
/// replaces the whole mod.
///
/// Every delta this builds holds only values the editor offers, each as a
/// chain of objects from the document root (`{"turrets": {"blue": {"stats":
/// {"damage": 20}}}}`), so a value set to its default leaves no trace.
class ModRules {
  ModRules(this.base, {this.behaviours})
    : fields = List.unmodifiable([
        for (final item in base.modEditor.items)
          for (final def in item.fields)
            ModField(
              item: item,
              def: def,
              descriptor:
                  base.descriptors.byAsset[def.asset] ??
                  ValueDescriptor(title: def.asset, description: ''),
              defaultValue: normalJson(resolveDataPath(base.documents[def.file], def.path).value),
            ),
      ]);

  /// Unmodded data: its documents are the defaults.
  final GameData base;

  /// Behaviour ids the modded data is validated against.
  final KnownBehaviours? behaviours;

  /// Every value, in editor order.
  final List<ModField> fields;

  late final Map<String, ModField> _byId = {for (final f in fields) f.id: f};

  List<ModItemDef> get items => base.modEditor.items;

  ModField? field(String id) => _byId[id];

  List<ModField> fieldsOf(String itemId) => [
    for (final f in fields)
      if (f.item.id == itemId) f,
  ];

  // ------------------------------------------------------------- reading

  /// Whether [delta] changes [f] (`assetDeltaGet` is defined).
  bool isSet(ModField f, ModDelta delta) =>
      readPath(delta.files, [f.def.file, ...f.def.path]).found;

  /// The value [f] has with [delta]: its change, or the default.
  Object? valueOf(ModField f, ModDelta delta) {
    final r = readPath(delta.files, [f.def.file, ...f.def.path]);
    return r.found ? r.value : f.defaultValue;
  }

  /// Whether [delta] changes any value of [itemId] (`itemHasDelta`).
  bool itemIsSet(String itemId, ModDelta delta) => fieldsOf(itemId).any((f) => isSet(f, delta));

  /// How many values [delta] changes.
  int changeCount(ModDelta delta) => fields.where((f) => isSet(f, delta)).length;

  // ------------------------------------------------------------- editing

  /// [delta] with [f] set to [value] (`assetDeltaSet`); setting the default
  /// removes the change. The caller checks [value] first ([check]).
  ModDelta withValue(ModDelta delta, ModField f, Object? value) {
    final v = normalJson(value);
    if (deepEquals(v, f.defaultValue)) return withoutValue(delta, f);
    final files = copyFiles(delta.files);
    putPath(files, [f.def.file, ...f.def.path], v);
    return ModDelta(files, name: delta.name);
  }

  /// [delta] without a change to [f] ("reset asset", `assetDeltaClear`).
  ModDelta withoutValue(ModDelta delta, ModField f) {
    if (!isSet(f, delta)) return delta;
    final files = copyFiles(delta.files);
    removePath(files, [f.def.file, ...f.def.path]);
    return ModDelta(files, name: delta.name);
  }

  /// [delta] without changes to [itemId] ("reset item", `itemDeltaClear`).
  ModDelta withoutItem(ModDelta delta, String itemId) => fieldsOf(itemId).fold(delta, withoutValue);

  /// No changes, same name ("reset all", `modClear`).
  ModDelta cleared(ModDelta delta) => ModDelta(const {}, name: delta.name);

  // ------------------------------------------------------------ applying

  /// The data with [delta] applied. Throws [DataValidationException] when
  /// it does not validate.
  GameData apply(ModDelta delta) =>
      GameData.fromDocuments(base.documents, delta: delta, behaviours: behaviours);
}

/// A short, stable fingerprint of what [delta] changes, shown while the mod
/// is active (the original's watermark showed an MD5 of the mod's JSON,
/// `ModManager.modSignature`). The name is not part of it; key order and
/// how a number is written (20 vs 20.0) do not change it.
String modSignature(ModDelta delta) => fnv1a32Hex(canonicalJson(normalJson(delta.files)));
