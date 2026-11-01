part of 'game_session.dart';

/// The one sanctioned way to change a session other than through
/// [GameSession.enqueue] and [GameSession.step]: tests and the soak driver
/// set a state up here, so every bypass of the command path is greppable
/// (`debug…`). Nothing in the game may use it; a replay of the commands
/// would not reproduce the state these make.
extension SessionDebug on GameSession {
  @visibleForTesting
  set debugCash(double v) => _cash = v;

  @visibleForTesting
  set debugLives(int v) => _lives = v;

  @visibleForTesting
  set debugKills(int v) => _kills = v;

  /// Makes turret [id] available without the kills.
  @visibleForTesting
  void debugMakeAvailable(String id) => _available.add(id);

  /// Drops every projectile in flight.
  @visibleForTesting
  void debugClearProjectiles() => _projectiles.clear();

  // World actions the rules use, for tests that stage a scene directly.

  @visibleForTesting
  Projectile debugAddProjectile({
    required String specId,
    required String kind,
    required Vec2 position,
    required double heading,
    required double damage,
    required int? targetUid,
    required int? turretUid,
    double poison = 0,
  }) => addProjectile(
    specId: specId,
    kind: kind,
    position: position,
    heading: heading,
    damage: damage,
    targetUid: targetUid,
    turretUid: turretUid,
    poison: poison,
  );

  @visibleForTesting
  void debugLaunchProjectile(Projectile p) => launchProjectile(p);

  @visibleForTesting
  Projectile debugTurretFire(Turret t, {Creep? target, required double damage}) =>
      turretFire(t, target: target, damage: damage);

  @visibleForTesting
  Blast debugSpawnBlast({
    required String specId,
    required Vec2 at,
    required double damage,
    required double poison,
    required int? turretUid,
    double angle = 0,
    int? targetUid,
  }) => spawnBlast(
    specId: specId,
    at: at,
    damage: damage,
    poison: poison,
    turretUid: turretUid,
    angle: angle,
    targetUid: targetUid,
  );

  @visibleForTesting
  void debugHitCreep(Creep creep, double damage, {int? by}) => hitCreep(creep, damage, by: by);

  @visibleForTesting
  void debugRemoveFinished() => removeFinished();
}
