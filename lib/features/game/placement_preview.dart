import 'package:onslaught_core/onslaught_core.dart';

import 'game_snapshots.dart';

/// The ghost of [turretId] at [at] in [session] (null = off the map): a
/// build, or with [moving] a move of that turret. Valid when the world
/// accepts commands, the cash covers the build or move cost and the spot
/// is free. [locked] marks a dropped-and-locked ghost. Null for an unknown
/// turret id. Reads the session; changes nothing.
PlacementPreview? placementPreview(
  GameSession session,
  String turretId,
  Vec2? at, {
  int? moving,
  bool locked = false,
}) {
  final data = session.data;
  final def = data.turrets[turretId];
  if (def == null) return null;
  final mover = moving == null ? null : session.turretByUid(moving);
  final cost = mover == null ? def.cost : data.world.placement.moveCost;
  final valid =
      at != null &&
      !session.gameOver &&
      !session.clock.paused &&
      session.cash >= cost &&
      session.placementIssueAt(at, moving: mover) == null;
  return PlacementPreview(
    turretId: turretId,
    at: at,
    valid: valid,
    range: at == null
        ? (mover == null ? def.stats.range : session.statOf(mover, StatKind.range))
        : _rangeAt(session, def, at, mover),
    moving: mover?.uid,
    locked: locked && at != null,
  );
}

/// The command that places ghost [p] (a build, or a move of the turret it
/// moves), or null when there is no valid ghost on the map.
GameCommand? placementCommand(PlacementPreview? p) {
  final at = p?.at;
  if (p == null || !p.valid || at == null) return null;
  final moving = p.moving;
  return moving == null ? BuildTurret(p.turretId, at.x, at.y) : MoveTurret(moving, at.x, at.y);
}

/// The range a turret of [def] (or [mover]) would have at [at]: its range
/// level's value with the auras of the modifiers covering [at] (and the
/// mover's running freakouts).
double _rangeAt(GameSession session, TurretDef def, Vec2 at, Turret? mover) {
  final terms =
      ModifierSpecial.termsAt(session, at, exclude: mover, modifiable: def.modifiable) +
      (mover?.freak ?? StatTerms.identity);
  final base = mover == null ? def.stats.range : turretBaseStat(mover, StatKind.range);
  return effectiveStat(
    base: base,
    added: terms.added(StatKind.range),
    mult: terms.mult(StatKind.range),
    multFloor: session.data.rules.modifierMultFloor,
  );
}
