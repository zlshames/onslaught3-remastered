import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../data/params.dart';
import '../../data/turret_def.dart';
import '../../sim/entities.dart';
import '../../sim/game_session.dart';
import '../aiming.dart';
import '../rules_registry.dart';
import '../stat_rules.dart';

/// How much energy a Fusion cannon shows (`fusionSetGlow`).
enum FusionTier { none, low, med, high, max }

class FusionState extends SpecialState {
  FusionState(this.sound);

  /// Energy stored from its feeders (`store_damage`, `store_poison`).
  double storeDamage = 0;
  double storePoison = 0;

  /// The feeders it is going through (`fusion_list`), newest first; null
  /// once a pass found none ready, so the next update takes a fresh list.
  List<int>? feeders;

  /// Glow pulse: the glow is drawn `glowPulse` × larger on alternate
  /// updates (`fusion_glow_pulse`).
  bool pulse = false;

  /// Sound of its next discharge (`sound_fire`), set by its glow tier.
  String? sound;

  /// Feeder shots absorbed.
  int fed = 0;

  @override
  Map<String, Object?> toJson() => {
    'store': [storeDamage, storePoison],
    'feeders': ?feeders,
    'pulse': pulse,
    'sound': ?sound,
    'fed': fed,
  };
}

/// The Fusion cannon (`turrets/TurretFusion.as`; `docs/legacy/ENGINE_NOTES.md`
/// §4.7).
///
/// * Feeding: every update it goes through its feeders (`fusionFeeder`
///   turrets, Green and Yellow, within its range) and the first one that has
///   reloaded fires its plain shot into it (a laser or a spark at the cannon,
///   with sound; it spends its reload and Yellow drops its target with lock
///   off). At most one feeder per update; feeders shoot creeps on their own
///   updates as usual. It keeps the same list until a pass finds no feeder
///   ready, so a feeder built meanwhile joins only after such a pass.
/// * It stores `absorbDamage` × each shot's damage and `absorbPoison` × its
///   poison (only sparks carry poison).
/// * Discharge: when it has a target, faces it, more than `storeTimeMs` have
///   passed since its last shot and it has reloaded, it fires a spark with
///   `min(damage, stored) + damage` and `min(dischargePoisonMax, stored
///   poison)` poison, and takes those from the store. It fires even with an
///   empty store. Its sound is its glow tier's.
/// * While it turns toward a target without facing it, its update ends early
///   and the time of its last update is not moved on, so its next turn is
///   longer: it turns faster the longer it turns (`return false` before
///   `time_last = now`).
/// * Glow: [tierOf] the stored damage, alternating size each update.
///
/// A Targeter joined to it makes it discharge without the `storeTimeMs`
/// wait (its `turretTryFiring` has no such check). Feeders are taken newest
/// first: `fusionGetInRange` lists them with AS2's `for…in` over the
/// turrets, assumed to walk arrays from the end (not observed).
class FusionSpecial extends TurretSpecial {
  const FusionSpecial();

  static const String specialId = 'fusion';

  @override
  String get id => specialId;

  @override
  Set<String>? get paramKeys => const {
    'glowUnit',
    'glowTierSize',
    'glowPulse',
    'dischargePoisonMax',
    'soundLow',
    'soundMed',
    'soundHigh',
    'soundMax',
    'storeTimeMs',
    'absorbDamage',
    'absorbPoison',
    'tickMs',
  };

  /// [Turret.stateOf] for this special: rules only (it creates the state).
  @internal
  static FusionState stateOf(Turret t) => t.stateOf(specialId, () => FusionState(t.def.fireSound));

  /// The glow tier of [storeDamage] (`fusionSetGlow`): none when the store
  /// is exactly 0, else by `floor(store / glowUnit)` in tiers of
  /// `glowTierSize`. A store under one unit shows no tier change (null).
  static FusionTier? tierOf(Params p, double storeDamage) {
    if (storeDamage == 0) return FusionTier.none;
    final u = (storeDamage / p.number('glowUnit')!).floor();
    if (u <= 0) return null;
    // One tier per `glowTierSize` units, the last one open-ended.
    final above = FusionTier.max.index - FusionTier.low.index;
    final step = math.min((u / p.number('glowTierSize')!).floor(), above);
    return FusionTier.values[FusionTier.low.index + step];
  }

  /// The turrets that feed [t]: feeders within its range, newest first.
  static List<Turret> feedersOf(GameSession s, Turret t) {
    final range = turretStat(t, StatKind.range, s.data.rules);
    return s.turretsNear(t, range, where: (o) => o.def.fusionFeeder).toList().reversed.toList();
  }

  @override
  void onBuilt(GameSession session, Turret turret) {
    // `onLoad`: `weapon_fired = now`, so the first discharge waits too.
    turret.firedAtMs = session.clock.nowMs;
    stateOf(turret);
  }

  @override
  void absorb(
    GameSession session,
    Turret turret, {
    required double damage,
    required double poison,
  }) {
    final p = params(turret);
    stateOf(turret)
      ..storeDamage += damage * p.number('absorbDamage')!
      ..storePoison += poison * p.number('absorbPoison')!
      ..fed += 1;
  }

  @override
  bool get ownsUpdate => true;

  @override
  void update(GameSession session, Turret turret, double dtMs) {
    final s = session;
    final st = stateOf(turret);
    _feed(s, turret, st);
    final target = acquireFor(s, turret);
    if (target != null) {
      if (!turnToward(s, turret, target.position, dtMs) && turret.def.stats.mustFace) {
        // Returns before `time_last = now`.
        turret.updatedAtMs = s.clock.nowMs - dtMs;
        return;
      }
      if (s.clock.nowMs - turret.firedAtMs > params(turret).number('storeTimeMs')!) {
        turretTryFiring(s, turret, target, dtMs);
      }
    } else {
      bearToCreep(s, turret, dtMs);
    }
    _glow(turret, st);
  }

  /// Its `turretTryFiring`: turn, and when facing and reloaded, discharge.
  @override
  bool tryFiring(GameSession session, Turret turret, Creep target, double dtMs) {
    if (!turnToward(session, turret, target.position, dtMs) && turret.def.stats.mustFace) {
      return true;
    }
    if (session.canFire(turret)) _discharge(session, turret, target);
    return true;
  }

  /// One feeding pass (the start of `TurretFusion.update`).
  void _feed(GameSession s, Turret t, FusionState st) {
    final uids = st.feeders ??= [for (final f in feedersOf(s, t)) f.uid];
    for (final uid in uids) {
      final f = s.turretByUid(uid);
      if (f == null || !f.active || !s.canFire(f)) continue;
      s.turretFire(f, into: t, damage: turretStat(f, StatKind.damage, s.data.rules));
      return;
    }
    st.feeders = null;
  }

  /// `fusionFire`.
  void _discharge(GameSession s, Turret t, Creep target) {
    final st = stateOf(t);
    final damage = turretStat(t, StatKind.damage, s.data.rules);
    final fromStore = math.min(damage, st.storeDamage);
    final poison = math.min(params(t).number('dischargePoisonMax')!, st.storePoison);
    s.turretFire(
      t,
      target: target,
      damage: fromStore + damage,
      poison: poison,
      sound: st.sound == t.def.fireSound ? null : st.sound,
    );
    st
      ..storeDamage -= fromStore
      ..storePoison -= poison;
  }

  /// `fusionSetGlow`: alternates the pulse and sets the discharge sound by
  /// tier while anything is stored.
  void _glow(Turret t, FusionState st) {
    if (st.storeDamage == 0) return;
    st.pulse = !st.pulse;
    final p = params(t);
    final sound = switch (tierOf(p, st.storeDamage)) {
      FusionTier.low => p.string('soundLow'),
      FusionTier.med => p.string('soundMed'),
      FusionTier.high => p.string('soundHigh'),
      FusionTier.max => p.string('soundMax'),
      FusionTier.none || null => st.sound,
    };
    st.sound = sound;
  }
}
