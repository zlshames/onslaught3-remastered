import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../data/descriptor_defs.dart';
import '../data/json_reader.dart';
import '../data/mod_delta.dart';
import '../data/mod_editor_defs.dart';
import 'delta_paths.dart';
import 'mod_fields.dart';
import 'mod_rules.dart';

/// Why a mod value (or a whole mod) is refused.
enum ModProblemKind {
  /// Not a value of the field's type (a word for a number, NaN, a fraction
  /// for an integer, a malformed entry).
  wrongType,
  belowMin,
  aboveMax,

  /// A string shorter / longer than the descriptor allows.
  tooShort,
  tooLong,

  /// An indexed value with fewer / more entries than the descriptor allows.
  fewerEntries,
  moreEntries,

  /// A value the editor does not offer (an imported mod only).
  unknownValue,

  /// The modded data does not validate (e.g. an upgrade path that goes down).
  invalidData,
}

@immutable
class ModProblem {
  const ModProblem(this.kind, {this.field, this.entry, this.part, this.limit, this.detail});

  final ModProblemKind kind;

  /// The value at fault, when it is one the editor offers.
  final ModField? field;

  /// For an indexed value: the entry (0-based) and its part (`key` or
  /// `value`) at fault.
  final int? entry;
  final String? part;

  /// The bound that was crossed.
  final num? limit;

  /// The data problem ([ModProblemKind.invalidData]) or the unknown value's
  /// location ([ModProblemKind.unknownValue]).
  final String? detail;

  @override
  String toString() => [
    kind.name,
    ?field?.id,
    if (entry != null) '#${entry! + 1}',
    ?part,
    ?limit?.toString(),
    ?detail,
  ].join(' ');
}

/// The mod editor's checks: one value against its descriptor ([check]) and
/// the whole modded data against the validator ([validate]).
extension ModChecks on ModRules {
  /// Why [value] cannot be [f]'s value (empty = it can). A value equal to
  /// the default always can, as can an indexed entry equal to the default's
  /// entry at the same place: some defaults lie outside the original's own
  /// descriptor bounds (`docs/legacy/LEGACY_VALUES.md`).
  List<ModProblem> check(ModField f, Object? value) {
    final v = normalJson(value);
    if (deepEquals(v, f.defaultValue)) return const [];
    final d = f.descriptor;
    switch (f.type) {
      case ModValueType.number || ModValueType.integer:
        if (v is! num || !v.isFinite || (f.type == ModValueType.integer && v is! int)) {
          return [ModProblem(ModProblemKind.wrongType, field: f)];
        }
        return _bounds(f, v, d);
      case ModValueType.boolean:
        return v is bool ? const [] : [ModProblem(ModProblemKind.wrongType, field: f)];
      case ModValueType.string:
        if (v is! String) return [ModProblem(ModProblemKind.wrongType, field: f)];
        return [
          if (d.min != null && v.length < d.min!)
            ModProblem(ModProblemKind.tooShort, field: f, limit: d.min),
          if (d.max != null && v.length > d.max!)
            ModProblem(ModProblemKind.tooLong, field: f, limit: d.max),
        ];
      case ModValueType.arrayIndexed:
        return _checkEntries(f, v);
    }
  }

  List<ModProblem> _bounds(ModField f, num v, ValueDescriptor d, {int? entry, String? part}) => [
    if (d.min != null && v < d.min!)
      ModProblem(ModProblemKind.belowMin, field: f, entry: entry, part: part, limit: d.min),
    if (d.max != null && v > d.max!)
      ModProblem(ModProblemKind.aboveMax, field: f, entry: entry, part: part, limit: d.max),
  ];

  List<ModProblem> _checkEntries(ModField f, Object? v) {
    final keyField = f.def.keyField!;
    final valueField = f.def.valueField!;
    bool wellFormed(Object? e) =>
        e is Map && e.length == 2 && isFiniteNum(e[keyField]) && isFiniteNum(e[valueField]);
    if (v is! List || !v.every(wellFormed)) {
      return [ModProblem(ModProblemKind.wrongType, field: f)];
    }
    final d = f.descriptor;
    final defaults = f.defaultValue is List ? f.defaultValue! as List : const <Object?>[];
    return [
      // For indexed values the descriptor's bounds count entries
      // (`ModValueArrayIndexed`).
      if (d.min != null && v.length < d.min!)
        ModProblem(ModProblemKind.fewerEntries, field: f, limit: d.min),
      if (d.max != null && v.length > d.max!)
        ModProblem(ModProblemKind.moreEntries, field: f, limit: d.max),
      for (var i = 0; i < v.length; i++)
        if (i >= defaults.length || !deepEquals(v[i], defaults[i])) ...[
          if (d.key != null)
            ..._bounds(f, (v[i] as Map)[keyField] as num, d.key!, entry: i, part: 'key'),
          if (d.value != null)
            ..._bounds(f, (v[i] as Map)[valueField] as num, d.value!, entry: i, part: 'value'),
        ],
    ];
  }

  /// Why the data with [delta] applied does not validate (empty = it does),
  /// each problem tied to the editor value it lies in when there is one.
  List<ModProblem> validate(ModDelta delta) {
    if (delta.isEmpty) return const [];
    try {
      apply(delta);
      return const [];
    } on DataValidationException catch (e) {
      return [
        for (final issue in e.issues)
          ModProblem(ModProblemKind.invalidData, field: _fieldAt(issue.path), detail: issue.reason),
      ];
    }
  }

  /// The editor value a validator issue path (`turrets.json:/turrets/0/
  /// upgrades/damage/3/value`) lies in: record indexes become ids, then the
  /// longest field path that is a prefix wins.
  ModField? _fieldAt(String issuePath) {
    final split = issuePath.indexOf(':/');
    if (split < 0) return null;
    final file = issuePath.substring(0, split);
    final steps = issuePath.substring(split + 2).split('/');
    final ids = <String>[];
    Object? at = base.documents[file];
    for (final s in steps) {
      final i = int.tryParse(s);
      if (at is List && i != null && i < at.length) {
        at = at[i];
        ids.add(at is Map && at['id'] is String ? at['id']! as String : s);
      } else {
        at = at is Map ? at[s] : null;
        ids.add(s);
      }
    }
    ModField? best;
    for (final f in fields) {
      final p = f.def.path;
      if (f.def.file != file || p.length > ids.length) continue;
      if (!const ListEquality<String>().equals(p, ids.sublist(0, p.length))) continue;
      if (best == null || p.length > best.def.path.length) best = f;
    }
    return best;
  }
}
