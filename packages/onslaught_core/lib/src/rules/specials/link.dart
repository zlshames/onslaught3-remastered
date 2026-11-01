import 'package:meta/meta.dart';

import '../../data/turret_def.dart';
import '../../sim/entities.dart';
import '../../sim/game_session.dart';
import '../rules_registry.dart';
import '../stat_rules.dart';
import '../targeting_rules.dart';

class LinkState extends SpecialState {
  /// Reloaded at its last update and not yet used by a leader
  /// (`link_offered`, true for a new turret).
  bool offered = true;

  /// Pooled shots led (`link_fire_count`) and helped (`link_assist_count`).
  int led = 0;
  int assisted = 0;

  /// Damage of its last pooled shot (`link_last_damage`).
  double lastDamage = 0;

  @override
  Map<String, Object?> toJson() => {
    'offered': offered,
    'led': led,
    'assisted': assisted,
    'last': lastDamage,
  };
}

/// Green's link (`Turret.linkGetInRange/linkFire`, `TurretGreen.update`).
///
/// Each update a green first offers itself if it has reloaded. When one
/// fires (the leader) every link turret within *its own* effective range
/// that is on offer is used: it turns to the leader and recursively pools
/// its own link neighbours into a shot it fires *at the leader* (no sound,
/// spending its reload); the leader's beam then carries its own damage plus
/// `mult` × each helper's pooled damage, compounding per depth, with no
/// limit on helpers. A green with no link neighbour in range fires plainly;
/// as a helper it pools nothing (it fires 0 at the leader, with sound).
///
/// The original keeps the neighbour list up to date on every change that
/// affects it (builds, sales, moves, its own upgrades and modifier
/// changes); here it is computed when needed, which gives the same list.
/// Helpers are taken in build order: AS2 `for…in` order is not observed and
/// only matters when two helpers share a neighbour.
class LinkSpecial extends TurretSpecial {
  const LinkSpecial();

  static const String specialId = 'link';

  @override
  String get id => specialId;

  @override
  Set<String>? get paramKeys => const {'mult'};

  /// [Turret.stateOf] for this special: rules only (it creates the state).
  @internal
  static LinkState stateOf(Turret t) => t.stateOf(specialId, LinkState.new);

  @override
  void beforeAim(GameSession session, Turret turret, double dtMs) =>
      stateOf(turret).offered = session.canFire(turret);

  @override
  bool fire(GameSession session, Turret turret, Creep target) {
    _linkFire(
      session,
      turret,
      target: target,
      damage: turretStat(turret, StatKind.damage, session.data.rules),
      lead: true,
    );
    return true;
  }

  /// The link turrets [t] would pool from (`link_in_range`).
  static List<Turret> neighbours(GameSession s, Turret t) {
    final range = turretStat(t, StatKind.range, s.data.rules);
    return s.turretsNear(t, range, where: (o) => o.def.specials.contains(specialId)).toList();
  }

  /// `Turret.linkFire(leader, 0)` as combos call it: [t] fires at [leader]
  /// (itself for a BFG) with what it pools from its link neighbours on
  /// offer, and returns that pool, 0 when it has no link neighbour in range
  /// (`Turret.comboTakeLink`, `comboFireBFG`).
  static double linkFireInto(GameSession s, Turret t, Turret leader) =>
      _linkFire(s, t, leader: leader, damage: 0, lead: false);

  /// `Turret.linkFire`: fires at [target] (a creep) or, as a helper, at
  /// [leader]; returns the damage pooled.
  static double _linkFire(
    GameSession s,
    Turret t, {
    Creep? target,
    Turret? leader,
    required double damage,
    required bool lead,
  }) {
    final links = neighbours(s, t);
    if (links.isEmpty) {
      _shoot(s, t, target, leader, damage, silent: false, lead: lead);
      return damage;
    }
    final state = stateOf(t)..offered = false;
    final helpers = [
      for (final h in links)
        if (stateOf(h).offered) h,
    ];
    for (final h in helpers) {
      stateOf(h).offered = false;
    }
    var pool = turretStat(t, StatKind.damage, s.data.rules);
    final mult = const LinkSpecial().params(t).number('mult')!;
    for (final h in helpers) {
      h.rotation = bearingDeg(h.position, t.position);
      pool += _linkFire(s, h, leader: t, damage: 0, lead: false) * mult;
    }
    _shoot(s, t, target, leader, pool, silent: !lead, lead: lead);
    if (lead) {
      state.led++;
    } else {
      state.assisted++;
    }
    state.lastDamage = pool;
    return pool;
  }

  static void _shoot(
    GameSession s,
    Turret t,
    Creep? target,
    Turret? leader,
    double damage, {
    required bool silent,
    required bool lead,
  }) {
    // A Combonly plate pooling for its BFG has no weapon of its own.
    if (t.def.projectiles.isEmpty) return s.weaponlessShot(t);
    s.turretFire(
      t,
      target: target,
      at: leader?.position,
      damage: damage,
      silent: silent,
      assist: !lead,
    );
  }
}
