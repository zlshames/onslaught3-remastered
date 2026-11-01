/// How turrets aim, shared by the turret system and the specials that run
/// their own update (Targeter, Fusion, Combonly).
library;

import '../data/turret_def.dart';
import '../math/vec2.dart';
import '../sim/entities.dart';
import '../sim/game_session.dart';
import 'rules_registry.dart';
import 'stat_rules.dart';
import 'targeting_rules.dart';

/// Keeps [t]'s current target while it is still a valid target in range,
/// else acquires one by its target mode within its range (modifiers
/// included); stores the result as [Turret.targetUid] and returns it.
Creep? acquireFor(GameSession s, Turret t) {
  final target = keepOrAcquireTarget(
    current: s.creepByUid(t.targetUid),
    creeps: s.creeps,
    from: t.position,
    range: turretStat(t, StatKind.range, s.data.rules),
    mode: t.targetMode ?? '',
    nowMs: s.clock.nowMs,
  );
  t.targetUid = target?.uid;
  return target;
}

/// Turns [t] toward [point] for [dtMs] game ms at its rotate speed
/// (`turretBearTowards`); whether it now faces it.
bool turnToward(GameSession s, Turret t, Vec2 point, double dtMs) {
  final bearing = bearTowards(
    rotation: t.rotation,
    bearing: bearingDeg(t.position, point),
    rotateDegPerS: t.def.stats.rotate,
    dtMs: dtMs,
    toleranceDeg: s.data.targeting.mustFaceToleranceDeg,
  );
  t.rotation = bearing.rotation;
  return bearing.faced;
}

/// [t] turns toward the creep a Targeter last sent it at
/// (`target_bear_to`), forgetting it once that creep is gone.
void bearToCreep(GameSession s, Turret t, double dtMs) {
  final uid = t.bearCreepUid;
  if (uid == null) return;
  final creep = s.creepByUid(uid);
  if (creep == null || !creep.targetable) {
    t.bearCreepUid = null;
    return;
  }
  turnToward(s, t, creep.position, dtMs);
}

/// [t]'s `turretTryFiring` at [target]: a special's own way
/// ([TurretSpecial.tryFiring]) or the colours': turn toward it, and once
/// facing it (or not needing to) and reloaded, let the first special that
/// fires its own way fire, else the plain weapon. Targeters call this on
/// the turrets they join, outside those turrets' own updates.
void turretTryFiring(GameSession s, Turret t, Creep target, double dtMs) {
  final specials = s.specialsOf(t).toList();
  for (final sp in specials) {
    if (sp.tryFiring(s, t, target, dtMs)) return;
  }
  if (t.def.projectiles.isEmpty) return;
  final faced = turnToward(s, t, target.position, dtMs);
  if (!faced && t.def.stats.mustFace) return;
  if (!s.canFire(t)) return;
  for (final sp in specials) {
    if (sp.fire(s, t, target)) return;
  }
  s.turretFire(t, target: target, damage: turretStat(t, StatKind.damage, s.data.rules));
}
