import 'package:meta/meta.dart';

import 'art_defs.dart';
import 'json_reader.dart';
import 'params.dart';

/// What projectile and blast definitions share: an id, the behaviour
/// [kind] that runs it, an optional sprite and the kind's [params]. One
/// entity type with a kind instead of a class per projectile or blast.
@immutable
abstract class OrdnanceSpec {
  const OrdnanceSpec({
    required this.id,
    required this.legacyId,
    required this.kind,
    required this.sprite,
    required this.params,
    this.art,
  });

  final String id;
  final String? legacyId;

  /// Behaviour id in `RulesRegistry.projectileKinds` (shell, rocket, beam,
  /// rail, spark, cluster-bomb, landmine …) or `RulesRegistry.blastKinds`
  /// (blast, napalm, shockwave …).
  final String kind;

  /// Logical asset id (null for drawn effects such as beams).
  final String? sprite;

  /// Speed, turn rate, impact radius, lifetimes … as the kind requires.
  final Params params;

  /// How a drawn effect looks (bands by damage, cosmetic timings); null for
  /// one drawn only from its [sprite]. Never read by the sim.
  final EffectArt? art;

  Map<String, Object?> toJson() => {
    'id': id,
    'legacyId': ?legacyId,
    'kind': kind,
    'sprite': ?sprite,
    'params': params.toJson(),
    'art': ?art?.toJson(),
  };
}

/// A projectile definition from `projectiles.json`.
@immutable
class ProjectileSpec extends OrdnanceSpec {
  const ProjectileSpec({
    required super.id,
    required super.legacyId,
    required super.kind,
    required super.sprite,
    required super.params,
    super.art,
  });

  factory ProjectileSpec.fromJson(JsonReader r) => _read(r, ProjectileSpec.new);
}

/// A blast definition from `blasts.json` (`BlastEngine` and `blasts/*`).
@immutable
class BlastSpec extends OrdnanceSpec {
  const BlastSpec({
    required super.id,
    required super.legacyId,
    required super.kind,
    required super.sprite,
    required super.params,
    super.art,
  });

  factory BlastSpec.fromJson(JsonReader r) => _read(r, BlastSpec.new);
}

/// Reads one `projectiles.json` or `blasts.json` entry and builds it with
/// [make].
T _read<T extends OrdnanceSpec>(
  JsonReader r,
  T Function({
    required String id,
    required String? legacyId,
    required String kind,
    required String? sprite,
    required Params params,
    EffectArt? art,
  })
  make,
) {
  r.expectOnlyKeys({'id', 'legacyId', 'kind', 'sprite', 'params', 'art'});
  return make(
    id: r.string('id'),
    legacyId: r.optString('legacyId'),
    kind: r.string('kind'),
    sprite: r.optString('sprite'),
    params: Params.fromJson(r.child('params')),
    art: r.optChild('art', EffectArt.fromJson),
  );
}
