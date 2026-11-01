import 'package:meta/meta.dart';

import '../math/vec2.dart';

/// One problem found while reading or validating a data document.
@immutable
class DataIssue {
  const DataIssue(this.path, this.reason);

  /// Location of the problem, e.g. `turrets.json:/turrets/0/stats/range`.
  final String path;

  /// Human-readable reason, e.g. `must be between 10 and 800 (was 900)`.
  final String reason;

  @override
  String toString() => '$path: $reason';

  @override
  bool operator ==(Object other) =>
      other is DataIssue && other.path == path && other.reason == reason;

  @override
  int get hashCode => Object.hash(path, reason);
}

/// Thrown when data fails to parse or validate. Carries every issue found, not
/// just the first, so a broken mod or data edit can be fixed in one pass.
class DataValidationException implements Exception {
  DataValidationException(List<DataIssue> issues) : issues = List.unmodifiable(issues);

  final List<DataIssue> issues;

  @override
  String toString() {
    final shown = issues.take(20).map((i) => '  - $i').join('\n');
    final more = issues.length > 20 ? '\n  … and ${issues.length - 20} more' : '';
    return 'DataValidationException (${issues.length} issues):\n$shown$more';
  }
}

/// Collects [DataIssue]s while documents are read.
class IssueSink {
  final List<DataIssue> _issues = [];

  List<DataIssue> get issues => List.unmodifiable(_issues);
  bool get isEmpty => _issues.isEmpty;

  void add(String path, String reason) => _issues.add(DataIssue(path, reason));

  /// Throws a [DataValidationException] if any issue was recorded.
  void throwIfAny() {
    if (_issues.isNotEmpty) throw DataValidationException(_issues);
  }
}

/// A cursor over decoded JSON that tracks its path and records problems in an
/// [IssueSink] instead of throwing, returning a neutral fallback so reading can
/// continue and report every problem at once.
class JsonReader {
  JsonReader._(this._value, this.path, this.sink);

  /// Reader for the root of [file]'s decoded JSON.
  factory JsonReader.root(Object? value, String file, IssueSink sink) =>
      JsonReader._(value, '$file:', sink);

  final Object? _value;

  /// Path of this node, e.g. `maps/map1.json:/road/3`.
  final String path;
  final IssueSink sink;

  Object? get raw => _value;

  Map<String, Object?> get _map {
    final v = _value;
    if (v is Map<String, Object?>) return v;
    if (v is Map) return v.cast<String, Object?>();
    return const {};
  }

  bool get isMap => _value is Map;
  bool get isList => _value is List;
  bool get isNull => _value == null;

  bool has(String key) => _map.containsKey(key) && _map[key] != null;

  Iterable<String> get keys => _map.keys;

  JsonReader child(String key) => JsonReader._(_map[key], '$path/$key', sink);

  /// The object at [key] read with [read], or null when [key] is absent or
  /// null.
  T? optChild<T>(String key, T Function(JsonReader r) read) => has(key) ? read(child(key)) : null;

  void issue(String reason) => sink.add(path, reason);

  /// Reports keys present in this object but not in [allowed]. Catches typos
  /// in hand-edited data and mods (`"rnage": 120`).
  void expectOnlyKeys(Set<String> allowed) {
    if (!isMap) return;
    for (final k in _map.keys) {
      if (!allowed.contains(k)) sink.add('$path/$k', 'unknown key');
    }
  }

  JsonReader _require(String key) {
    if (!isMap) {
      issue('expected an object');
    } else if (!has(key)) {
      sink.add('$path/$key', 'is required');
    }
    return child(key);
  }

  String string(String key, {String fallback = ''}) {
    final c = _require(key);
    return c._asString(fallback: fallback, required: has(key));
  }

  String? optString(String key) => has(key) ? string(key) : null;

  String _asString({required String fallback, bool required = true}) {
    final v = _value;
    if (v is String) return v;
    if (required) issue('expected a string');
    return fallback;
  }

  bool boolean(String key, {bool fallback = false}) {
    final c = _require(key);
    final v = c._value;
    if (v is bool) return v;
    if (has(key)) c.issue('expected a boolean');
    return fallback;
  }

  bool optBoolean(String key, {required bool fallback}) =>
      has(key) ? boolean(key, fallback: fallback) : fallback;

  double number(String key, {num? min, num? max, double fallback = 0}) {
    final c = _require(key);
    return c.asNumber(min: min, max: max, fallback: fallback, present: has(key));
  }

  double? optNumber(String key, {num? min, num? max}) =>
      has(key) ? number(key, min: min, max: max) : null;

  /// This node as a number, with optional bounds.
  double asNumber({num? min, num? max, double fallback = 0, bool present = true}) {
    final v = _value;
    if (v is! num) {
      if (present) issue('expected a number');
      return fallback;
    }
    final d = v.toDouble();
    if (!d.isFinite) {
      issue('must be finite');
      return fallback;
    }
    _checkBounds(d, min, max);
    return d;
  }

  int integer(String key, {int? min, int? max, int fallback = 0}) {
    final c = _require(key);
    return c.asInt(min: min, max: max, fallback: fallback, present: has(key));
  }

  int? optInteger(String key, {int? min, int? max}) =>
      has(key) ? integer(key, min: min, max: max) : null;

  /// The `"#RRGGBB"` colour at [key] as 0xRRGGBB (0 when missing or malformed).
  int rgb(String key, {String fallback = '#000000'}) =>
      _parseRgb(string(key, fallback: fallback), child(key));

  /// This node, a `"#RRGGBB"` colour, as 0xRRGGBB (0 when malformed).
  int asRgb() => _parseRgb(asString(), this);

  static int _parseRgb(String s, JsonReader at) {
    final m = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(s);
    if (m == null) {
      at.issue('expected a colour like "#B2885B" (was "$s")');
      return 0;
    }
    return int.parse(m.group(1)!, radix: 16);
  }

  /// [rgb] when [key] is present, else null.
  int? optRgb(String key) => has(key) ? rgb(key) : null;

  /// This node as an integer (a JSON number with no fractional part).
  int asInt({int? min, int? max, int fallback = 0, bool present = true}) {
    final v = _value;
    if (v is int) {
      _checkBounds(v, min, max);
      return v;
    }
    if (v is double && v == v.roundToDouble() && v.isFinite) {
      _checkBounds(v, min, max);
      return v.toInt();
    }
    if (present) issue('expected an integer');
    return fallback;
  }

  void _checkBounds(num v, num? min, num? max) {
    if (min != null && v < min || max != null && v > max) {
      final lo = min ?? '-∞';
      final hi = max ?? '∞';
      issue('must be between $lo and $hi (was $v)');
    }
  }

  /// This node as a string.
  String asString({String fallback = ''}) => _asString(fallback: fallback);

  /// The string at [key], which must be one of [allowed].
  String oneOf(String key, Set<String> allowed, {required String fallback}) {
    final s = string(key, fallback: fallback);
    if (has(key) && !allowed.contains(s)) {
      child(key).issue('must be one of ${allowed.join(', ')} (was "$s")');
      return fallback;
    }
    return s;
  }

  /// This node as a point: an object with exactly the numbers `x` and `y`.
  Vec2 asPoint() {
    expectOnlyKeys({'x', 'y'});
    return Vec2(number('x'), number('y'));
  }

  /// The point ([asPoint]) at [key].
  Vec2 point(String key) => child(key).asPoint();

  /// The list at [key], each element read with [read]; unmodifiable.
  List<T> list<T>(String key, T Function(JsonReader r) read, {int? minLength}) {
    final c = _require(key);
    return c.asList(read, minLength: minLength, present: has(key));
  }

  List<T> optList<T>(String key, T Function(JsonReader r) read) =>
      has(key) ? list(key, read) : const [];

  /// This node as an unmodifiable list, reading each element with [read].
  List<T> asList<T>(T Function(JsonReader r) read, {int? minLength, bool present = true}) {
    final v = _value;
    if (v is! List) {
      if (present) issue('expected an array');
      return const [];
    }
    if (minLength != null && v.length < minLength) {
      issue('must have at least $minLength entries (had ${v.length})');
    }
    return List<T>.unmodifiable([
      for (var i = 0; i < v.length; i++) read(JsonReader._(v[i], '$path/$i', sink)),
    ]);
  }

  /// This node as an unmodifiable object whose values are all read with
  /// [read], keeping key order.
  Map<String, T> asMapOf<T>(T Function(JsonReader r) read) {
    if (!isMap) {
      issue('expected an object');
      return const {};
    }
    return Map<String, T>.unmodifiable({for (final k in _map.keys) k: read(child(k))});
  }

  /// The object at [key], each value read with [read]; unmodifiable.
  Map<String, T> mapOf<T>(String key, T Function(JsonReader r) read) {
    final c = _require(key);
    return c.isMap ? c.asMapOf(read) : const {};
  }
}

/// Checks the `schemaVersion` of a data document against what this build reads.
int readSchemaVersion(JsonReader root, {required int supported}) {
  final v = root.integer('schemaVersion', min: 1);
  if (root.has('schemaVersion') && v != supported) {
    root
        .child('schemaVersion')
        .issue('unsupported schema version $v (this build reads $supported)');
  }
  return v;
}

// ------------------------------------------------------------ writing JSON
//
// The inverse of [JsonReader] for the data records' `toJson`: the reader
// widens every number to a double, so writing one back gives it the JSON
// spelling the documents use (an integer when it has no fraction).

/// [v] as a JSON number: an `int` when it is whole (`130`, not `130.0`), else
/// the double.
num jsonNumber(num v) => v is double && v.isFinite && v == v.truncateToDouble() ? v.toInt() : v;

/// [v] as a JSON number ([jsonNumber]), or null.
num? optJsonNumber(num? v) => v == null ? null : jsonNumber(v);

/// A point as the `{x, y}` object [JsonReader.asPoint] reads.
Map<String, Object?> pointToJson(Vec2 p) => {'x': jsonNumber(p.x), 'y': jsonNumber(p.y)};

/// A 0xRRGGBB colour as the `"#RRGGBB"` string [JsonReader.rgb] reads.
String rgbToJson(int rgb) => '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
