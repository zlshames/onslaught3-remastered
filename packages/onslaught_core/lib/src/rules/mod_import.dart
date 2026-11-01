import 'package:meta/meta.dart';

import '../data/mod_delta.dart';
import '../data/mod_editor_defs.dart';
import 'delta_paths.dart';
import 'mod_checks.dart';
import 'mod_fields.dart';
import 'mod_rules.dart';

/// A mod read from a share code or an original-game export, checked and
/// ready to replace the current one.
@immutable
class ModImport {
  const ModImport({required this.delta, required this.problems});

  /// The values that passed; everything else was left out.
  final ModDelta delta;
  final List<ModProblem> problems;

  /// Whether the data with [delta] applied validates (a mod that does not
  /// cannot be used).
  bool get usable => problems.every((p) => p.kind != ModProblemKind.invalidData);
}

/// The two ways a whole mod comes in: a shared [ModDelta] ([importDelta])
/// and the original game's mod save ([importLegacy]).
extension ModImporters on ModRules {
  /// Reads a shared mod: every value the editor offers is checked as if it
  /// were typed in; values that fail, and values the editor does not offer,
  /// are left out and reported. The result replaces the whole mod
  /// (`modFromObject`).
  ModImport importDelta(ModDelta incoming) {
    final problems = <ModProblem>[];
    var out = ModDelta(const {}, name: incoming.name);
    final rest = copyFiles(incoming.files);
    for (final f in fields) {
      final r = readPath(incoming.files, [f.def.file, ...f.def.path]);
      if (!r.found) continue;
      removePath(rest, [f.def.file, ...f.def.path]);
      final found = check(f, r.value);
      if (found.isEmpty) {
        out = withValue(out, f, r.value);
      } else {
        problems.addAll(found);
      }
    }
    for (final path in leafPaths(rest)) {
      problems.add(ModProblem(ModProblemKind.unknownValue, detail: path));
    }
    problems.addAll(validate(out));
    return ModImport(delta: out, problems: List.unmodifiable(problems));
  }

  /// Reads a mod saved by the original game's "Create Mod Save"
  /// (`ModImportExport`: `{"TurretBlue": {"weapon_damage": 20,
  /// "upgrade_damage": {"cost": […], "amount": […]}}, …}`). Values convert
  /// as `modFromObject` did (`Number(v)`, `v == true`, the shorter of the
  /// two arrays), then go through [importDelta].
  ModImport importLegacy(Object? json) {
    if (json is! Map) {
      return const ModImport(
        delta: ModDelta.none,
        problems: [ModProblem(ModProblemKind.wrongType, detail: 'not a mod')],
      );
    }
    final unknown = <ModProblem>[];
    final files = <String, Object?>{};

    json.forEach((itemKey, assets) {
      if (assets is! Map) {
        unknown.add(ModProblem(ModProblemKind.unknownValue, detail: '$itemKey'));
        return;
      }
      assets.forEach((assetKey, value) {
        final f = field('$itemKey.$assetKey');
        if (f == null) {
          // Indexed values are also saved flattened (`upgrade_damage_cost`);
          // the paired object carries the same values.
          final flattened = fieldsOf('$itemKey').any(
            (g) =>
                g.type == ModValueType.arrayIndexed &&
                (assetKey == '${g.def.asset}_${g.descriptor.keyField}' ||
                    assetKey == '${g.def.asset}_${g.descriptor.valueField}'),
          );
          if (!flattened) {
            unknown.add(ModProblem(ModProblemKind.unknownValue, detail: '$itemKey.$assetKey'));
          }
          return;
        }
        putPath(files, [f.def.file, ...f.def.path], _fromLegacy(f, value));
      });
    });
    final read = importDelta(ModDelta(files));
    return ModImport(
      delta: read.delta,
      problems: List.unmodifiable([...unknown, ...read.problems]),
    );
  }

  Object? _fromLegacy(ModField f, Object? v) {
    num? number(Object? x) => switch (x) {
      num() => x,
      String() => num.tryParse(x.trim()),
      bool() => x ? 1 : 0,
      _ => null,
    };
    switch (f.type) {
      case ModValueType.number || ModValueType.integer:
        return number(v) ?? v;
      case ModValueType.boolean:
        return v == true;
      case ModValueType.string:
        return v is String ? v : '$v';
      case ModValueType.arrayIndexed:
        if (v is! Map) return v;
        final keys = v[f.descriptor.keyField];
        final values = v[f.descriptor.valueField];
        if (keys is! List || values is! List) return v;
        return [
          for (var i = 0; i < keys.length && i < values.length; i++)
            {f.def.keyField!: number(keys[i]), f.def.valueField!: number(values[i])},
        ];
    }
  }
}
