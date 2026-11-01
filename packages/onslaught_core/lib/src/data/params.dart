import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import 'json_reader.dart';

/// A small bag of named scalar parameters owned by a behaviour (a turret
/// special, a projectile kind, a combo recipe). Values are numbers, booleans,
/// strings or lists of numbers; the behaviour registered for the owning id
/// declares and reads the keys it needs.
@immutable
class Params {
  const Params(this._values);

  factory Params.fromJson(JsonReader r) {
    if (r.isNull) return empty;
    final out = <String, Object>{};
    if (!r.isMap) {
      r.issue('expected an object of parameters');
      return empty;
    }
    for (final key in r.keys) {
      final c = r.child(key);
      final v = c.raw;
      if (v is num || v is bool || v is String) {
        out[key] = v is int ? v.toDouble() : v!;
      } else if (v is List && v.every((e) => e is num)) {
        out[key] = List<double>.unmodifiable(v.map((e) => (e as num).toDouble()));
      } else {
        c.issue('expected a number, boolean, string or list of numbers');
      }
    }
    return Params(Map.unmodifiable(out));
  }

  static const Params empty = Params({});

  final Map<String, Object> _values;

  Iterable<String> get keys => _values.keys;
  bool get isEmpty => _values.isEmpty;
  bool has(String key) => _values.containsKey(key);

  double? number(String key) => _values[key] as double?;
  bool? boolean(String key) => _values[key] as bool?;
  String? string(String key) => _values[key] as String?;
  List<double>? numbers(String key) => _values[key] as List<double>?;

  /// The parameters as JSON, whole numbers written as integers
  /// ([jsonNumber]) the way the documents spell them.
  Map<String, Object> toJson() => {
    for (final e in _values.entries)
      e.key: switch (e.value) {
        final num n => jsonNumber(n),
        final List<double> l => [for (final n in l) jsonNumber(n)],
        final v => v,
      },
  };

  @override
  bool operator ==(Object other) =>
      other is Params && const DeepCollectionEquality().equals(other._values, _values);

  @override
  int get hashCode => const DeepCollectionEquality().hash(_values);
}
