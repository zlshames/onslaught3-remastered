import 'dart:math' as math;

import '../../math/vec2.dart';
import '../../sim/entities.dart';
import '../../sim/game_session.dart';
import '../creep_rules.dart';
import '../rules_registry.dart';
import '../targeting_rules.dart';

/// The original creep (`AttackerEngine`): walks the road waypoint to
/// waypoint and hits the base after the last one.
///
/// Each leg is a linear tween from the creep's position to the next road
/// point plus a fresh jitter offset (`updateMove`). Its duration is the
/// distance to the *un-jittered* point divided by the current speed, so the
/// jitter slightly changes the effective speed, as in the original. Time
/// left over when a leg ends carries into the next one so movement does not
/// depend on the step size (the original loses up to one 32 ms tween tick
/// per waypoint).
///
/// Slows re-plan the current leg at the new speed (with a new jitter). While
/// slower than at spawn, one recovery timer at a time adds the recovery
/// amount every recovery interval of game time, capped at the spawn speed
/// (`attackerReplenish`), and re-plans the leg again.
class WalkerBehaviour implements CreepBehaviour {
  const WalkerBehaviour();

  @override
  String get id => 'walker';

  @override
  Set<String>? get paramKeys => null;

  @override
  void start(GameSession session, Creep creep) => _nextLeg(session, creep);

  @override
  void onSpeedChanged(GameSession session, Creep creep) => retarget(session, creep);

  @override
  void step(GameSession session, Creep creep, double dtMs) {
    final recoverAt = creep.recoverAtMs;
    if (recoverAt != null && session.clock.nowMs >= recoverAt) _recover(session, creep);
    var remaining = dtMs;
    while (remaining > 0 && !creep.gone) {
      final left = creep.legDurationMs - creep.legElapsedMs;
      if (remaining < left) {
        creep.legElapsedMs += remaining;
        creep.position = creep.legFrom.lerp(creep.legTo, creep.legElapsedMs / creep.legDurationMs);
        return;
      }
      remaining -= left;
      creep.position = creep.legTo;
      _nextLeg(session, creep);
    }
  }

  /// Ends the current leg (`AttackerEngine.update`): steps to the next road
  /// point, or hits the base after the last one.
  void _nextLeg(GameSession session, Creep creep) {
    creep.waypoint++;
    final road = session.road.points;
    if (creep.waypoint >= road.length) {
      session.creepReachedBase(creep);
      return;
    }
    retarget(session, creep);
  }

  /// `AttackerEngine.attackerReplenish`: regain speed, then re-plan.
  static void _recover(GameSession session, Creep creep) {
    final rules = session.data.rules;
    creep
      ..speed = math.min(creep.speed + rules.slowRecoverAmount, creep.baseSpeed)
      ..recoverAtMs = null;
    retarget(session, creep);
  }

  /// Starts a leg from the current position toward the current waypoint
  /// with a new jitter (`AttackerEngine.updateMove`, also run after every
  /// slow or speed recovery), and arms the recovery timer while the creep
  /// is slowed.
  static void retarget(GameSession session, Creep creep) {
    final point = session.road.points[creep.waypoint];
    final jitter = session.data.creeps.movement.number('waypointJitter') ?? 0;
    final dx = jitterOffset(session.random, jitter);
    final dy = jitterOffset(session.random, jitter);
    creep
      ..legFrom = creep.position
      ..legTo = point + Vec2(dx, dy)
      ..legDurationMs = creep.position.distanceTo(point) / creep.speed * 1000
      ..legElapsedMs = 0
      ..heading = bearingDeg(creep.position, point);
    if (creep.speed < creep.baseSpeed && creep.recoverAtMs == null) {
      creep.recoverAtMs = session.clock.nowMs + session.data.rules.slowRecoverIntervalMs;
    }
  }
}
