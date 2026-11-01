import 'package:collection/collection.dart';

// Raw helpers over a mod delta's files (document name → chain of objects):
// read, set and remove a value at a path, list what is left, and the JSON
// normalisation every mod comparison uses. Internal to the mod rules; not
// exported.

/// The value at [path] (the document name first) in [files], and whether
/// there is one. A document with no patch, or a null one, has none.
({bool found, Object? value}) readPath(Map<String, Object?> files, List<String> path) {
  Object? at = files[path.first];
  if (at == null) return (found: false, value: null);
  for (final key in path.skip(1)) {
    if (at is! Map || !at.containsKey(key)) return (found: false, value: null);
    at = at[key];
  }
  return (found: true, value: at);
}

/// Sets the value at [path], creating the objects on the way.
void putPath(Map<String, Object?> root, List<String> path, Object? value) {
  var node = root;
  for (final key in path.take(path.length - 1)) {
    node = (node[key] ??= <String, Object?>{}) as Map<String, Object?>;
  }
  node[path.last] = value;
}

/// Removes the value at [path] and every object it leaves empty.
void removePath(Map<String, Object?> root, List<String> path) {
  final chain = <Map<String, Object?>>[root];
  for (final key in path.take(path.length - 1)) {
    final next = chain.last[key];
    if (next is! Map<String, Object?>) return;
    chain.add(next);
  }
  chain.last.remove(path.last);
  for (var i = chain.length - 1; i > 0 && chain[i].isEmpty; i--) {
    chain[i - 1].remove(path[i - 1]);
  }
}

/// `file:/a/b` for every value left in [files].
List<String> leafPaths(Map<String, Object?> files) {
  final out = <String>[];
  void walk(Object? v, String at) {
    if (v is Map && v.isNotEmpty) {
      v.forEach((k, c) => walk(c, '$at/$k'));
    } else {
      out.add(at);
    }
  }

  files.forEach((file, patch) {
    if (patch is Map && patch.isNotEmpty) {
      patch.forEach((k, c) => walk(c, '$file:/$k'));
    } else {
      out.add('$file:');
    }
  });
  return out;
}

bool isFiniteNum(Object? v) => v is num && v.isFinite;

bool deepEquals(Object? a, Object? b) => const DeepCollectionEquality().equals(a, b);

/// Whole doubles become ints (`20.0` → `20`), as the data files write them.
Object? normalJson(Object? v) => switch (v) {
  double() when v.isFinite && v == v.truncateToDouble() => v.toInt(),
  Map() => {for (final e in v.entries) e.key as String: normalJson(e.value)},
  List() => [for (final e in v) normalJson(e)],
  _ => v,
};

Map<String, Object?> copyFiles(Map<String, Object?> files) =>
    normalJson(files)! as Map<String, Object?>;
