import 'package:meta/meta.dart';

import 'json_reader.dart';

/// `targeting.json`: target modes and directional cones.
@immutable
class TargetingDefs {
  const TargetingDefs({
    required this.modes,
    required this.cones,
    required this.mustFaceToleranceDeg,
  });

  factory TargetingDefs.fromJson(JsonReader r) {
    r.expectOnlyKeys({'schemaVersion', 'modes', 'cones', 'mustFaceToleranceDeg'});
    return TargetingDefs(
      modes: r.list('modes', (c) => c.asString(), minLength: 1),
      cones: r.list('cones', TargetCone.fromJson, minLength: 1),
      mustFaceToleranceDeg: r.number('mustFaceToleranceDeg', min: 0),
    );
  }

  static const int schemaVersion = 1;

  /// Mode ids in cycle order (near, far, weak, strong, slow, fast, old, young).
  final List<String> modes;
  final List<TargetCone> cones;
  final double mustFaceToleranceDeg;

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'modes': modes,
    'cones': [for (final c in cones) c.toJson()],
    'mustFaceToleranceDeg': jsonNumber(mustFaceToleranceDeg),
  };
}

/// A directional-arc option; [spreadDeg] null = no cone.
@immutable
class TargetCone {
  const TargetCone(this.id, this.spreadDeg);

  factory TargetCone.fromJson(JsonReader r) {
    r.expectOnlyKeys({'id', 'spreadDeg'});
    return TargetCone(r.string('id'), r.optNumber('spreadDeg', min: 0, max: 360));
  }

  final String id;
  final double? spreadDeg;

  /// [spreadDeg] is always written, null included (no cone).
  Map<String, Object?> toJson() => {'id': id, 'spreadDeg': optJsonNumber(spreadDeg)};
}
