import 'package:meta/meta.dart';

import '../../data/combo_recipe.dart';
import '../../data/game_data.dart';
import '../../data/turret_def.dart';
import '../../math/vec2.dart';
import '../../sim/entities.dart';
import '../../sim/game_event.dart';
import '../../sim/game_session.dart';
import '../../sim/sim_random.dart';
import '../aiming.dart';
import '../behaviours/rocket_state.dart';
import '../rules_registry.dart';
import '../stat_rules.dart';
import '../targeting_rules.dart';
import 'link.dart';

class ComboState extends SpecialState {
  /// Last time it fired or helped a combo (`combo_fired`).
  double firedAtMs = 0;

  /// It may combo again from this game time (`combo_next`).
  double nextAtMs = 0;

  /// Combos led (`combo_fire_count`) and helped (`combo_assist_count`).
  int led = 0;
  int assisted = 0;

  /// Uid of the leader it turns toward while it has no target
  /// (`target_bear_to`), until it has one.
  int? bearTo;

  @override
  Map<String, Object?>? toJson() => led == 0 && assisted == 0
      ? null
      : {'fired': firedAtMs, 'next': nextAtMs, 'led': led, 'assisted': assisted, 'bearTo': ?bearTo};
}

/// Combos (`Turret.comboActivate/comboCanFire/comboCountColours/comboTake*`,
/// each colour's `comboFire`, `Turret.comboFire*`; `docs/legacy/ENGINE_NOTES.md`
/// §1).
///
/// * A colour turret can combo once its damage track is fully bought
///   ([isComboCapable]).
/// * When it is reloaded and aimed at a target and may combo (reloaded,
///   past its `combo_next`), it counts the helpers within the combo range
///   that may combo too, by colour, and fires the first of its colour's
///   recipes, in priority order, whose helper counts are met (`requires`,
///   exactly for the `exact` colours). With none it shoots its own way.
/// * Firing takes helpers: a `link` value has one green helper pool its
///   link neighbours into a shot at the leader and adds that pool plus its
///   own damage; a `poison` value uses one yellow helper's poison; `ownLink`
///   is the leader's own link pool (0 with no link neighbour), `ownPoison`
///   its own poison (whole number; the fallback when 0). Then the other
///   `takes` are picked at random among the ready helpers, plus any
///   `takesIfReady`. Taken helpers may combo again `rechargeMs − 1` after,
///   and turn toward the leader while they have no target (colours with
///   `bearToLeader`); their reload is untouched.
/// * The leader may combo again `rechargeMs` after; its weapon reloads, but
///   the combo is not a shot (no fire sound, no shot count, lock-off keeps
///   the target). It fires the recipe's projectile from its next fire
///   point (placed projectiles start from its centre) with its values
///   through the leader's damage modifiers: missing values fall back to the
///   `combos.json` defaults as they are, `linkAddsTo` values get the link
///   value first, `rawValues` (and the poison rocket's blast damage, unless
///   `poisonRocketModified`) skip the modifiers.
///
/// The neighbourhood is everything within the combo range, both ways. The
/// original adds a newly built turret to an older one's list only when it
/// is strictly inside the range, so at exactly the range the older turret
/// does not see the newer one; that edge is not copied. Helpers that turn
/// toward their leader stop when they get a target (Red keeps turning back
/// in the original once it loses its target again).
class ComboSpecial extends TurretSpecial {
  const ComboSpecial();

  static const String specialId = 'combo';

  @override
  String get id => specialId;

  @override
  Set<String>? get paramKeys => const {'bearToLeader'};

  /// [Turret.stateOf] for this special: rules only (it creates the state).
  @internal
  static ComboState stateOf(Turret t) => t.stateOf(specialId, ComboState.new);

  /// `Turret.comboCanFire`: combo-capable, reloaded (at least a reload
  /// since its last shot) and past its `combo_next`.
  static bool canCombo(GameSession s, Turret t) =>
      t.active &&
      isComboCapable(t.def, t.damageLevel) &&
      s.reloadedForCombo(t) &&
      s.clock.nowMs >= stateOf(t).nextAtMs;

  /// The turrets [t] may combo with (`combo_in_range`): every other turret
  /// that ever combos within the combo range.
  static List<Turret> neighbours(GameSession s, Turret t) {
    return s.turretsNear(t, s.data.rules.comboRange, where: (o) => !o.def.comboNever).toList();
  }

  /// `Turret.comboCountColours`: the neighbours that may combo now, by
  /// turret id, in build order.
  static Map<String, List<Turret>> readyHelpers(GameSession s, Turret t) {
    final out = <String, List<Turret>>{};
    for (final o in neighbours(s, t)) {
      if (canCombo(s, o)) out.putIfAbsent(o.def.id, () => []).add(o);
    }
    return out;
  }

  /// [leader]'s recipes in priority order.
  static List<ComboRecipe> recipesFor(GameData d, String leader) => [
    for (final r in d.combos.values)
      if (r.leader == leader) r,
  ]..sort((a, b) => a.priority.compareTo(b.priority));

  /// The first of [leader]'s recipes that [ready] helpers satisfy.
  static ComboRecipe? match(GameData d, String leader, Map<String, List<Turret>> ready) {
    for (final r in recipesFor(d, leader)) {
      if (satisfies(r, ready)) return r;
    }
    return null;
  }

  /// Whether [ready] meets [r]'s helper counts.
  static bool satisfies(ComboRecipe r, Map<String, List<Turret>> ready) {
    for (final e in r.requires.counts.entries) {
      final n = ready[e.key]?.length ?? 0;
      if (r.exact.contains(e.key) ? n != e.value : n < e.value) return false;
    }
    return true;
  }

  @override
  bool fire(GameSession session, Turret turret, Creep target) {
    if (!canCombo(session, turret)) return false;
    final ready = readyHelpers(session, turret);
    final recipe = match(session.data, turret.def.id, ready);
    if (recipe == null) return false;
    fireRecipe(session, turret, recipe, target, ready);
    return true;
  }

  @override
  void afterAim(
    GameSession session,
    Turret turret, {
    required bool hadTarget,
    required double dtMs,
  }) {
    final st = turret.stateOrNull<ComboState>(specialId);
    final uid = st?.bearTo;
    if (st == null || uid == null) return;
    final leader = hadTarget ? null : session.turretByUid(uid);
    if (leader == null) {
      st.bearTo = null;
      return;
    }
    turnToward(session, turret, leader.position, dtMs);
  }

  /// Fires [recipe] from [leader] at [target] with the [ready] helpers
  /// (`Turret.comboFire*`). [silent] fires without taking helpers or link
  /// and poison values (`combo_silent`, the Combonly plate); [firePoints]
  /// replace the leader's own (the plate's colour weapon).
  static Projectile fireRecipe(
    GameSession s,
    Turret leader,
    ComboRecipe recipe,
    Creep target,
    Map<String, List<Turret>> ready, {
    bool silent = false,
    List<Vec2>? firePoints,
  }) {
    final now = s.clock.nowMs;
    final rules = s.data.rules;
    final defaults = s.data.comboDefaults;
    final v = recipe.values;
    final pools = {for (final e in ready.entries) e.key: List.of(e.value)};
    final taken = <Turret>[];

    List<Turret> pick(String colour, int n) {
      final list = pools[colour] ?? <Turret>[];
      final picked = pickRandom(s.random, list, n);
      list.removeWhere(picked.contains);
      return picked;
    }

    void take(List<Turret> helpers) {
      if (silent) return;
      for (final h in helpers) {
        final st = stateOf(h)
          ..firedAtMs = now
          ..assisted += 1
          ..nextAtMs = now + recipe.rechargeMs - 1;
        if (const ComboSpecial().params(h).boolean('bearToLeader') ?? false) st.bearTo = leader.uid;
        // `turretBearTarget(leader)` replaces a Targeter's creep.
        h.bearCreepUid = null;
        taken.add(h);
      }
    }

    // The helper value, taken first (`comboTakeLink`, `comboTakePoison`).
    var link = 0.0;
    double? helperPoison;
    final fallbackPoison = defaults.number('helperPoisonFallback')!;
    final helperColour = recipe.helperColour;
    switch (recipe.helperValue) {
      case 'link' when helperColour != null:
        final greens = pick(helperColour, 1);
        if (greens.isNotEmpty) {
          final g = greens.single;
          link = LinkSpecial.linkFireInto(s, g, leader) + s.statOf(g, StatKind.damage);
          g.rotation = bearingDeg(g.position, leader.position);
          take(greens);
        }
      case 'poison' when helperColour != null:
        final yellows = pick(helperColour, 1);
        helperPoison = yellows.isEmpty ? fallbackPoison : turretPoison(yellows.single, rules);
        take(yellows);
      case 'ownLink':
        link = LinkSpecial.linkFireInto(s, leader, leader);
      case 'ownPoison':
        final own = turretPoison(leader, rules).truncateToDouble();
        helperPoison = own <= 0 ? fallbackPoison : own;
    }
    if (!silent) {
      for (final e in recipe.takes.counts.entries) {
        final valueTaken =
            e.key == helperColour &&
            (recipe.helperValue == 'link' || recipe.helperValue == 'poison');
        final n = e.value - (valueTaken ? 1 : 0);
        if (n > 0) take(pick(e.key, n));
      }
      for (final e in recipe.takesIfReady.counts.entries) {
        take(pick(e.key, e.value));
      }
    }

    double value(String field) {
      final raw = v.number(field);
      if (raw == null) return defaults.number(field) ?? 0;
      final amount = raw + (recipe.linkAddsTo.contains(field) ? link : 0);
      final unmodified =
          recipe.rawValues.contains(field) ||
          (field == _blastDamage &&
              (v.boolean('blastDamageRaw') ?? false) &&
              !s.config.profile.poisonRocketModified);
      return unmodified ? amount : modifiedDamage(leader, amount, rules);
    }

    // `comboFired`.
    stateOf(leader)
      ..firedAtMs = now
      ..led += 1
      ..nextAtMs = now + recipe.rechargeMs;
    s.countCombo();

    final specId = recipe.projectile!;
    final p = s.comboProjectile(
      leader,
      specId: specId,
      target: target,
      damage: recipe.bulletFromLeader || !v.has(_bulletDamage) ? null : value(_bulletDamage),
      poison: v.number('bulletPoison') ?? helperPoison ?? defaults.number('bulletPoison')!,
      firePoints: firePoints,
    );
    if (v.boolean('holdingCapable') ?? false) RocketState.of(p).holdingCapable = true;
    final speed = v.number('moveSpeed');
    final blast = recipe.blast;
    final blastLoad = blast == null
        ? null
        : BlastLoad(
            type: blast,
            damage: value(_blastDamage),
            poison: v.number('blastPoison') ?? defaults.number('blastPoison')!,
            sound: recipe.sound,
          );
    final cluster = recipe.cluster;
    final clusterLoad = cluster == null
        ? null
        : ClusterLoad(
            type: cluster,
            qty: (v.number('clusterQty') ?? defaults.number('clusterQty')!).toInt(),
            damage: value('clusterDamage'),
            holding: v.boolean('clusterHolding') ?? defaults.boolean('clusterHolding')!,
            laser: v.boolean('clusterLaser') ?? false,
            laserDamage: value('clusterLaserDamage'),
          );
    OnboardWeapon? laser;
    if (v.has('laserDamage')) {
      final type = v.string('laserType') ?? defaults.string('laserType');
      final damage = value('laserDamage');
      final range = v.number('laserRange') ?? defaults.number('laserRange')!;
      final intervalMs = fireIntervalMs(v.number('laserRate') ?? defaults.number('laserRate')!);
      if (type != null) {
        laser = OnboardWeapon(
          projectile: type,
          damage: damage,
          range: range,
          intervalMs: intervalMs,
        );
      }
    }
    OnboardWeapon? subRocket;
    if (v.boolean('rocketCapable') ?? false) {
      final type = defaults.string('rocketType');
      final damage = value('rocketDamage');
      final intervalMs = fireIntervalMs(defaults.number('rocketRate')!);
      if (type != null) {
        subRocket = OnboardWeapon(projectile: type, damage: damage, intervalMs: intervalMs);
      }
    }
    final napalm = v.has('napalmQuantity')
        ? NapalmLoad(
            qty: v.number('napalmQuantity')!.toInt(),
            timingMs: v.number('napalmTiming') ?? defaults.number('napalmTiming')!,
            jitter: v.number('napalmJit') ?? defaults.number('napalmJit')!,
          )
        : null;
    final laserBlast = s.config.profile.laserRocketLaserBlast && v.has('laserblastQty')
        ? LaserBlastLoad(
            qty: v.number('laserblastQty')!.toInt(),
            damage: value('laserblastDamage'),
            range: v.number('laserblastRange')!,
          )
        : null;
    final hole = v.has('blackholeRadius')
        ? HoleLoad(radius: v.number('blackholeRadius')!, durationMs: v.number('blackholeDuration')!)
        : null;
    Vec2? placed;
    final place = recipe.place;
    if (place != null) {
      final points = place == 'minePoint' ? minePoints(s, leader) : holePoints(s, leader);
      final chosen = pickRandom(s.random, points, 1);
      placed = chosen.isEmpty ? null : chosen.single;
      p.position = leader.position;
    }
    p.load = Ordnance(
      combo: recipe.id,
      speed: speed,
      blast: blastLoad,
      cluster: clusterLoad,
      laser: laser,
      laserFiredAtMs: laser == null ? 0 : now,
      subRocket: subRocket,
      subRocketFiredAtMs: subRocket == null ? 0 : now,
      napalm: napalm,
      laserBlast: laserBlast,
      place: placed,
      hole: hole,
    );
    s.emit(
      ComboFired(
        s.stepIndex,
        uid: leader.uid,
        combo: recipe.id,
        helpers: [for (final h in taken) h.uid],
        projectile: specId,
        sound: blast == null ? recipe.sound : null,
      ),
    );
    s.launchProjectile(p);
    return p;
  }

  /// `Turret.comboFindMinepoints`: the road's mine points within the
  /// *maximum* of [t]'s range track (not its current range).
  static List<Vec2> minePoints(GameSession s, Turret t) {
    final track = t.def.upgrades.range;
    if (track.isEmpty) return const [];
    final max = track.last.value;
    return [
      for (final m in s.road.minePoints)
        if (t.position.distanceTo(m) <= max) m,
    ];
  }

  /// `Turret.comboFindBlackHolePoints`: the mine points within
  /// `blackHolePointRange` of [t].
  static List<Vec2> holePoints(GameSession s, Turret t) {
    final range = s.data.rules.blackHolePointRange;
    return [
      for (final m in s.road.minePoints)
        if (t.position.distanceTo(m) <= range) m,
    ];
  }

  static const String _bulletDamage = 'bulletDamage';
  static const String _blastDamage = 'blastDamage';
}

/// `OnslaughtObject.as:arrayPick`: [n] distinct random items of [list]; the
/// list itself when it has exactly [n]; one item by one draw; two by
/// drawing pairs until they differ. Fewer when the list is shorter (the
/// original returns `[undefined]` for an empty list, and would loop forever
/// picking two of one).
List<T> pickRandom<T>(SimRandom random, List<T> list, int n) {
  if (n <= 0) return [];
  if (list.length == n) return List.of(list);
  if (n == 1) {
    // The original draws once even from an empty list.
    if (list.isEmpty) {
      random.nextDouble();
      return [];
    }
    return [list[random.nextInt(list.length)]];
  }
  if (list.length < n) return List.of(list);
  if (n == 2) {
    var i = 0;
    var j = 0;
    while (i == j) {
      i = random.nextInt(list.length);
      j = random.nextInt(list.length);
    }
    return [list[i], list[j]];
  }
  final rest = List.of(list);
  return [for (var k = 0; k < n; k++) rest.removeAt(random.nextInt(rest.length))];
}
