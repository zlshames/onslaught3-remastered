part of 'game_session.dart';

/// The combat API the systems and rules change the world through: projectiles
/// and blasts come into being here, creeps are hit, slowed, swallowed and
/// killed here (with the bounty, the kill count and the unlocks that follow).
/// Every member is `@internal`: the app reads the world and dispatches
/// [GameCommand]s; it never calls these.
extension WorldActions on GameSession {
  /// Adds a projectile to the world (turrets and projectile kinds call
  /// this). Call [launchProjectile] once it is set up.
  @internal
  Projectile addProjectile({
    required String specId,
    required String kind,
    required Vec2 position,
    required double heading,
    required double damage,
    required int? targetUid,
    required int? turretUid,
    double poison = 0,
  }) {
    final p = Projectile(
      uid: _nextUid++,
      specId: specId,
      kind: kind,
      position: position,
      heading: heading,
      damage: damage,
      targetUid: targetUid,
      turretUid: turretUid,
      createdAtMs: clock.nowMs,
      poison: poison,
    );
    _projectiles.add(p);
    return p;
  }

  /// Adds shockwave walker [w] to the road (the shockwave blast drops it).
  @internal
  void addWalker(ShockwaveWalker w) => _walkers.add(w);

  /// Counts a combo fired (`Game.weaponComboFired`).
  @internal
  void countCombo() => _combos++;

  /// Runs [p]'s kind's launch (instant kinds hit here).
  @internal
  void launchProjectile(Projectile p) => registry.projectileKind(p.kind).launch(this, p);

  /// Fires [t]'s weapon (`Turret.turretFire`): a projectile of its current
  /// damage level leaves the next fire point, at creep [target] or, with no
  /// creep, toward [at] (a link helper shooting its leader) or at nothing
  /// (a held rocket). The shot counts, reloads the weapon and, with lock
  /// off, drops the target. [silent] shots play no fire sound; [assist]
  /// marks a link helper's shot. A shot [into] a turret (a feeder charging a
  /// Fusion cannon) flies at it and the turret absorbs it; [sound] replaces
  /// the turret's fire sound. Specials see the projectile before it
  /// launches.
  @internal
  Projectile turretFire(
    Turret t, {
    Creep? target,
    Vec2? at,
    Turret? into,
    required double damage,
    double? poison,
    bool silent = false,
    bool assist = false,
    String? sound,
  }) {
    final specId = t.def.projectileAtLevel(t.damageLevel)!;
    final spec = data.projectiles[specId]!;
    final points = t.def.firePoints;
    final local = points.isEmpty ? Vec2.zero : points[t.firePointIndex % points.length];
    t
      ..firePointIndex += 1
      ..firedAtMs = clock.nowMs
      ..shots += 1;
    _shots++;
    final p =
        addProjectile(
            specId: specId,
            kind: spec.kind,
            position: t.position + rotateVec(local, t.rotation),
            heading: t.rotation,
            damage: damage,
            targetUid: target?.uid,
            turretUid: t.uid,
            poison: poison ?? turretPoison(t, data.rules),
          )
          ..lineTo = at ?? into?.position
          ..intoTurretUid = into?.uid;
    for (final sp in specialsOf(t)) {
      sp.onShot(this, t, p);
    }
    emit(
      TurretFired(
        stepIndex,
        uid: t.uid,
        projectile: specId,
        target: target?.uid,
        silent: silent,
        assist: assist,
        into: into?.uid,
        sound: sound,
      ),
    );
    launchProjectile(p);
    if (t.lockOff) t.targetUid = null;
    return p;
  }

  /// `turretFire` on a turret with no weapon (a Combonly plate pooling its
  /// link turrets): `bulletNew(undefined)` makes nothing, but the shot still
  /// counts and reloads.
  @internal
  void weaponlessShot(Turret t) {
    t
      ..firedAtMs = clock.nowMs
      ..shots += 1;
    _shots++;
  }

  /// A shot carrying [damage] and [poison] reached turret [uid] (fired into
  /// it): its specials absorb it.
  @internal
  void feedTurret(int uid, {required double damage, required double poison}) {
    final t = turretByUid(uid);
    if (t == null) return;
    for (final sp in specialsOf(t)) {
      sp.absorb(this, t, damage: damage, poison: poison);
    }
  }

  /// Fires [t]'s combo projectile [specId] (`Turret.comboFireBullet`): it
  /// leaves the next fire point along the weapon at [target] with the
  /// leader's effective damage unless [damage] is given, and the weapon
  /// reloads. Unlike [turretFire] it is not counted as a shot, plays no
  /// fire sound, keeps the target with lock off and skips the specials'
  /// [TurretSpecial.onShot]. Not launched yet: set its [Projectile.load],
  /// then call [launchProjectile]. [firePoints] replace the turret's own (a
  /// Combonly plate fires from the colour weapon it took on).
  @internal
  Projectile comboProjectile(
    Turret t, {
    required String specId,
    Creep? target,
    double? damage,
    double poison = 1,
    List<Vec2>? firePoints,
  }) {
    final spec = data.projectiles[specId]!;
    final points = firePoints ?? t.def.firePoints;
    final local = points.isEmpty ? Vec2.zero : points[t.firePointIndex % points.length];
    t
      ..firePointIndex += 1
      ..firedAtMs = clock.nowMs;
    return addProjectile(
      specId: specId,
      kind: spec.kind,
      position: t.position + rotateVec(local, t.rotation),
      heading: t.rotation,
      damage: damage ?? turretStat(t, StatKind.damage, data.rules),
      targetUid: target?.uid,
      turretUid: t.uid,
      poison: poison,
    );
  }

  /// Sets off blast [specId] at [at] (`Projectile.projectileBlast` /
  /// `projectileCluster`, `BlastNapalm` drops): runs its kind's start, then
  /// emits [BlastStarted] where it ended up. [sound] defaults to the blast's own `sound`
  /// parameter (the cluster spark's "Tazer").
  @internal
  Blast spawnBlast({
    required String specId,
    required Vec2 at,
    required double damage,
    required double poison,
    required int? turretUid,
    double angle = 0,
    int? targetUid,
    String? sound,
    Ordnance? load,
  }) {
    final spec = data.blasts[specId]!;
    final b = Blast(
      uid: _nextUid++,
      specId: specId,
      kind: spec.kind,
      position: at,
      damage: damage,
      poison: poison,
      turretUid: turretUid,
      angle: angle,
      targetUid: targetUid,
      createdAtMs: clock.nowMs,
      load: load,
    );
    _blasts.add(b);
    registry.blastKind(b.kind).start(this, b);
    // After the start, which may move it (the shockwave goes to its target).
    emit(
      BlastStarted(
        stepIndex,
        uid: b.uid,
        blast: specId,
        x: b.position.x,
        y: b.position.y,
        damage: damage,
        sound: sound ?? spec.params.string('sound'),
      ),
    );
    return b;
  }

  /// [creep] reached the centre of black hole [hole] (`attackerDead(true)`).
  /// Under `blackHoleDirtyKills` (the original) it is just removed: no
  /// cash, kill or credit. Otherwise it counts as the hole's turret's kill
  /// with the bounty it had before the hole took it.
  @internal
  void swallowCreep(Creep creep, {required int hole, required int? by, required int bounty}) {
    if (creep.gone) return;
    if (!config.profile.blackHoleDirtyKills) {
      creep
        ..bounty = bounty
        ..blackHoled = false
        ..hp = math.min(creep.hp, 0);
      _kill(creep, by: by);
      return;
    }
    creep.gone = true;
    emit(CreepSwallowed(stepIndex, uid: creep.uid, hole: hole));
  }

  /// Deals [damage] to [creep] (`AttackerEngine.attackerHit`). At 0 HP or
  /// less it dies: the turret [by] (if still standing) is credited, the
  /// bounty is paid and the kill counted (`AttackerManager.attackerKilled`).
  /// A creep in a black hole takes no damage.
  @internal
  void hitCreep(Creep creep, double damage, {int? by}) {
    if (!creep.targetable || creep.blackHoled) return;
    creep.hp -= damage;
    if (creep.hp > 0) return;
    _kill(creep, by: by);
  }

  void _kill(Creep creep, {int? by}) {
    creep.gone = true;
    final turret = by == null ? null : turretByUid(by);
    if (turret != null) turret.kills++;
    if (creep.bounty > 0) _cash += creep.bounty;
    // The demo resets the kills on every kill (`GameManagerIntro.attackerKilled`).
    if (!config.attract) _kills++;
    emit(
      CreepKilled(
        stepIndex,
        uid: creep.uid,
        turret: turret?.uid,
        bounty: creep.bounty,
        cash: cash,
        kills: kills,
        x: creep.position.x,
        y: creep.position.y,
      ),
    );
    if (config.attract) return;
    _unlockByKills();
    if (freeplay) return;
    _objectiveSystem.onKill(this);
  }

  /// Slows [creep] by [amount] (`AttackerEngine.attackerPoison`): subtracts
  /// it ([subtract], sparks) or divides by it (blasts), never below the
  /// slow floor, then re-plans the current leg. A creep in a black hole is
  /// not slowed.
  @internal
  void slowCreep(Creep creep, double amount, {required bool subtract}) {
    if (!creep.targetable || creep.blackHoled) return;
    final slowed = subtract ? creep.speed - amount : creep.speed / amount;
    creep.speed = math.max(slowed, data.rules.slowFloor);
    registry.creepBehaviour(creep.behaviour).onSpeedChanged(this, creep);
  }

  /// `GameManager.weaponStoreUpdate`, run after every kill: turrets whose
  /// kill threshold is reached become available.
  void _unlockByKills() {
    for (final def in data.turrets.values) {
      if (def.unlockKills <= 0 || kills < def.unlockKills || !_available.add(def.id)) continue;
      _unlocked.add(def.id);
      emit(WeaponUnlocked(stepIndex, turret: def.id, kills: kills));
    }
  }
}
