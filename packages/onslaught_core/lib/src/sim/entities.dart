import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../data/turret_def.dart';
import '../math/vec2.dart';

/// An attacker walking the road (`AttackerEngine`). Mutable sim state; the
/// presentation layer reads it, only systems write it.
class Creep {
  Creep({
    required this.uid,
    required this.wave,
    required this.typeIndex,
    required this.behaviour,
    required this.position,
    required this.hpStart,
    required this.baseSpeed,
    required this.bounty,
    required this.scaleBump,
    required this.createdAtMs,
  }) : hp = hpStart,
       speed = baseSpeed;

  final int uid;

  /// Wave that sent this creep.
  final int wave;

  /// Index into `creeps.json` types.
  final int typeIndex;

  /// Creep behaviour id in `RulesRegistry.creepBehaviours`.
  final String behaviour;

  Vec2 position;

  /// Hit points left (`energy`) and at spawn (`energy_start`).
  double hp;
  final double hpStart;

  /// Current and unslowed speed, px/s (`move_speed`, `move_speed_init`).
  double speed;
  final double baseSpeed;

  /// Cash paid when killed (`cash_bounty`); a black hole sets it to 0.
  int bounty;

  /// `10 / wave_size` (1 for normal waves); the sprite scale grows with it.
  final double scaleBump;

  /// Game time of the spawn, for the old/young target modes.
  final double createdAtMs;

  /// Index of the road point the current leg heads for (0 = spawn point).
  int waypoint = 0;

  /// The current leg: a linear move from [legFrom] to [legTo] over
  /// [legDurationMs], [legElapsedMs] of which have passed.
  Vec2 legFrom = Vec2.zero;
  Vec2 legTo = Vec2.zero;
  double legDurationMs = 0;
  double legElapsedMs = 0;

  /// Heading of the current leg in degrees (for sprites that repoint).
  double heading = 0;

  /// Game time at which the pending speed recovery fires, or null when none
  /// is pending (`interval_replenish`: one 1000 ms timer at a time while the
  /// creep is slower than its initial speed).
  double? recoverAtMs;

  /// Caught by a black hole (`black_holed`): it no longer moves, slows or
  /// takes damage, but stays on the road and targetable until it reaches
  /// the hole's centre and is removed.
  bool blackHoled = false;

  /// Its pull into a black hole, while [blackHoled].
  Capture? capture;

  /// Its bounty before a black hole zeroed it.
  int bountyBeforeHole = 0;

  bool get alive => hp > 0;

  /// Killed or reached the base this step; removed at the end of the step.
  bool gone = false;

  /// Whether turrets and projectiles may still aim at it.
  bool get targetable => !gone && alive;

  /// Game milliseconds since the spawn.
  double ageMs(double nowMs) => nowMs - createdAtMs;

  /// HP as a whole percentage, rounded up (the original's health text).
  int get hpPercent => (hp / hpStart * 100).ceil();

  Map<String, Object?> toJson() => {
    'uid': uid,
    'wave': wave,
    'type': typeIndex,
    'pos': position.toJson(),
    'hp': hp,
    'speed': speed,
    'waypoint': waypoint,
    'legTo': legTo.toJson(),
    'legDurationMs': legDurationMs,
    'legElapsedMs': legElapsedMs,
    'recoverAtMs': ?recoverAtMs,
    if (blackHoled) 'holed': true,
    'capture': ?capture?.toJson(),
  };
}

/// A creep, projectile or blast being pulled into a black hole
/// (`OnslaughtObject.as:blackHoled`): a linear move from [from] to the hole's
/// centre [to] over [durationMs] while the sprite shrinks to 25 %, then it is
/// removed without effect.
class Capture {
  Capture({required this.hole, required this.from, required this.to, required this.durationMs});

  /// Uid of the black hole.
  final int hole;
  final Vec2 from;
  final Vec2 to;
  final double durationMs;
  double elapsedMs = 0;

  /// Progress 0…1.
  double get t => durationMs <= 0 ? 1 : (elapsedMs / durationMs).clamp(0, 1);

  bool get done => elapsedMs >= durationMs;

  Vec2 get position => from.lerp(to, t);

  Map<String, Object?> toJson() => {
    'hole': hole,
    'to': to.toJson(),
    'ms': durationMs,
    'at': elapsedMs,
  };
}

/// A built turret (`turrets.Turret`).
class Turret {
  Turret({
    required this.uid,
    required this.def,
    required this.position,
    required this.displayName,
    required this.cashValue,
    required this.targetModeIndex,
    required this.lockOff,
    required this.builtAtMs,
  });

  final int uid;
  final TurretDef def;
  Vec2 position;
  final String displayName;

  /// Purchase price plus every upgrade bought (`cash_value`).
  double cashValue;

  /// Upgrade levels bought per track.
  int damageLevel = 0;
  int rangeLevel = 0;
  int rateLevel = 0;

  /// Index into `targeting.json` modes. Every turret starts at 0 in the
  /// original (`target_type_num`), even when its default mode is not
  /// "near", so the first cycle goes to index 1.
  int targetModeIndex;

  /// Current target mode id (`target_type`).
  String? targetMode;

  /// Drop the target after each shot (`target_reacquire`).
  bool lockOff;

  /// Weapon rotation in degrees, Flash convention: (−180, 180], clockwise.
  double rotation = 0;

  /// Uid of the creep being tracked, if any.
  int? targetUid;

  /// Game time of the last shot (`weapon_fired`).
  double firedAtMs = 0;
  final double builtAtMs;

  /// Next fire point to use when the weapon has several.
  int firePointIndex = 0;

  /// Real ms since its update timer last ticked (`setInterval(update,
  /// frame_space)`, started when built or moved).
  double sinceTickMs = 0;

  /// Game time of its last update (`time_last`); null until its first tick,
  /// which does nothing (the original's `now − undefined` is NaN).
  double? updatedAtMs;

  int shots = 0;
  int kills = 0;

  /// False while a Combonly plate consumes it (`active = false`): it does
  /// nothing and cannot be selected until it is removed.
  bool active = true;

  /// Uid of the creep a Targeter last sent it at (`turretBearTarget`): it
  /// turns toward that creep while it has no target of its own.
  int? bearCreepUid;

  /// Base poison (slow per shot) before modifiers (`weapon_poison`). Starts
  /// at the data value; a special may rescale it on upgrade (Yellow).
  late double poison = def.stats.poison;

  /// Terms from modifier auras in range, recomputed whenever the turret set
  /// changes (`TurretModify._modifyAssert`).
  StatTerms aura = StatTerms.identity;

  /// Terms from running freakouts (`FreakoutEngine` stage 2 `modifyGain`).
  StatTerms freak = StatTerms.identity;

  /// All terms: auras and freakouts stack additively (`Turret.modifyGain`).
  StatTerms get terms => aura + freak;

  final Map<String, SpecialState> _specialState = {};

  /// Per-special state, keyed by special id, read-only. Specials create
  /// theirs lazily ([stateOf]) and it is part of the hashed state, so a
  /// reader must never create one: the app reads through [stateOrNull] and
  /// shows the special's defaults while there is none.
  late final Map<String, SpecialState> specialState = UnmodifiableMapView(_specialState);

  /// The state of special [id], created with [create] on first use. For the
  /// rules only: creating state changes [toJson], and so the state hash,
  /// which a replay of the command log must reproduce.
  @internal
  T stateOf<T extends SpecialState>(String id, T Function() create) =>
      _specialState.putIfAbsent(id, create) as T;

  /// The state of special [id] when it has been created, else null.
  T? stateOrNull<T extends SpecialState>(String id) => _specialState[id] as T?;

  int level(StatKind stat) => switch (stat) {
    StatKind.damage => damageLevel,
    StatKind.range => rangeLevel,
    StatKind.rate => rateLevel,
  };

  void setLevel(StatKind stat, int value) {
    switch (stat) {
      case StatKind.damage:
        damageLevel = value;
      case StatKind.range:
        rangeLevel = value;
      case StatKind.rate:
        rateLevel = value;
    }
  }

  Map<String, Object?> toJson() => {
    'uid': uid,
    'turret': def.id,
    'pos': position.toJson(),
    'levels': [damageLevel, rangeLevel, rateLevel],
    'cashValue': cashValue,
    'mode': targetMode,
    'lockOff': lockOff,
    'rotation': rotation,
    'target': targetUid,
    'firedAtMs': firedAtMs,
    'tick': [sinceTickMs, updatedAtMs],
    'shots': shots,
    'kills': kills,
    if (!active) 'inactive': true,
    'bearCreep': ?bearCreepUid,
    if (poison != def.stats.poison) 'poison': poison,
    if (terms != StatTerms.identity) 'terms': terms.toJson(),
    if (_specialsJson().isNotEmpty) 'specials': _specialsJson(),
  };

  Map<String, Object?> _specialsJson() => {
    for (final e in _specialState.entries) e.key: ?e.value.toJson(),
  };
}

/// What a special remembers about one turret. [toJson] returns null while
/// the state cannot affect anything that is not already derivable from the
/// turret's levels, so turrets whose special never engages hash as before.
abstract class SpecialState {
  Map<String, Object?>? toJson();
}

/// The `added` / `mult` terms of a turret's effective stats
/// (`modify_*_added`, `modify_*_mult`). [mult] terms here are the sums
/// added to the base multiplier 1.
@immutable
class StatTerms {
  const StatTerms({
    this.addDamage = 0,
    this.addRange = 0,
    this.addRate = 0,
    this.addPoison = 0,
    this.multDamage = 0,
    this.multRange = 0,
    this.multRate = 0,
    this.multPoison = 0,
  });

  static const StatTerms identity = StatTerms();

  final double addDamage;
  final double addRange;
  final double addRate;
  final double addPoison;
  final double multDamage;
  final double multRange;
  final double multRate;
  final double multPoison;

  double added(StatKind stat) => switch (stat) {
    StatKind.damage => addDamage,
    StatKind.range => addRange,
    StatKind.rate => addRate,
  };

  /// The multiplier of [stat]: 1 plus the summed terms.
  double mult(StatKind stat) =>
      1 +
      switch (stat) {
        StatKind.damage => multDamage,
        StatKind.range => multRange,
        StatKind.rate => multRate,
      };

  StatTerms operator +(StatTerms o) => StatTerms(
    addDamage: addDamage + o.addDamage,
    addRange: addRange + o.addRange,
    addRate: addRate + o.addRate,
    addPoison: addPoison + o.addPoison,
    multDamage: multDamage + o.multDamage,
    multRange: multRange + o.multRange,
    multRate: multRate + o.multRate,
    multPoison: multPoison + o.multPoison,
  );

  StatTerms operator -() => StatTerms(
    addDamage: -addDamage,
    addRange: -addRange,
    addRate: -addRate,
    addPoison: -addPoison,
    multDamage: -multDamage,
    multRange: -multRange,
    multRate: -multRate,
    multPoison: -multPoison,
  );

  List<double> get _values => [
    addDamage,
    addRange,
    addRate,
    addPoison,
    multDamage,
    multRange,
    multRate,
    multPoison,
  ];

  List<double> toJson() => _values;

  @override
  bool operator ==(Object other) =>
      other is StatTerms && const ListEquality<double>().equals(other._values, _values);

  @override
  int get hashCode => Object.hashAll(_values);

  @override
  String toString() => 'StatTerms($_values)';
}

/// A shot in flight. One entity type for every projectile; its [kind] (a
/// `RulesRegistry` projectile kind) decides how it moves and hits.
class Projectile {
  Projectile({
    required this.uid,
    required this.specId,
    required this.kind,
    required this.position,
    required this.heading,
    required this.damage,
    required this.targetUid,
    required this.turretUid,
    required this.createdAtMs,
    this.poison = 0,
  });

  final int uid;

  /// `projectiles.json` id (decides the sprite).
  final String specId;
  final String kind;
  Vec2 position;

  /// Degrees, clockwise from +x.
  double heading;
  final double damage;
  int? targetUid;

  /// Turret credited with kills (null for none).
  final int? turretUid;

  /// A shot fired into a turret instead of a creep (a feeder charging a
  /// Fusion cannon): the turret absorbs it.
  int? intoTurretUid;

  /// Slow applied on hit (`bullet_poison`).
  final double poison;

  /// Game time of the launch.
  final double createdAtMs;

  /// Set by its kind when the projectile is spent.
  bool done = false;

  /// Instant kinds (beams, sparks): where the drawn line ends. They hit on
  /// launch and stay only as a fading visual.
  Vec2? lineTo;

  /// What a combo projectile carries (blast, cluster, on-board weapons …);
  /// null for plain shots.
  Ordnance? load;

  /// Its kind's own state (rocket holding, landmine throw, black-hole timers).
  KindState? state;

  /// Its pull into a black hole; it does nothing else meanwhile.
  Capture? capture;

  Map<String, Object?> toJson() => {
    'uid': uid,
    'spec': specId,
    'pos': position.toJson(),
    'heading': heading,
    'damage': damage,
    'target': targetUid,
    'into': ?intoTurretUid,
    if (poison != 0) 'poison': poison,
    'lineTo': ?lineTo?.toJson(),
    'load': ?load?.toJson(),
    if (state case final st? when st.flatInSnapshot) ...st.toJson() else 'state': ?state?.toJson(),
    'capture': ?capture?.toJson(),
  };
}

/// Per-entity state a projectile or blast kind keeps.
abstract class KindState {
  Map<String, Object?> toJson();

  /// Whether [toJson]'s entries sit directly in the entity's snapshot rather
  /// than under `state`: true for state that lived on the entity itself
  /// before it moved here (the rocket's), so recorded state hashes still hold.
  bool get flatInSnapshot => false;
}

/// What a combo projectile carries besides its own damage: what a
/// `Turret.comboFire*` sets on the `Projectile`, one record per block (blast,
/// cluster, on-board laser and rockets, napalm, laser blast, black hole) and
/// the placement. Fixed when fired; only the on-board weapons' last-fired
/// times change.
class Ordnance {
  Ordnance({
    required this.combo,
    this.speed,
    this.blast,
    this.cluster,
    this.laser,
    this.subRocket,
    this.napalm,
    this.laserBlast,
    this.place,
    this.hole,
    this.laserFiredAtMs = 0,
    this.subRocketFiredAtMs = 0,
  });

  /// Recipe id that fired it.
  final String combo;

  /// Speed override, px/s (`move_speed`).
  final double? speed;

  /// Blast spawned on impact.
  final BlastLoad? blast;

  /// Cluster spawned on impact.
  final ClusterLoad? cluster;

  /// On-board laser (`laser_capable`).
  final OnboardWeapon? laser;

  /// On-board rockets (`rocket_capable`).
  final OnboardWeapon? subRocket;

  /// Napalm drops.
  final NapalmLoad? napalm;

  /// Laser blast on impact (only under `RulesProfile.laserRocketLaserBlast`).
  final LaserBlastLoad? laserBlast;

  /// Where a placed projectile goes (landmine mine point, black-hole point);
  /// null when it found none.
  final Vec2? place;

  /// The black hole it opens.
  final HoleLoad? hole;

  /// Game time the on-board laser and rockets last fired (the launch, at
  /// first).
  double laserFiredAtMs;
  double subRocketFiredAtMs;

  /// A copy carrying only what a blast passes on (napalm drops, cluster).
  Ordnance copy() => Ordnance(combo: combo, cluster: cluster, napalm: napalm);

  Map<String, Object?> toJson() => {
    'combo': combo,
    'speed': ?speed,
    if (blast case final b?) 'blast': [b.type, b.damage, b.poison],
    if (cluster case final c?)
      'cluster': [c.type, c.qty, c.damage, c.holding, c.laser, c.laserDamage],
    if (laser case final l?)
      'laser': [l.projectile, l.damage, l.range, l.intervalMs, laserFiredAtMs],
    if (subRocket case final r?)
      'rocket': [r.projectile, r.damage, r.intervalMs, subRocketFiredAtMs],
    if (napalm case final n? when n.qty > 0) 'napalm': [n.qty, n.timingMs, n.jitter],
    if (laserBlast case final l? when l.qty > 0) 'laserBlast': [l.qty, l.damage, l.range],
    'place': ?place?.toJson(),
    if (hole case final h? when h.radius > 0) 'hole': [h.radius, h.durationMs],
  };
}

/// The blast a combo projectile sets off on impact (`blast_type`,
/// `blast_damage`, `blast_poison`) and the sound it plays (`sound_blast`).
final class BlastLoad {
  const BlastLoad({required this.type, required this.damage, required this.poison, this.sound});

  /// `blasts.json` id.
  final String type;
  final double damage;
  final double poison;
  final String? sound;
}

/// The cluster a combo projectile fans out on impact (`cluster_type`,
/// `cluster_qty`, `cluster_damage`, `cluster_holding`, `cluster_laser`,
/// `cluster_laser_damage`).
final class ClusterLoad {
  const ClusterLoad({
    required this.type,
    required this.qty,
    required this.damage,
    required this.holding,
    required this.laser,
    required this.laserDamage,
  });

  /// `blasts.json` id of the cluster blast.
  final String type;
  final int qty;
  final double damage;
  final bool holding;
  final bool laser;
  final double laserDamage;
}

/// An on-board weapon (`laser_capable`, `rocket_capable`): the projectile it
/// fires, with what damage, how far (the laser only) and how often.
final class OnboardWeapon {
  const OnboardWeapon({
    required this.projectile,
    required this.damage,
    this.range = 0,
    required this.intervalMs,
  });

  /// `projectiles.json` id.
  final String projectile;
  final double damage;
  final double range;
  final double intervalMs;
}

/// Napalm drops (`napalm_quantity`, `napalm_timing`, `napalm_jit`).
final class NapalmLoad {
  const NapalmLoad({required this.qty, required this.timingMs, required this.jitter});

  final int qty;
  final double timingMs;
  final double jitter;
}

/// The laser blast on impact (`laserblast_*`).
final class LaserBlastLoad {
  const LaserBlastLoad({required this.qty, required this.damage, required this.range});

  final int qty;
  final double damage;
  final double range;
}

/// A black hole's radius and how long it stays open (`weapon_range`,
/// `hole_duration`).
final class HoleLoad {
  const HoleLoad({required this.radius, required this.durationMs});

  final double radius;
  final double durationMs;
}

/// A blast (`BlastEngine` and `blasts/*`, `ClusterBlastEngine`,
/// `ClusterSparkEngine`): an effect left where ordnance went off. Its [kind]
/// (a `RulesRegistry` blast kind) decides what it does: grow and deal its
/// damage once, drop napalm, send shockwave walkers, fan out a cluster.
class Blast {
  Blast({
    required this.uid,
    required this.specId,
    required this.kind,
    required this.position,
    required this.damage,
    required this.poison,
    required this.turretUid,
    required this.angle,
    required this.targetUid,
    required this.createdAtMs,
    this.load,
  });

  final int uid;

  /// `blasts.json` id.
  final String specId;
  final String kind;
  Vec2 position;

  /// `weapon_damage` and `weapon_poison` (divide-mode slow).
  final double damage;
  final double poison;

  /// Turret credited with kills.
  final int? turretUid;

  /// Heading of the ordnance when it went off (`blast_angle`).
  final double angle;

  /// The ordnance's target when it went off (`bullet_target`).
  final int? targetUid;
  final double createdAtMs;

  /// Cluster and napalm parameters passed on by the ordnance.
  final Ordnance? load;

  /// Current diameter, px, and opacity 0…1 (views).
  double size = 0;
  double alpha = 1;

  /// Its kind's own state.
  KindState? state;

  /// Its pull into a black hole.
  Capture? capture;

  bool done = false;

  Map<String, Object?> toJson() => {
    'uid': uid,
    'spec': specId,
    'pos': position.toJson(),
    'damage': damage,
    'poison': poison,
    'size': size,
    'alpha': alpha,
    'state': ?state?.toJson(),
    'capture': ?capture?.toJson(),
  };
}

/// One of a shockwave's road walkers (`Shockwave`): it walks the road from
/// the blast toward the base ([direction] +1) or the spawn (−1) at the
/// shockwave's walker speed, and every walker tick hits and slows the
/// creeps right around it, by less as its lifetime runs out. Not a creep:
/// nothing targets it.
class ShockwaveWalker {
  ShockwaveWalker({
    required this.uid,
    required this.specId,
    required this.position,
    required this.direction,
    required this.waypoint,
    required this.damage,
    required this.poison,
    required this.turretUid,
    required this.startedAtMs,
  });

  final int uid;

  /// The shockwave blast's `blasts.json` id (walker parameters).
  final String specId;
  Vec2 position;
  final int direction;

  /// Index of the road point the current leg heads for.
  int waypoint;

  /// Full-strength damage and subtracted slow (`bullet_damage`,
  /// `bullet_poison`).
  final double damage;
  final double poison;
  final int? turretUid;
  final double startedAtMs;

  Vec2 legFrom = Vec2.zero;
  Vec2 legTo = Vec2.zero;
  double legDurationMs = 0;
  double legElapsedMs = 0;
  double heading = 0;

  /// Game ms since its last hit tick, and hit ticks so far.
  double sinceTickMs = 0;
  int zaps = 0;

  bool done = false;

  Map<String, Object?> toJson() => {
    'uid': uid,
    'pos': position.toJson(),
    'dir': direction,
    'waypoint': waypoint,
    'legMs': [legDurationMs, legElapsedMs],
    'tick': sinceTickMs,
    'zaps': zaps,
  };
}
