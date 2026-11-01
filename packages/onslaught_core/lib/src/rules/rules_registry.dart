import '../data/game_data.dart';
import '../data/params.dart';
import '../sim/entities.dart';
import '../sim/game_session.dart';
import 'behaviours/beam.dart';
import 'behaviours/black_hole.dart';
import 'behaviours/blasts.dart';
import 'behaviours/cluster_bomb.dart';
import 'behaviours/landmine.dart';
import 'behaviours/rail.dart';
import 'behaviours/rocket.dart';
import 'behaviours/shell.dart';
import 'behaviours/shockwave.dart';
import 'behaviours/sniper_shot.dart';
import 'behaviours/walker.dart';
import 'specials/charge.dart';
import 'specials/combo.dart';
import 'specials/combonly.dart';
import 'specials/freakout.dart';
import 'specials/fusion.dart';
import 'specials/holding.dart';
import 'specials/link.dart';
import 'specials/modifier.dart';
import 'specials/plain.dart';
import 'specials/targeter.dart';

/// A mechanic that data refers to by id. New mechanics are new behaviours
/// plus data, never new branches in existing systems (rule R4).
abstract interface class Behaviour {
  /// The id data uses to refer to this behaviour (`holding`, `rocket` …).
  String get id;

  /// Parameter keys this behaviour reads from its owner's `params`, or null
  /// when it reads none / does not check.
  Set<String>? get paramKeys;
}

/// A turret special (`link`, `holding`, `charge`, `freakout`, `modifier`,
/// `targeter` …): what a turret does beyond aiming and firing its weapon.
/// The turret system calls these hooks for every special a turret's data
/// names, in data order; each does nothing unless overridden.
abstract class TurretSpecial implements Behaviour {
  const TurretSpecial();

  /// [t]'s parameters for this special (its turret data's
  /// `specialParams[id]`), empty when it has none.
  Params params(Turret t) => t.def.specialParams[id] ?? Params.empty;

  /// [turret] was just built (its `onLoad`), after the relations refresh.
  void onBuilt(GameSession session, Turret turret) {}

  /// Whether this special runs [turret]'s whole update itself ([update])
  /// instead of the turret system's aim-and-fire (Targeter, Fusion,
  /// Combonly, whose `update` differs from the colours').
  bool get ownsUpdate => false;

  /// Every update of [turret] when this special [ownsUpdate]; [dtMs] is the
  /// game time since its last update.
  void update(GameSession session, Turret turret, double dtMs) {}

  /// [turret]'s own `turretTryFiring` at [target], when it is not the
  /// colours' (bear, reload, combo or shot): fire in this special's way and
  /// return true, or return false for the usual one. A Targeter calls this
  /// on the turrets it joins; [dtMs] is the game time since [turret]'s last
  /// update.
  bool tryFiring(GameSession session, Turret turret, Creep target, double dtMs) => false;

  /// A shot carrying [damage] and [poison] was fired into [turret] (a
  /// Fusion cannon's `attackerHit` / `attackerPoison`).
  void absorb(
    GameSession session,
    Turret turret, {
    required double damage,
    required double poison,
  }) {}

  /// Every simulation step with the real (unscaled) step length, paused or
  /// not: timers on the original's real-time clock.
  void onRealTime(GameSession session, Turret turret, double realMs) {}

  /// Turret [other] was built, or moved to here (`notifyNew`).
  void onTurretAdded(GameSession session, Turret turret, Turret other) {}

  /// Turret [other] was sold, consumed, or moved away (`notifyGone`).
  void onTurretGone(GameSession session, Turret turret, Turret other) {}

  /// [turret] itself was moved (`onMove`), after the others were told.
  void onMoved(GameSession session, Turret turret) {}

  /// After [turret] was upgraded (`Turret.upgradeDone`: `onUpgrade`,
  /// `freakoutActivate`).
  void onUpgraded(GameSession session, Turret turret) {}

  /// Adds what [turret] does to the turrets around it (modifier auras).
  /// Run for every turret after any build, sell, move or upgrade, once the
  /// session has reset every turret's [Turret.aura].
  void applyRelations(GameSession session, Turret turret) {}

  /// Every simulation step, whether or not [turret]'s update timer ticks
  /// (work the original does every frame: `FreakoutEngine.onEnterFrame`).
  void onStep(GameSession session, Turret turret, double dtMs) {}

  /// Every update of [turret] (each tick of its timer), before it picks a
  /// target; [dtMs] is the game time since its last update.
  void beforeAim(GameSession session, Turret turret, double dtMs) {}

  /// [turret] is reloaded and aimed at [target]: fire it in this special's
  /// way and return true, or return false to leave the shot to the next
  /// special or the plain weapon.
  bool fire(GameSession session, Turret turret, Creep target) => false;

  /// [turret] just fired [projectile] (`turretFire`), before it launches.
  void onShot(GameSession session, Turret turret, Projectile projectile) {}

  /// Every update, after [turret] aimed and maybe fired; [hadTarget] says
  /// whether it had a target.
  void afterAim(
    GameSession session,
    Turret turret, {
    required bool hadTarget,
    required double dtMs,
  }) {}

  /// [turret] is being sold, before it is removed (`onSell`).
  void onSold(GameSession session, Turret turret) {}

  /// [turret] was consumed by a Combonly plate and has just been removed.
  /// The original calls no hook here (`TurretManager.as` removes it like a
  /// sale, without `onSell`), so only a `RulesProfile` fix may act on it.
  void onConsumed(GameSession session, Turret turret) {}
}

/// A projectile kind (`shell`, `rocket`, `beam`, `spark`, `landmine` …):
/// how a [Projectile] of this kind moves and hits.
abstract interface class ProjectileKind implements Behaviour {
  /// Called once when [projectile] is created (the original's constructor):
  /// instant kinds hit here.
  void launch(GameSession session, Projectile projectile);

  /// Advances [projectile] by [dtMs] game ms; sets [Projectile.done] when
  /// it is spent.
  void step(GameSession session, Projectile projectile, double dtMs);
}

/// A projectile kind with timers on the original's real-time ("eternal")
/// clock, which keeps running while the game is paused and ignores the
/// game speed (black holes under the classic rules).
abstract interface class RealTimeProjectileKind implements ProjectileKind {
  /// Advances [projectile] by [realMs] real milliseconds; called every step,
  /// paused or not, after the game-time systems.
  void stepRealTime(GameSession session, Projectile projectile, double realMs);
}

/// A blast kind (`blast`, `napalm`, `shockwave`, `cluster-rockets`,
/// `cluster-sparks`): what a [Blast] of this kind does.
abstract interface class BlastKind implements Behaviour {
  /// Called once when [blast] is created (the original's constructor and
  /// `onLoad`): instant kinds (clusters) do all their work here.
  void start(GameSession session, Blast blast);

  /// Advances [blast] by [dtMs] game ms; sets [Blast.done] when it is over.
  void step(GameSession session, Blast blast, double dtMs);
}

/// A creep behaviour (`walker`, and later anything content packs add):
/// how a [Creep] moves.
abstract interface class CreepBehaviour implements Behaviour {
  /// Called once when [creep] spawns.
  void start(GameSession session, Creep creep);

  /// [creep]'s speed changed (slowed or recovering): re-plan its movement.
  void onSpeedChanged(GameSession session, Creep creep);

  /// Advances [creep] by [dtMs] game ms.
  void step(GameSession session, Creep creep, double dtMs);
}

/// Id → behaviour lookup for every extensible mechanic. Sessions resolve the
/// behaviours their data names through this; tests can register fakes.
class RulesRegistry implements KnownBehaviours {
  RulesRegistry();

  /// The original game's mechanics.
  factory RulesRegistry.classic() {
    final r = RulesRegistry()
      ..registerProjectileKind(const ShellKind())
      ..registerProjectileKind(const BeamKind())
      ..registerProjectileKind(const SparkKind())
      ..registerProjectileKind(const RocketKind())
      ..registerProjectileKind(const ClusterBombKind())
      ..registerProjectileKind(const LandmineKind())
      ..registerProjectileKind(const BlackHoleKind())
      ..registerProjectileKind(const SniperShotKind())
      ..registerProjectileKind(const RailKind())
      ..registerBlastKind(const PlainBlastKind())
      ..registerBlastKind(const NapalmKind())
      ..registerBlastKind(const ShockwaveKind())
      ..registerBlastKind(const ClusterRocketsKind())
      ..registerBlastKind(const ClusterSparksKind())
      ..registerTurretSpecial(const ComboSpecial())
      ..registerTurretSpecial(const FreakoutSpecial())
      ..registerTurretSpecial(const LinkSpecial())
      ..registerTurretSpecial(const HoldingSpecial())
      ..registerTurretSpecial(const ChargeSpecial())
      ..registerTurretSpecial(const ModifierSpecial())
      ..registerTurretSpecial(const TargeterSpecial())
      ..registerTurretSpecial(const FusionSpecial())
      ..registerTurretSpecial(const CombonlySpecial())
      ..registerTurretSpecial(
        const PlainSpecial(
          'sniper',
          paramKeys: {
            'brassMax',
            'brassFadeAfterMs',
            'brassFadeMs',
            'brassMs',
            'brassJitter',
            'brassSpin',
            'brassPoint',
            'brassPointTo',
          },
        ),
      )
      ..registerTurretSpecial(const PlainSpecial('railgun'))
      ..registerCreepBehaviour(const WalkerBehaviour());
    return r;
  }

  final Map<String, TurretSpecial> _turretSpecials = {};
  final Map<String, ProjectileKind> _projectileKinds = {};
  final Map<String, BlastKind> _blastKinds = {};
  final Map<String, CreepBehaviour> _creepBehaviours = {};

  void registerTurretSpecial(TurretSpecial b) => _turretSpecials[b.id] = b;
  void registerProjectileKind(ProjectileKind b) => _projectileKinds[b.id] = b;
  void registerBlastKind(BlastKind b) => _blastKinds[b.id] = b;
  void registerCreepBehaviour(CreepBehaviour b) => _creepBehaviours[b.id] = b;

  TurretSpecial turretSpecial(String id) => _lookup(_turretSpecials, id, 'turret special');
  ProjectileKind projectileKind(String id) => _lookup(_projectileKinds, id, 'projectile kind');
  BlastKind blastKind(String id) => _lookup(_blastKinds, id, 'blast kind');
  CreepBehaviour creepBehaviour(String id) => _lookup(_creepBehaviours, id, 'creep behaviour');

  /// Whether this registry has rules for projectile kind [kind].
  bool implementsProjectileKind(String kind) => _projectileKinds.containsKey(kind);

  /// Whether a turret with special [id] can be built: this registry has
  /// rules for the special.
  bool allowsTurretSpecial(String id) => _turretSpecials.containsKey(id);

  @override
  Set<String> get turretSpecialIds => _turretSpecials.keys.toSet();
  @override
  Set<String> get projectileKindIds => _projectileKinds.keys.toSet();
  @override
  Set<String> get blastKindIds => _blastKinds.keys.toSet();
  @override
  Set<String> get creepBehaviourIds => _creepBehaviours.keys.toSet();

  static T _lookup<T>(Map<String, T> m, String id, String what) {
    final b = m[id];
    if (b == null) throw ArgumentError.value(id, 'id', 'no $what registered');
    return b;
  }
}
