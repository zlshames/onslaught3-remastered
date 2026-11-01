import '../data/turret_def.dart';
import '../rules/aiming.dart';
import '../rules/behaviours/shockwave.dart';
import '../rules/rules_registry.dart';
import 'entities.dart';
import 'game_session.dart';
import 'sim_constants.dart';

/// The classic game-time systems in their fixed order
/// (`docs/REMASTER_PLAN.md` §2.3): waves → creeps → turrets → projectiles →
/// blasts → black-hole captures. After them the session runs the real-time
/// timers, then its own [ObjectiveSystem] (the win check), then removes dead
/// creeps and spent projectiles, blasts and walkers (the cleanup step).
List<SimSystem> classicSystems() => [
  WaveSystem(),
  CreepSystem(),
  TurretSystem(),
  ProjectileSystem(),
  BlastSystem(),
  CaptureSystem(),
];

/// Sends waves and spawns their creeps (`AttackerManager.update`,
/// `WaveManager.update`). Both run on their own `managerTickMs` interval,
/// which is why creeps leave every 800 ms rather than 700: a creep spawns on
/// the first check after more than `creepSpacingMs` has passed. The
/// manager's interval starts with the game; each wave's starts when it is
/// sent. The manager's check also runs the time limit and, with wave
/// follow on, sends the next wave as soon as the field is clear.
class WaveSystem implements SimSystem {
  @override
  String get name => 'waves';

  @override
  void step(GameSession s, double dtMs) {
    final defs = s.data.waves;
    final tick = defs.managerTickMs;
    final waves = s.waves;
    final now = s.clock.nowMs;
    // A wave sent during this step starts its own interval from now.
    final spawners = List.of(waves.spawners);
    waves.sinceCheckMs += dtMs;
    while (_due(waves.sinceCheckMs, tick)) {
      waves.sinceCheckMs -= tick;
      // `AttackerManager.update`: the time limit first; once the waves have
      // ended the manager stops (waves already sending carry on below).
      s.checkTimeLimit();
      if (s.objectives.noMoreWaves || s.clock.stopped) continue;
      if (now - waves.lastWaveMs > s.waveSpacingMs) s.waveSend(early: false);
      if (s.waveFollow && s.fieldClear) s.waveSend(early: false);
    }
    for (final spawner in spawners) {
      spawner.sinceCheckMs += dtMs;
      while (!spawner.done && _due(spawner.sinceCheckMs, tick)) {
        spawner.sinceCheckMs -= tick;
        if (now - spawner.lastSpawnMs > defs.creepSpacingMs) {
          spawner.lastSpawnMs = now;
          s.spawnCreep(spawner);
        }
      }
    }
    waves.spawners.removeWhere((w) => w.done);
  }

  /// Whether an interval of [tickMs] has elapsed, allowing for the rounding
  /// of summed 1/60 s steps.
  static bool _due(double elapsed, double tickMs) => elapsed >= tickMs - epsilonMs;
}

/// Moves every creep with its behaviour. Creeps spawned during this step
/// (at its end time) start moving on the next one.
class CreepSystem implements SimSystem {
  @override
  String get name => 'creeps';

  @override
  void step(GameSession s, double dtMs) {
    final now = s.clock.nowMs;
    for (final c in s.creeps) {
      if (s.clock.stopped) return;
      if (c.gone || c.blackHoled || c.createdAtMs >= now) continue;
      s.registry.creepBehaviour(c.behaviour).step(s, c, dtMs);
    }
  }
}

/// Runs every turret in build order. Each turret updates on its own timer
/// (`setInterval(update, frame_space)`, 70 ms, started when it is built or
/// moved; real time, so twice the game time at 2× speed): every step its
/// specials' [TurretSpecial.onStep] runs (frame-driven work such as
/// freakout stages), and when its timer has ticked it updates with the game
/// time since its last update (each colour's `update` / `turretTryFiring`):
///
/// 1. its specials' [TurretSpecial.beforeAim] (freakout schedule, charge,
///    link offer);
/// 2. keep the current target while it is in range, else acquire one by the
///    turret's target mode;
/// 3. turn toward it; a must-face weapon fires only once facing it;
/// 4. when more than `60000 / rate` ms have passed since the last shot, the
///    first special that fires its own way does ([TurretSpecial.fire]:
///    combos, link pooling, charged shots), else the plain weapon fires;
/// 5. its specials' [TurretSpecial.afterAim] (combo helpers turning to
///    their leader, holding pattern).
///
/// So a turret fires on the first tick after it has reloaded, and a
/// reloaded helper stays ready for a combo until its own next tick. The
/// first tick after a build does nothing (`time_last` starts undefined);
/// ticks while paused do nothing but keep the timer's phase. Ticks land on
/// simulation steps (1/60 s), so they come every 66.7 or 83.3 ms, 70 on
/// average. A [TurretDef.tickMs] of 0 updates every step.
///
/// Turrets without a weapon (modifiers) only run their specials. Combos are
/// the first special of every colour, so a combo pre-empts link pooling and
/// charged shots, as each colour's `turretTryFiring` does. A turret whose
/// special [TurretSpecial.ownsUpdate] (Targeter, Fusion, Combonly) updates
/// its own way instead. A turret with no target of its own turns toward the
/// creep a Targeter last sent it at. Inactive turrets (being consumed by a
/// Combonly plate) do nothing.
class TurretSystem implements SimSystem, RealTimeSystem {
  @override
  String get name => 'turrets';

  @override
  void step(GameSession s, double dtMs) {
    final now = s.clock.nowMs;
    for (final t in List.of(s.turrets)) {
      if (!s.turrets.contains(t) || !t.active) continue;
      for (final sp in s.specialsOf(t)) {
        sp.onStep(s, t, dtMs);
      }
      if (!_ticked(t, s.clock.stepMs)) continue;
      final last = t.updatedAtMs;
      t.updatedAtMs = now;
      if (last == null || now - last <= 0) continue;
      updateTurret(s, t, now - last);
    }
  }

  /// Runs the specials' real-time timers, and keeps each update timer's
  /// phase while paused (the original's ticks still come, and do nothing).
  @override
  void stepRealTime(GameSession s, double realMs) {
    for (final t in List.of(s.turrets)) {
      if (!s.turrets.contains(t)) continue;
      for (final sp in s.specialsOf(t)) {
        sp.onRealTime(s, t, realMs);
      }
    }
    if (!s.clock.paused) return;
    for (final t in s.turrets) {
      _ticked(t, realMs);
    }
  }

  /// Advances [t]'s timer by [realMs]; whether it ticked.
  static bool _ticked(Turret t, double realMs) {
    final tick = t.def.tickMs;
    if (tick <= 0) return true;
    t.sinceTickMs += realMs;
    if (t.sinceTickMs < tick - epsilonMs) return false;
    t.sinceTickMs = (t.sinceTickMs - tick).clamp(0, tick);
    return true;
  }

  /// One update of [t] covering [dtMs] game ms (each colour's `update`).
  void updateTurret(GameSession s, Turret t, double dtMs) {
    final specials = s.specialsOf(t).toList();
    for (final sp in specials) {
      if (sp.ownsUpdate) return sp.update(s, t, dtMs);
    }
    for (final sp in specials) {
      sp.beforeAim(s, t, dtMs);
    }
    if (t.def.projectiles.isEmpty) return;
    final target = acquireFor(s, t);
    if (target != null) {
      t.bearCreepUid = null;
      turretTryFiring(s, t, target, dtMs);
    } else {
      bearToCreep(s, t, dtMs);
    }

    for (final sp in specials) {
      sp.afterAim(s, t, hadTarget: target != null, dtMs: dtMs);
    }
  }
}

/// Moves projectiles and resolves hits with each one's kind. Shots fired
/// during this step (at its end time) fly from the next one. A projectile
/// being pulled into a black hole does nothing else. Kinds with real-time
/// timers also get [RealTimeProjectileKind.stepRealTime].
class ProjectileSystem implements SimSystem, RealTimeSystem {
  @override
  String get name => 'projectiles';

  @override
  void step(GameSession s, double dtMs) {
    final now = s.clock.nowMs;
    for (final p in List.of(s.projectiles)) {
      if (s.clock.stopped) return;
      if (p.done || p.capture != null || p.createdAtMs >= now) continue;
      s.registry.projectileKind(p.kind).step(s, p, dtMs);
    }
  }

  @override
  void stepRealTime(GameSession s, double realMs) {
    for (final p in List.of(s.projectiles)) {
      if (p.done || p.capture != null) continue;
      final kind = s.registry.projectileKind(p.kind);
      if (kind is RealTimeProjectileKind) kind.stepRealTime(s, p, realMs);
    }
  }
}

/// Runs blasts with their kind (grow → damage → fade, napalm drops,
/// clusters) and moves shockwave walkers. Blasts set off during this step
/// run from the next one; a blast being pulled into a black hole stops.
class BlastSystem implements SimSystem {
  @override
  String get name => 'blasts';

  @override
  void step(GameSession s, double dtMs) {
    final now = s.clock.nowMs;
    for (final b in List.of(s.blasts)) {
      if (s.clock.stopped) return;
      if (b.done || b.capture != null || b.createdAtMs >= now) continue;
      s.registry.blastKind(b.kind).step(s, b, dtMs);
    }
    for (final w in List.of(s.walkers)) {
      if (s.clock.stopped) return;
      if (w.done || w.startedAtMs >= now) continue;
      stepWalker(s, w, dtMs);
    }
  }
}

/// Pulls captured creeps, projectiles and blasts into their black hole and
/// removes them at its centre (`OnslaughtObject.as:blackHoled`). The
/// original runs the pull on its real-time clock (paused or not, whatever
/// the game speed); `RulesProfile.blackHoleGameClock` runs it on game time.
class CaptureSystem implements SimSystem, RealTimeSystem {
  @override
  String get name => 'captures';

  @override
  void step(GameSession s, double dtMs) {
    if (s.config.profile.blackHoleGameClock) _advance(s, dtMs);
  }

  @override
  void stepRealTime(GameSession s, double realMs) {
    if (!s.config.profile.blackHoleGameClock) _advance(s, realMs);
  }

  static void _advance(GameSession s, double ms) {
    for (final c in List.of(s.creeps)) {
      final cap = c.capture;
      if (cap == null || c.gone) continue;
      cap.elapsedMs += ms;
      c.position = cap.position;
      if (cap.done) {
        final hole = s.projectileByUid(cap.hole);
        s.swallowCreep(c, hole: cap.hole, by: hole?.turretUid, bounty: c.bountyBeforeHole);
      }
    }
    for (final p in s.projectiles) {
      final cap = p.capture;
      if (cap == null || p.done) continue;
      cap.elapsedMs += ms;
      p.position = cap.position;
      if (cap.done) p.done = true;
    }
    for (final b in s.blasts) {
      final cap = b.capture;
      if (cap == null || b.done) continue;
      cap.elapsedMs += ms;
      b.position = cap.position;
      if (cap.done) b.done = true;
    }
  }
}
