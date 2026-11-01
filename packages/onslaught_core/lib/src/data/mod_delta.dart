import 'package:meta/meta.dart';

import 'json_reader.dart';

/// A sparse override of the data layer: per data file, a JSON merge patch
/// (RFC 7386) with one extension so records can be patched by id.
///
/// * An object patch merges into an object; `null` deletes a key.
/// * An object patch applied to an **array of records that all have an `id`**
///   merges per record: `{"turrets": {"blue": {"cost": 12}}}` changes only the
///   blue turret's cost; `{"blue": null}` removes it; an unknown id appends a
///   new record (which must then be complete; a patch that is not an object
///   is appended as it is, for the reader to report).
/// * Anything else (scalars, arrays) replaces the target.
///
/// This mirrors the original mod system (`mods.default[item][asset] = value`,
/// undefined = default) without copying whole tables into every mod.
@immutable
class ModDelta {
  const ModDelta(this.files, {this.name});

  factory ModDelta.fromJson(Object? json) {
    final sink = IssueSink();
    final r = JsonReader.root(json, 'mod', sink);
    r.expectOnlyKeys({'schemaVersion', 'name', 'files'});
    readSchemaVersion(r, supported: schemaVersion);
    final files = r.child('files');
    if (!files.isMap) files.issue('expected an object of file patches');
    final delta = ModDelta({
      for (final k in files.keys) k: files.child(k).raw,
    }, name: r.optString('name'));
    sink.throwIfAny();
    return delta;
  }

  static const int schemaVersion = 1;
  static const ModDelta none = ModDelta({});

  /// Data file path (as in the manifest) → merge patch.
  final Map<String, Object?> files;
  final String? name;

  bool get isEmpty => files.isEmpty;

  Map<String, Object?> toJson() => {'schemaVersion': schemaVersion, 'name': ?name, 'files': files};

  /// Returns [documents] with this delta applied. Inputs are not modified.
  Map<String, Object?> applyTo(Map<String, Object?> documents) {
    if (isEmpty) return documents;
    final out = Map<String, Object?>.of(documents);
    files.forEach((path, patch) {
      out[path] = mergePatch(out[path], patch);
    });
    return out;
  }
}

/// Applies [patch] to [target] with the id-aware merge rules of [ModDelta].
Object? mergePatch(Object? target, Object? patch) {
  if (patch is! Map) return _deepCopy(patch);
  if (target is List && _isRecordList(target)) {
    return _mergeRecords(target, patch.cast<String, Object?>());
  }
  final base = target is Map
      ? Map<String, Object?>.of(target.cast<String, Object?>())
      : <String, Object?>{};
  patch.forEach((k, v) {
    final key = k as String;
    if (v == null) {
      base.remove(key);
    } else {
      base[key] = mergePatch(base[key], v);
    }
  });
  return base;
}

bool _isRecordList(List<Object?> list) =>
    list.isNotEmpty && list.every((e) => e is Map && e['id'] is String);

List<Object?> _mergeRecords(List<Object?> records, Map<String, Object?> patch) {
  final out = <Object?>[];
  final seen = <String>{};
  for (final r in records) {
    final rec = (r! as Map).cast<String, Object?>();
    final id = rec['id']! as String;
    seen.add(id);
    if (!patch.containsKey(id)) {
      out.add(rec);
    } else if (patch[id] != null) {
      out.add(mergePatch(rec, patch[id]));
    }
  }
  patch.forEach((id, v) {
    if (seen.contains(id) || v == null) return;
    if (v is Map) {
      out.add({'id': id, ...(mergePatch(<String, Object?>{}, v)! as Map<String, Object?>)});
    } else {
      // Not a record: appended as it is, so the document's reader reports
      // it ("expected an object") with its path.
      out.add(_deepCopy(v));
    }
  });
  return out;
}

Object? _deepCopy(Object? v) {
  if (v is Map) {
    return {for (final e in v.entries) e.key as String: _deepCopy(e.value)};
  }
  if (v is List) return [for (final e in v) _deepCopy(e)];
  return v;
}
