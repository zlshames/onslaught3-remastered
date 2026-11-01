/// Engine constants of the original game that are not plain data
/// declarations: literals inside engine classes (speeds, radii, timings),
/// combo recipe structure from each colour's `comboFire`, sound and art
/// symbol mappings. Transcribed once from the deobfuscated source; every
/// entry cites `File.as:function` (paths under `__Packages/` unless noted).
/// The narrative with formulas and quirks is `docs/legacy/ENGINE_NOTES.md`.
library;

/// Combo recipes in each leader's priority order. `requires` counts helpers
/// besides the leader (≥, unless the colour is in `exact`). `takes` is what
/// `comboTake` is applied to; `takesIfReady` is taken only when one is
/// available. `helperValue`: `link` (a green's link pool is added to the
/// damage) or `poison` (a yellow's poison is used), taken from the
/// `helperColour` helpers (`comboTakeLink(combo_green)`,
/// `comboTakePoison(combo_yellow)`); `linkAddsTo` names the
/// `Combos` fields the link pool is added to before `modifyDamage`.
/// `rawValues` are copied without `modifyDamage`; `bulletFromLeader`: the hit
/// uses the leader's `weapon_damage_effective` (the function sets
/// `weapon_damage`, which the rocket never reads, instead of `bullet_damage`);
/// `holding`: the function sets `holding_capable` (the BFGs too).
const List<Map<String, Object?>> comboRecipes = [
  // Blue leader — turrets/TurretBlue.as:comboFire
  {
    'key': 'big_laser_cluster_landmine',
    'leader': 'Blue',
    'priority': 0,
    'requires': {'red': 2, 'green': 1, 'blue': 1},
    'takes': {'red': 2, 'blue': 1, 'green': 1},
    'projectile': 'LandmineBigClusterLaser',
    'blast': 'BlastLarge',
    'cluster': 'ClusterBlast',
    'clusterLaser': true,
    'sound': 'BlastMedium',
    'source': 'turrets/Turret.as:comboFireBigLaserClusterLandmine',
  },
  {
    'key': 'big_cluster_landmine',
    'leader': 'Blue',
    'priority': 1,
    'requires': {'red': 2, 'blue': 1},
    'takes': {'red': 2, 'blue': 1},
    'projectile': 'LandmineBigCluster',
    'blast': 'BlastLarge',
    'cluster': 'ClusterBlast',
    'sound': 'BlastMedium',
    'source': 'turrets/Turret.as:comboFireBigClusterLandmine',
  },
  {
    'key': 'big_laser_clusterbomb',
    'leader': 'Blue',
    'priority': 2,
    'requires': {'red': 2, 'green': 1},
    'takes': {'red': 2, 'green': 1},
    'helperValue': 'link',
    'helperColour': 'green',
    'projectile': 'ClusterBomb',
    'blast': 'BlastLarge',
    'cluster': 'ClusterBlast',
    'clusterLaser': true,
    'sound': 'BlastMedium',
    'linkAddsTo': ['cluster_laser_damage'],
    'source': 'turrets/Turret.as:comboFireBigLaserClusterBomb',
  },
  {
    'key': 'big_clusterbomb',
    'leader': 'Blue',
    'priority': 3,
    'requires': {'red': 2},
    'takes': {'red': 2},
    'projectile': 'ClusterBomb',
    'blast': 'BlastLarge',
    'cluster': 'ClusterBlast',
    'sound': 'BlastMedium',
    'source': 'turrets/Turret.as:comboFireBigClusterBomb',
  },
  {
    'key': 'sparky_landmine',
    'leader': 'Blue',
    'priority': 4,
    'requires': {'blue': 1, 'yellow': 1},
    'takes': {'blue': 1, 'yellow': 1},
    'takesIfReady': {'red': 1},
    'projectile': 'LandmineSparky',
    'blast': 'BlastSmall',
    'cluster': 'ClusterSpark',
    'sound': 'BlastMedium',
    'source': 'turrets/Turret.as:comboFireSparkyLandmine',
  },
  {
    'key': 'sparky_clusterbomb',
    'leader': 'Blue',
    'priority': 5,
    'requires': {'red': 1, 'yellow': 1},
    'takes': {'red': 1, 'yellow': 1},
    'projectile': 'ClusterBomb',
    'blast': 'BlastSmall',
    'cluster': 'ClusterSpark',
    'sound': 'BlastSmall',
    'source': 'turrets/Turret.as:comboFireSparkyClusterBomb',
  },
  {
    'key': 'laser_clusterbomb',
    'leader': 'Blue',
    'priority': 6,
    'requires': {'red': 1, 'green': 1},
    'takes': {'red': 1, 'green': 1},
    'helperValue': 'link',
    'helperColour': 'green',
    'projectile': 'ClusterBomb',
    'blast': 'BlastMedium',
    'cluster': 'ClusterBlast',
    'clusterLaser': true,
    'sound': 'BlastMedium',
    'linkAddsTo': ['cluster_laser_damage'],
    'source': 'turrets/Turret.as:comboFireLaserClusterBomb',
  },
  {
    'key': 'big_landmine',
    'leader': 'Blue',
    'priority': 7,
    'requires': {'red': 1, 'blue': 1},
    'takes': {'red': 1, 'blue': 1},
    'projectile': 'LandmineBig',
    'blast': 'BlastLarge',
    'sound': 'BlastMedium',
    'source': 'turrets/Turret.as:comboFireBigLandmine',
  },
  {
    'key': 'clusterbomb',
    'leader': 'Blue',
    'priority': 8,
    'requires': {'red': 1},
    'takes': {'red': 1},
    'projectile': 'ClusterBomb',
    'blast': 'BlastSmall',
    'cluster': 'ClusterBlast',
    'sound': 'BlastSmall',
    'source': 'turrets/Turret.as:comboFireClusterBomb',
  },
  {
    'key': 'landmine',
    'leader': 'Blue',
    'priority': 9,
    'requires': {'blue': 1},
    'takes': {'blue': 1},
    'projectile': 'Landmine',
    'blast': 'BlastSmall',
    'sound': 'BlastSmall',
    'source': 'turrets/Turret.as:comboFireLandmine',
  },
  // Red leader — turrets/TurretRed.as:comboFire
  {
    'key': 'nuke',
    'leader': 'Red',
    'priority': 0,
    'requires': {'blue': 2},
    'takes': {'blue': 2},
    'projectile': 'RocketNuke',
    'blast': 'BlastHuge',
    'sound': 'BlastLarge',
    'holding': true,
    'source': 'turrets/Turret.as:comboFireNuke',
  },
  {
    'key': 'napalm',
    'leader': 'Red',
    'priority': 1,
    'requires': {'red': 1, 'yellow': 1, 'blue': 1},
    'takes': {'red': 1, 'yellow': 1, 'blue': 1},
    'projectile': 'RocketNapalm',
    'blast': 'BlastNapalm',
    'bulletFromLeader': true,
    'source': 'turrets/Turret.as:comboFireNapalm',
  },
  {
    'key': 'poison_rocket',
    'leader': 'Red',
    'priority': 2,
    'requires': {'blue': 1, 'green': 1},
    'takes': {'blue': 1, 'green': 1},
    'projectile': 'RocketPoison',
    'blast': 'BlastPoison',
    'sound': 'BlastMedium',
    'holding': true,
    'blastPoison': 2,
    'blastDamageRaw': true,
    'source': 'turrets/Turret.as:comboFirePoisonGas',
  },
  {
    'key': 'tazer_rocket',
    'leader': 'Red',
    'priority': 3,
    'requires': {'yellow': 1},
    'takes': {'yellow': 1},
    'helperValue': 'poison',
    'helperColour': 'yellow',
    'projectile': 'RocketTazer',
    'laserType': 'Spark',
    'holding': true,
    'source': 'turrets/Turret.as:comboFireTazerRocket',
  },
  {
    'key': 'laser_rocket',
    'leader': 'Red',
    'priority': 4,
    'requires': {'green': 1},
    'takes': {'green': 1},
    'helperValue': 'link',
    'helperColour': 'green',
    'projectile': 'RocketLaser',
    'laserType': 'LaserBeam',
    'holding': true,
    'linkAddsTo': ['bullet_damage', 'laser_damage'],
    'rawValues': ['laserblast_damage'],
    'source': 'turrets/Turret.as:comboFireLaserRocket',
  },
  // Green leader — turrets/TurretGreen.as:comboFire
  {
    'key': 'rocket_bfg',
    'leader': 'Green',
    'priority': 0,
    'requires': {'red': 2, 'blue': 1},
    'takes': {'red': 1, 'blue': 1},
    'helperValue': 'ownLink',
    'projectile': 'BFG',
    'blast': 'BlastBFG',
    'sound': 'BlastBFG',
    'subRockets': true,
    'holding': true,
    'linkAddsTo': ['bullet_damage', 'blast_damage', 'laser_damage', 'rocket_damage'],
    'source': 'turrets/Turret.as:comboFireRocketBFG',
  },
  {
    'key': 'bfg',
    'leader': 'Green',
    'priority': 1,
    'requires': {'red': 1, 'blue': 1},
    'takes': {'red': 1, 'blue': 1},
    'helperValue': 'ownLink',
    'projectile': 'BFG',
    'blast': 'BlastBFG',
    'sound': 'BlastBFG',
    'holding': true,
    'linkAddsTo': ['bullet_damage', 'blast_damage', 'laser_damage'],
    'source': 'turrets/Turret.as:comboFireBFG',
  },
  // Yellow leader — turrets/TurretYellow.as:comboFire
  {
    'key': 'blackhole',
    'leader': 'Yellow',
    'priority': 0,
    'requires': {'yellow': 2, 'green': 1},
    'exact': ['green'],
    'takes': {'yellow': 2, 'green': 1},
    'projectile': 'BlackHole',
    'sound': 'BlackHole',
    'source': 'turrets/Turret.as:comboFireBlackHole',
  },
  {
    'key': 'shockwave',
    'leader': 'Yellow',
    'priority': 1,
    'requires': {'yellow': 1, 'blue': 1, 'green': 1},
    'exact': ['blue', 'green'],
    'takes': {'yellow': 1, 'blue': 1, 'green': 1},
    'helperValue': 'link',
    'helperColour': 'green',
    'projectile': 'Spark',
    'blast': 'BlastShockwave',
    'linkAddsTo': ['bullet_damage', 'blast_damage'],
    'source': 'turrets/Turret.as:comboFireShockwave',
  },
  {
    'key': 'tazer_bfg',
    'leader': 'Yellow',
    'priority': 2,
    'requires': {'red': 1, 'blue': 1},
    'exact': ['blue'],
    'takes': {'red': 1, 'blue': 1},
    'helperValue': 'ownPoison',
    'projectile': 'BFGTazer',
    'blast': 'BlastBFG',
    'sound': 'BlastBFG',
    'laserType': 'Spark',
    'holding': true,
    'source': 'turrets/Turret.as:comboFireTazerBFG',
  },
];

/// `Combos` keys that exist in `Combos.as` but no `comboFire` calls.
const Map<String, String> unreachableCombos = {
  'big_sparky_clusterbomb': 'turrets/Turret.as:comboFireBigSparkyClusterBomb is never called',
};

/// The Combonly plate's scan (`TurretCombonly.as:comboScan`): rules in source order; for each
/// colour the **last** rule whose counts are met wins. `needs` counts every turret the plate
/// consumes, including one of the chosen colour (`combo_needs`); `recipe` is the `Combos` key of
/// the `comboFire*` its `comboFire` switch calls for `name`.
const List<Map<String, Object?>> combonlyScan = [
  {
    'colour': 'Blue',
    'name': 'Landmine',
    'recipe': 'landmine',
    'needs': {'blue': 2},
  },
  {
    'colour': 'Blue',
    'name': 'ClusterBomb',
    'recipe': 'clusterbomb',
    'needs': {'blue': 1, 'red': 1},
  },
  {
    'colour': 'Red',
    'name': 'LaserRocket',
    'recipe': 'laser_rocket',
    'needs': {'green': 1, 'red': 1},
  },
  {
    'colour': 'Red',
    'name': 'TazerRocket',
    'recipe': 'tazer_rocket',
    'needs': {'yellow': 1, 'red': 1},
  },
  {
    'colour': 'Blue',
    'name': 'BigLandmine',
    'recipe': 'big_landmine',
    'needs': {'blue': 2, 'red': 1},
  },
  {
    'colour': 'Blue',
    'name': 'SparkyLandmine',
    'recipe': 'sparky_landmine',
    'needs': {'blue': 2, 'yellow': 1},
  },
  {
    'colour': 'Blue',
    'name': 'BigClusterBomb',
    'recipe': 'big_clusterbomb',
    'needs': {'red': 2, 'blue': 1},
  },
  {
    'colour': 'Red',
    'name': 'Nuke',
    'recipe': 'nuke',
    'needs': {'blue': 2, 'red': 1},
  },
  {
    'colour': 'Yellow',
    'name': 'BlackHole',
    'recipe': 'blackhole',
    'needs': {'yellow': 3, 'green': 1},
  },
  {
    'colour': 'Blue',
    'name': 'LaserClusterBomb',
    'recipe': 'laser_clusterbomb',
    'needs': {'red': 1, 'green': 1, 'blue': 1},
  },
  {
    'colour': 'Yellow',
    'name': 'TazerBFG',
    'recipe': 'tazer_bfg',
    'needs': {'red': 1, 'yellow': 1, 'blue': 1},
  },
  {
    'colour': 'Green',
    'name': 'BFG',
    'recipe': 'bfg',
    'needs': {'red': 1, 'green': 1, 'blue': 1},
  },
  {
    'colour': 'Red',
    'name': 'PoisonGas',
    'recipe': 'poison_rocket',
    'needs': {'red': 1, 'green': 1, 'blue': 1},
  },
  {
    'colour': 'Blue',
    'name': 'SparkyClusterBomb',
    'recipe': 'sparky_clusterbomb',
    'needs': {'red': 1, 'yellow': 1, 'blue': 1},
  },
  {
    'colour': 'Yellow',
    'name': 'Shockwave',
    'recipe': 'shockwave',
    'needs': {'yellow': 2, 'green': 1, 'blue': 1},
  },
  {
    'colour': 'Blue',
    'name': 'BigLaserClusterBomb',
    'recipe': 'big_laser_clusterbomb',
    'needs': {'red': 2, 'green': 1, 'blue': 1},
  },
  {
    'colour': 'Green',
    'name': 'RocketBFG',
    'recipe': 'rocket_bfg',
    'needs': {'red': 2, 'green': 1, 'blue': 1},
  },
  {
    'colour': 'Red',
    'name': 'Napalm',
    'recipe': 'napalm',
    'needs': {'red': 2, 'yellow': 1, 'blue': 1},
  },
  {
    'colour': 'Blue',
    'name': 'BigClusterLandmine',
    'recipe': 'big_cluster_landmine',
    'needs': {'red': 2, 'blue': 2},
  },
  {
    'colour': 'Blue',
    'name': 'BigLaserClusterBombLandmine',
    'recipe': 'big_laser_cluster_landmine',
    'needs': {'red': 2, 'blue': 2, 'green': 1},
  },
];

/// Turrets the sandbox modes add to the rack (`GameManager.as:resetGame`: `game_type ==
/// "sandbox"` opens the modifiers and the Targeter; when "sandbox2" is unlocked it also opens
/// the super turrets and starts with `starting_cash_levels.sandbox2`).
const Map<String, List<String>> modeRacks = {
  'sandbox': [
    'TurretRangeUp',
    'TurretDamageUp',
    'TurretRateUpExchange',
    'TurretRangeUpExchange',
    'TurretRateUp',
    'TurretDamageUpBig',
    'TurretDamageUpBigExchange',
    'TurretTargeter',
  ],
  'sandbox2': [
    'TurretRangeUp',
    'TurretDamageUp',
    'TurretRateUpExchange',
    'TurretRangeUpExchange',
    'TurretRateUp',
    'TurretDamageUpBig',
    'TurretDamageUpBigExchange',
    'TurretTargeter',
    'TurretSniper',
    'TurretFusion',
    'TurretRailgun',
    'TurretCombonly',
  ],
};

/// `Projectile.as:class vars` — fallbacks for fields a combo does not set.
const Map<String, Object?> projectileDefaults = {
  'bullet_poison': 1,
  'blast_damage': 1000000,
  'blast_poison': 1,
  'cluster_damage': 1000000,
  'cluster_qty': 5,
  'cluster_holding': true,
  'cluster_poison': 20,
  'laser_range': 200,
  'laser_rate': 120,
  'rocket_damage': 1000000,
  'rocket_rate': 120,
  'laser_type': 'LaserBeam',
  'rocket_type': 'Rocket9',
  'napalm_quantity': 16,
  'napalm_timing': 75,
  'napalm_jit': 30,
  'helper_poison_fallback': 20,
  'source': 'Projectile.as:class vars; Turret.as:comboTakePoison (20 fallback); ClusterSparkEngine.as:class vars (cluster_poison)',
};

/// Projectile engines by linkage name.
const Map<String, Map<String, Object?>> projectileEngines = {
  'ShellEngine': {
    'speed': 900,
    'impactRadius': 3,
    'homing': 'perfect',
    'tickMs': 32,
    'source': 'ShellEngine.as:class vars, update',
  },
  'RocketEngine': {
    'speed': 250,
    'turnRate': 270,
    'impactRadius': 8,
    'acquireRange': 1000,
    'tickMs': 32,
    'tickJitterMs': 10,
    'smokeMax': 200,
    'source': 'RocketEngine.as:class vars, ctor, update; SmokeManager.as:rocketSmoke; GameStatus.as (rocket_smoke_max)',
  },
  'BFG': {
    'speed': 60,
    'impactRadius': 10,
    'noRotate': true,
    'offscreenLock': true,
    'laserRange': 250,
    'laserRate': 180,
    'subRocketIntervalMs': 500,
    'source': 'Turret.as:comboFireBFG/RocketBFG/TazerBFG; RocketEngine.as:update, rocketFire',
  },
  'BulletSniper': {
    'instant': true,
    'tracerColor': '#777733',
    'tracerAlpha': 75,
    'tracerMs': 32,
    'source': 'BulletSniper.as:onLoad',
  },
  'LaserEngine': {
    'instant': true,
    'fadeMs': 350,
    'startAlpha': 80,
    'blackHoleImmune': true,
    'source': 'LaserEngine.as:ctor, laserFire, class vars',
  },
  'RailLaser': {
    'instant': true,
    'length': 900,
    'halfWidth': 20,
    'hurtDelayMs': 32,
    'visualMs': 125,
    'blackHoleImmune': true,
    'source': 'RailLaser.as:laserFire, railHurt, class vars',
  },
  'SparkEngine': {
    'instant': true,
    'defaultPoison': 1,
    'segmentLength': 11,
    'minSegments': 3,
    'extraSegmentsMax': 5,
    'jitter': 5.5,
    'fadeMs': 400,
    'alpha': 75,
    'blackHoleImmune': true,
    'source': 'SparkEngine.as:class vars, sparkDraw',
  },
  'ClusterBombEngine': {
    'speed': 750,
    'impactRadius': 3,
    'homing': 'perfect',
    'source': 'ClusterBombEngine.as:class vars, update',
  },
  'LandmineEngine': {
    'throwMs': 1000,
    'jitter': 5,
    'checkIntervalMs': 150,
    'triggerBox': 20,
    'source': 'LandmineEngine.as:ctor, update',
  },
  'BlackHole': {
    'scanIntervalMs': 200,
    'gravity': 500,
    'openMs': 200,
    'closeMs': 200,
    'debrisRange': 60,
    'pointRange': 90,
    'source': 'BlackHole.as:ctor, update, onEnterFrame; Turret.as:class vars (combo_hole_range)',
  },
};

/// Which engine each projectile linkage uses (`.legacy/deobfuscated/<Linkage>.as`).
const Map<String, String> projectileLinkages = {
  'Bullet': 'ShellEngine',
  'Bullet2': 'ShellEngine',
  'Bullet3': 'ShellEngine',
  'Bullet4': 'ShellEngine',
  'Bullet5': 'ShellEngine',
  'Bullet6': 'ShellEngine',
  'Bullet7': 'ShellEngine',
  'Bullet8': 'ShellEngine',
  'Bullet9': 'ShellEngine',
  'BulletSniper': 'BulletSniper',
  'Rocket': 'RocketEngine',
  'Rocket2': 'RocketEngine',
  'Rocket3': 'RocketEngine',
  'Rocket4': 'RocketEngine',
  'Rocket5': 'RocketEngine',
  'Rocket6': 'RocketEngine',
  'Rocket7': 'RocketEngine',
  'Rocket8': 'RocketEngine',
  'Rocket9': 'RocketEngine',
  'RocketNuke': 'RocketEngine',
  'RocketPoison': 'RocketEngine',
  'RocketNapalm': 'RocketEngine',
  'RocketLaser': 'RocketEngine',
  'RocketTazer': 'RocketEngine',
  'BFG': 'BFG',
  'BFGTazer': 'BFG',
  'LaserBeam': 'LaserEngine',
  'RailLaser': 'RailLaser',
  'Spark': 'SparkEngine',
  'ClusterBomb': 'ClusterBombEngine',
  'Landmine': 'LandmineEngine',
  'LandmineBig': 'LandmineEngine',
  'LandmineBigCluster': 'LandmineEngine',
  'LandmineBigClusterLaser': 'LandmineEngine',
  'LandmineSparky': 'LandmineEngine',
  'BlackHole': 'BlackHole',
};

/// `BlastEngine.as:blastSetup` table and `blasts/*.as` class vars.
const Map<String, Map<String, Object?>> blasts = {
  'tiny': {
    'growMs': 60,
    'startSize': 10,
    'diameter': 70,
    'fadeMs': 1500,
    'source': 'BlastEngine.as:blastSetup (blast_type "tiny")',
  },
  'BlastSmall': {
    'growMs': 70,
    'startSize': 10,
    'diameter': 100,
    'fadeMs': 1500,
    'source': 'blasts/BlastSmall.as',
  },
  'BlastMedium': {
    'growMs': 80,
    'startSize': 10,
    'diameter': 160,
    'fadeMs': 1750,
    'source': 'blasts/BlastMedium.as',
  },
  'BlastLarge': {
    'growMs': 80,
    'startSize': 10,
    'diameter': 190,
    'fadeMs': 2000,
    'source': 'blasts/BlastLarge.as',
  },
  'BlastHuge': {
    'growMs': 90,
    'startSize': 10,
    'diameter': 250,
    'fadeMs': 2500,
    'source': 'blasts/BlastHuge.as',
  },
  'BlastPoison': {
    'growMs': 80,
    'startSize': 10,
    'diameter': 190,
    'fadeMs': 2500,
    'source': 'blasts/BlastPoison.as',
  },
  'BlastBFG': {
    'growMs': 80,
    'startSize': 10,
    'diameter': 190,
    'fadeMs': 2500,
    'source': 'blasts/BlastBFG.as',
  },
  'BlastShockwave': {
    'growMs': 105,
    'startSize': 10,
    'diameter': 200,
    'fadeMs': 2500,
    'defaultPoison': 100,
    'walkerSpeed': 150,
    'walkerDurationMs': 3000,
    'walkerTickMs': 32,
    'walkerHitBox': 10,
    'decorativeSparks': 15,
    'source': 'blasts/BlastShockwave.as:class vars, preBlast; Shockwave.as',
  },
  'BlastNapalm': {
    'stepPx': 15,
    'dropBlast': 'tiny',
    'dropDamage': 1000000,
    'source': 'blasts/BlastNapalm.as:update',
  },
  'ClusterBlast': {
    'spawnOffset': 30,
    'childProjectile': 'Rocket9',
    'acquireRange': 1000,
    'source': 'ClusterBlastEngine.as:onLoad',
  },
  'ClusterSpark': {
    'childProjectile': 'Spark',
    'spawnOffset': 40,
    'range': 220,
    'poison': 20,
    'sound': 'Tazer',
    'source': 'ClusterSparkEngine.as:class vars, onLoad',
  },
};

/// Turret specials not covered by class `var`s (formulas live in ENGINE_NOTES).
const Map<String, Map<String, Object?>> turretSpecials = {
  'freakout': {
    'firstDelayMs': 60000,
    'warnMs': 3000,
    'jitterPx': 4,
    'buyCostPerSecond': 250,
    'source':
        'Turret.as:freakoutActivate (first schedule now + 60000, guarded by an uninitialised '
        'freak_next), freakoutNow/freakoutNext; turretinfo/TurretInfoBlue.as',
  },
  'targeter': {'joinSnap': 17, 'joinSearchBox': 30, 'source': 'TurretJoiner.as'},
  'sniper': {
    'brassMax': 15,
    'brassFadeAfterMs': 8000,
    'brassFadeMs': 1000,
    'brassMs': 400,
    'brassJitter': 10,
    'brassSpin': 2160,
    'brassPoint': [-2, 3],
    'brassPointTo': [-2, 30],
    'source':
        'TurretSniper.as:brassFire; BarrattBrass.as; weapon sprite 917 BrassPoint / BrassPointTo '
        'placements (FFDec swf2xml, twips / 20)',
  },
  'fusion': {
    'glowUnit': 500000,
    'glowTierSize': 80,
    'glowPulse': 1.1,
    'dischargePoisonMax': 100,
    'soundLow': 'FusionLow',
    'soundMed': 'FusionMed',
    'soundHigh': 'FusionHigh',
    'soundMax': 'FusionMax',
    'source': 'TurretFusion.as:fusionSetGlow, fusionFire',
  },
  'combonly': {
    'cycleMs': 1000,
    'consumeMs': 2000,
    'activateMs': 1500,
    'scanRange': 70,
    'source':
        'TurretCombonly.as:onLoad (1000 ms interval), comboChoose (2 s consume tween), '
        'comboWeaponAttach (1.5 s weapon fade, then comboActivate)',
  },
  'holding': {'sellTargetRange': 720, 'source': 'TurretRed.as:onSell'},
  'combo': {
    'bearToLeader': ['TurretBlue', 'TurretGreen', 'TurretRed'],
    'source':
        'Turret.as:comboTake (turretBearTarget(leader)); TurretBlue/Green/Red.as:update '
        '(target_bear_to branch; TurretYellow.as:update has none)',
  },
  'charge': {
    'maxPerDamageLevel': 10,
    'ratePerRateLevel': 2,
    'poisonBoost': 3,
    'source': 'TurretYellow.as:onUpgrade (charge_max, charge_rate), chargeFire (×3 poison)',
  },
};

/// Play area, road drawing and placement (`GameStatus`, `RoadManager`,
/// `BuildShape`, `MoveShape`).
const Map<String, Object?> world = {
  'playWidth': 720,
  'playHeight': 480,
  'roadOuterWidth': 31,
  'roadOuterColor': '#666666',
  'roadInnerWidth': 28,
  'roadInnerColor': '#B2885B',
  'minePointSpacing': 4,
  'turretSpacing': 36,
  'clearanceRadius': 19,
  'clearanceSamples': 8,
  'moveCost': 500,
  'baseWidth': 126,
  'baseHeight': 82.15,
  'source': 'GameStatus.as:class vars (game_area_x/y); RoadManager.as:roadBuild (line_width 28 + 3, colours 6710886 / 11700315, minepoints floor(segment/4) per segment); BuildShape.as:ctor, buildCheckOtherTurrets (BuildArea 36 px wide: spacing 36, samples at 36/2 + 1 = 19 px, 8 of them), buildCheck (samples hit-test RoadManager, which holds the road and the PlayerBase); MoveShape.as:ctor (500); PlayerBase sprite 254 bounds 126 x 82.15 px from its top-left registration point (FFDec swf2xml)',
  // Faint decorations on the ground, under the road: main timeline frame 37
  // "GameStart" (the same on frames 42 and 47), depths 3 and 5, read with swf2xml.
  // Twips / 20; every matrix is a uniform scale and a rotation.
  'groundArt': [
    {'art': 'ground.decor-rings', 'x': 491.5, 'y': 174.35, 'scale': 1.2120361},
    {'art': 'ground.decor-lines', 'x': 149.65, 'y': 304.85, 'scale': 1.4718323},
  ],
};

/// The map editor (`GameManagerMapping`, `KeyboardManagerMapping`), with the
/// Mapping frame's placements read with FFDec swf2xml. Areas are `[x, y,
/// width, height]` in world px: the 700 × 450 area sprite 1138 as placed
/// (scale and centre) on the frame. `baseEntries` are the base sprite 1167's
/// `BP1`..`BP31` markers and `baseAnchor` its `BasePoint`, in px from the
/// base's top-left registration point.
const Map<String, Object?> mapEditor = {
  'gridSize': 20,
  'startArea': [0, 0, 720, 465],
  'baseArea': [0, 0, 720, 445],
  'waypointArea': [18, 18, 684, 444],
  'baseAnchor': [50, 47],
  'baseEntries': [
    [8.5, 20.5],
    [14.95, 17],
    [24.9, 17],
    [34.85, 17],
    [44.8, 17],
    [54.75, 17],
    [64.7, 17],
    [74.65, 17],
    [84.6, 17],
    [91.05, 20.5],
    [95, 25.55],
    [95, 34.1],
    [95, 42.65],
    [95, 51.2],
    [95, 59.75],
    [95, 68.3],
    [91.5, 73.35],
    [85, 77],
    [75, 77],
    [65, 77],
    [55, 77],
    [45, 77],
    [35, 77],
    [25, 77],
    [15, 77],
    [8.5, 73.5],
    [5, 67],
    [5, 57],
    [5, 47],
    [5, 37],
    [5, 27],
  ],
  'nudge': 1,
  'nudgeFast': 10,
  'messages': {
    'saved': "Map '{name}' saved!",
    'imported': "Map '{name}' saved in your map library.",
    'noStart': 'There is no start point on the map',
    'noBase': 'There is no base on the map',
    'unsaved': 'This map has been changed but not saved.',
    'noSuchMap': "No such map '{name}'",
  },
  'source':
      'GameManagerMapping.as: grid_size, gridAlign (nearest corner), waypointNew (inside '
      'StartArea, no duplicate position, appended), waypointMake onMouseUp (released outside '
      'PlayArea deletes), waypointPathUpdate (start outside StartArea or BasePoint outside '
      'BaseArea resets the marker; road ends at waypointClosestBasePoint of the last waypoint, '
      'or of the start), waypointInsertBetween (midpoint handles), waypointNudge (1 px, shift '
      '10 px, clamped to 720 x 480), mapSave (start in StartArea, BasePoint in BaseArea), '
      'messageNew texts; mapping/MappingSave.as:update; KeyboardManagerMapping.as; Mapping '
      'frame placements PlayArea/StartArea/BaseArea (sprite 1138, shape 28 scaled 58.33 x 37.5) '
      'and WaypointBase (sprite 1167: BP1..BP31, BasePoint) via FFDec swf2xml',
};

/// Initial `Weapon._rotation` in degrees, from each turret's `Weapon`
/// placement matrix (FFDec swf2xml); the weapon keeps it until it first
/// turns toward a target.
const Map<String, num> weaponRotations = {
  'TurretBlue': -90,
  'TurretGreen': -90,
  'TurretRed': -90,
  'TurretYellow': 0,
  'TurretSniper': -90,
  'TurretFusion': -90,
  'TurretRailgun': -90,
  'TurretTargeter': -90,
};

/// Weapon `FirePoint` markers in weapon-local px (x along the barrel), read
/// from the SWF placements with FFDec swf2xml. Shots leave from
/// `Weapon.FirePoint` (`turrets/Turret.as:turretFire`); every `Weapon` sits
/// at its turret's origin. Red's launcher has four tubes used in turn.
const Map<String, List<List<num>>> firePoints = {
  'TurretBlue': [
    [26, 0],
  ],
  'TurretGreen': [
    [26.4, 0],
  ],
  'TurretRed': [
    [13.3, -9.05],
    [13.3, -3.05],
    [13.3, 2.95],
    [13.3, 9.05],
  ],
  'TurretYellow': [
    [0, 0],
  ],
  'TurretSniper': [
    [34, 0],
  ],
  'TurretFusion': [
    [26, 0],
  ],
  'TurretRailgun': [
    [27.5, 0],
  ],
  'TurretTargeter': [
    [11.5, 0],
  ],
};

/// Rule literals inside engine methods.
const Map<String, Object?> rules = {
  'modifierMultFloor': 0.2,
  'slowFloor': 5,
  'slowRecoverAmount': 2,
  'slowRecoverIntervalMs': 1000,
  'tutorialWaveLimit': 50,
  'winCheckIntervalMs': 1000,
  'source': 'turrets/Turret.as:modifyStat (max(mult, 0.2)); AttackerEngine.as:attackerPoison (max(speed, 5)), attackerReplenish (+2 every 1000 ms); GameManagerTutorial.as:class vars (wave_limit 50); GameManager.as:gameWinCheckSetup (setInterval gameWinCheck, 1000)',
};

/// Target modes in cycle order and directional cones (`OnslaughtObject.as`).
const Map<String, Object?> targeting = {
  'modes': ['near', 'far', 'weak', 'strong', 'slow', 'fast', 'old', 'young'],
  'modeNames': [
    'Nearest',
    'Furthest',
    'Weakest',
    'Strongest',
    'Slowest',
    'Fastest',
    'Oldest',
    'Youngest',
  ],
  'cones': {'off': null, 'wide': 50, 'medium': 30, 'narrow': 15},
  'mustFaceToleranceDeg': 1,
  'source': 'OnslaughtObject.as:ctor, targetAcquire; TurretRangeAngled.as:draw; turrets/Turret.as:turretBearTowards',
};

/// Creep movement (`AttackerEngine.as`, `WaveManager.as`).
const Map<String, Object?> creeps = {
  'repoint': [false, true, false, true, true, true, false, true, true],
  'waypointJitter': 19,
  'fadeInMs': 225,
  'scaleBumpPercent': 6,
  'source': 'WaveManager.as:ctor (attacker_point); AttackerEngine.as:ctor, onLoad, updateMove',
};

/// Settings bounds (`docs/ONSLAUGHT2_GAME_REFERENCE.md` §3: PrefWaveSpace
/// 5–40 s; the slider bounds are Flash component parameters not present in
/// the script export, so this is unverified against the SWF).
const Map<String, Object?> settings = {
  'waveSpacingMinS': 5,
  'waveSpacingMaxS': 40,
  'timeScaleMinPercent': 50,
  'timeScaleMaxPercent': 200,
  'rocketSmoke': true,
  'rocketSmokeMax': 200,
  'rocketSmokeMaxMin': 1,
  'rocketSmokeMaxMax': 500,
  'source':
      'GameManager.as:settingsInit (defaults); bounds from the reference doc (unverified); '
      'rocket smoke defaults GameStatus.as (rocket_smoke, rocket_smoke_max), '
      'PrefSmokeMax stepper 1-500 DefineSprite_420_PrefData NumericStepper_22 on(construct)',
};

/// Mixing (`SoundPlayer.as:play`): pan = (1.7·max(1,x)/720 − 0.85)·100
/// (`GameStatus.sound_pan_max`, the `PrefSoundPan` default).
const Map<String, Object?> soundMix = {
  'volume': 80,
  'panSpread': 1.7,
  'source': 'SoundPlayer.as:play; GameStatus.as (sound_volume, sound_pan_max)',
};

/// Sound events → exported MP3 files (`.legacy/dissassembled/sounds/`).
const Map<String, List<String>> soundEvents = {
  'Cannon': ['976_ONS2_cannon_2shrt.aif.mp3', '975_ONS2_cannon_3.aif.mp3'],
  'Laser': ['970_ONS2_laser_09_var.aif.mp3'],
  'Rocket': [
    '961_ONS2_rocket_09.aif.mp3',
    '962_ONS2_rocket_05.aif.mp3',
    '963_ONS2_rocket_03.aif.mp3',
  ],
  'Tazer': ['959_ONS2_taser_30.aif.mp3'],
  'Sniper': ['956_sniper_03.aif.mp3'],
  'FusionLow': ['980_Fusion_Low_01.aif.mp3'],
  'FusionMed': ['978_Fusion_Med_01.aif.mp3'],
  'FusionHigh': ['981_Fusion_Hi_01.aif.mp3'],
  'FusionMax': ['979_Fusion_Max_01.aif.mp3'],
  'BlastSmall': ['988_BlastSmall_01.aif.mp3'],
  'BlastMedium': ['989_BlastMed_01.aif.mp3'],
  'BlastLarge': ['987_BlowUp_02.aif.mp3'],
  'BlastBFG': ['992_BFG_01.aif.mp3'],
  'BlackHole': ['990_black_hole_01.aif.mp3'],
  'Combo': ['985_combo_16.aif.mp3'],
  'FreakoutWarn': ['982_FreakWarning_01.aif.mp3'],
  'FreakoutStart': ['983_freakout_up_20.aif.mp3'],
  'FreakoutEnd': ['984_freakout_dn_20_shrt.aif.mp3'],
  'NextWave': ['968_ONS2_nextWave_02.aif.mp3'],
  'Build': ['958_ONS2_turretmade_inv_4.aif.mp3'],
  'Sell': ['951_weapon_sale_01.aif.mp3'],
  'Weapon': ['969_ONS2_newWeapon_1.aif.mp3'],
  'UpgradeDamage': ['974_ONS2_chime_04.aif.mp3'],
  'UpgradeRange': ['974_ONS2_chime_04.aif.mp3'],
  'UpgradeRate': ['974_ONS2_chime_04.aif.mp3'],
  'UpgradeNo': ['966_ONS2_raspberry_chirp_short.aif.mp3'],
  'ClickBuild': ['986_cartfall_14.aif.mp3'],
  'TurretSelect': ['986_cartfall_14.aif.mp3'],
  'ClickButton': ['973_ONS2_click_01.aif.mp3'],
  'ClickTab': ['973_ONS2_click_01.aif.mp3'],
  'ClickMin': ['972_ONS2_close_01.aif.mp3'],
  'ClickMax': ['967_ONS2_open_01.aif.mp3'],
  'ClickLeft': ['965_ONS2_ratchet_04.aif.mp3'],
  'ClickRight': ['965_ONS2_ratchet_04.aif.mp3'],
  'RackPrev': ['964_ONS2_ratchet_05.aif.mp3'],
  'RackNext': ['964_ONS2_ratchet_05.aif.mp3'],
  'Pause': ['957_pause_03.aif.mp3'],
  'UnPause': ['955_un_pause_03.aif.mp3'],
  'AttackerDead': ['971_ONS2_explode_05shrt_02.aif.mp3'],
  'AttackerHit': [],
  'BaseHit': ['960_ONS2_scream_03.aif.mp3'],
  'BaseDead': ['977_ONS2_basehit_02.aif.mp3'],
  'BaseWarn3': ['952_vox_3_lives_remaining.aif.mp3'],
  'BaseWarn2': ['953_vox_2_lives_remaining.aif.mp3'],
  'BaseWarn1': ['954_vox_1_lives_remaining.aif.mp3'],
  'Message': [],
};

/// Art symbols (`.legacy/dissassembled/symbolClass/symbols.csv` id → class)
/// used by the classic asset pack. Frame counts are the SWF frame counts.
const Map<String, Map<String, Object?>> artSymbols = {
  'TurretBlue': {'id': 828},
  'TurretGreen': {'id': 866},
  'TurretRed': {'id': 910},
  'TurretYellow': {'id': 923},
  'TurretSniper': {'id': 918},
  'TurretFusion': {'id': 852},
  'TurretRailgun': {'id': 882},
  'TurretTargeter': {'id': 945},
  'TurretCombonly': {'id': 932},
  'TurretRangeUp': {'id': 890},
  'TurretRangeUpExchange': {'id': 891},
  'TurretDamageUp': {'id': 837},
  'TurretDamageUpBig': {'id': 839},
  'TurretDamageUpBigExchange': {'id': 842},
  'TurretRateUp': {'id': 898},
  'TurretRateUpExchange': {'id': 899},
  'Cannon': {'id': 827, 'frames': 20},
  'Laser': {'id': 861, 'frames': 16},
  'MissileLauncher': {'id': 909, 'frames': 18},
  'SparkGun': {'id': 922, 'frames': 11},
  'Railgun': {'id': 881, 'frames': 18},
  'CannonLegs': {'id': 821},
  'ElectricLegs': {'id': 845},
  'Attacker0': {'id': 710, 'frames': 9},
  'Attacker1': {'id': 705, 'frames': 9},
  'Attacker2': {'id': 700, 'frames': 9},
  'Attacker3': {'id': 695, 'frames': 9},
  'Attacker4': {'id': 690, 'frames': 9},
  'Attacker5': {'id': 685, 'frames': 9},
  'Attacker6': {'id': 680, 'frames': 9},
  'Attacker7': {'id': 675, 'frames': 9},
  'Attacker8': {'id': 670, 'frames': 1},
  'Bullet': {'id': 770},
  'Bullet2': {'id': 771},
  'Bullet3': {'id': 773},
  'Bullet4': {'id': 775},
  'Bullet5': {'id': 777},
  'Bullet6': {'id': 778},
  'Bullet7': {'id': 780},
  'Bullet8': {'id': 782},
  'Bullet9': {'id': 784},
  'Rocket': {'id': 728},
  'Rocket2': {'id': 730},
  'Rocket3': {'id': 732},
  'Rocket4': {'id': 734},
  'Rocket5': {'id': 736},
  'Rocket6': {'id': 738},
  'Rocket7': {'id': 740},
  'Rocket8': {'id': 726},
  'Rocket9': {'id': 724},
  'RocketNuke': {'id': 718},
  'RocketPoison': {'id': 716},
  'RocketNapalm': {'id': 720},
  'RocketLaser': {'id': 722},
  'RocketTazer': {'id': 714},
  'BFG': {'id': 815, 'frames': 5},
  'BFGTazer': {'id': 817, 'frames': 5},
  'ClusterBomb': {'id': 768},
  'Landmine': {'id': 748, 'frames': 19},
  'LandmineBig': {'id': 752, 'frames': 19},
  'LandmineBigCluster': {'id': 754, 'frames': 19},
  'LandmineBigClusterLaser': {'id': 758, 'frames': 19},
  'LandmineSparky': {'id': 762, 'frames': 19},
  'BlackHole': {'id': 802},
  'BlackHoleDebris': {'id': 804},
  'BlastSmall': {'id': 799},
  'BlastMedium': {'id': 793},
  'BlastNapalm': {'id': 794},
  'BlastLarge': {'id': 791},
  'BlastHuge': {'id': 789},
  'BlastPoison': {'id': 796},
  'BlastShockwave': {'id': 798},
  'BlastBFG': {'id': 787},
  'RocketTrail': {'id': 266, 'frames': 31},
  'BarrattBrass': {'id': 239},
  'SpecialFire': {'id': 214, 'frames': 14},
  'SpecialTake': {'id': 217, 'frames': 14},
  'TurretFreakWarning': {'id': 225, 'frames': 20},
  'CashEarned': {'id': 71, 'frames': 19},
  'PlayerBase': {'id': 254},
  'Waypoint': {'id': 243, 'frames': 5},
  'TurretRange': {'id': 197},
  'TurretRangeEffective': {'id': 229},
  'BuildArea': {'id': 199},
  'FusionGlow': {'id': 231},
  'FusionGlowBlue': {'id': 233},
  'FusionGlowRed': {'id': 235},
  'FusionGlowWhite': {'id': 237},
  'Ground': {
    'image': '1021.jpg',
    'width': 611,
    'height': 475,
    'note': 'stretched to the 720×480 play area; main timeline frame 37, sprite 1095 → shape 1022',
  },
  'source': {
    'note': '.legacy/dissassembled/symbolClass/symbols.csv; frame counts from .legacy/dissassembled/sprites/',
  },
};

/// The attract-mode demo behind the main menu (`GameManagerIntro.as:resetGame`; road and
/// turrets are the main-timeline frame 35 "InstructionsStart" placements, read with FFDec
/// swf2xml: `Waypoint1`…`Waypoint12` (sprite 243) and the turret instances Blue1–4 (828),
/// Green1–5 (866), Red1–5 (910), Yellow1–5 (923), twips / 20, in depth order). The road uses
/// the whole 720 × 535 stage. `RoadManager.roadBuild()` with no map reads the `_root`
/// waypoints. The turrets are plain level-1 turrets. Creeps: one per wave
/// (`wave_size = 1`, so 10× the HP of a normal-size creep, `attacker_size_change = false`, so
/// no size bump), base energy 1050 grown by the difficulty's schedule
/// (`GameStatus.game_diff`, "easy" until a game is chosen; `attacker_upgrade_rate = 1` is
/// overridden by the schedule's wave-1 entry), the first 3 creep types, a wave every 6 s
/// (`AttackerManager.wave_spacing = 6000`, no wave follow). Lives are never lost
/// (`GameManager.roadBaseHit` checks `game_demo`) and kills are reset to 0 on every kill
/// (`GameManagerIntro.attackerKilled`), so nothing unlocks.
const Map<String, Object?> attractDemo = {
  'difficulty': 'easy',
  'waveSize': 1,
  'waveSpacingMs': 6000,
  'baseHp': 1050,
  'creepTypes': 3,
  'sizeChange': false,
  'road': [
    [0, 514.65],
    [610.5, 514.75],
    [610.5, 435.3],
    [700, 435.3],
    [700, 20.55],
    [110.3, 20.55],
    [110.3, 435.15],
    [610.5, 435.3],
    [610.5, 99.95],
    [110.35, 100],
    [20.6, 100],
    [20.6, 535.35],
  ],
  'turrets': [
    ['TurretBlue', 536.3, 476.45],
    ['TurretBlue', 419.3, 57.2],
    ['TurretGreen', 65.45, 57.4],
    ['TurretGreen', 537.25, 57.4],
    ['TurretRed', 65.45, 229.9],
    ['TurretRed', 655.1, 474.35],
    ['TurretRed', 301.35, 55.1],
    ['TurretGreen', 65.45, 397.65],
    ['TurretGreen', 655.25, 310.1],
    ['TurretBlue', 655.25, 223.45],
    ['TurretRed', 655.25, 137.2],
    ['TurretBlue', 65.45, 148.3],
    ['TurretYellow', 655.25, 392.2],
    ['TurretYellow', 65.45, 311.5],
    ['TurretYellow', 183.4, 55.1],
    ['TurretYellow', 655.25, 55.1],
    ['TurretGreen', 417.5, 476.65],
    ['TurretYellow', 298.7, 474.35],
    ['TurretRed', 179.9, 474.35],
  ],
  'source':
      'GameManagerIntro.as:resetGame, attackerKilled; GameManager.as:roadBaseHit; '
      'GameStatus.as (game_diff "easy"); main timeline frame 35 placements (FFDec swf2xml)',
  // The menu's own decorations: main timeline frame 35, depths 2, 4, 6 and 8.
  'groundArt': [
    {'art': 'ground.decor-lines', 'x': 546.7, 'y': 46.35},
    {'art': 'ground.decor-rings', 'x': 129.1, 'y': 87.7},
    {'art': 'ground.decor-rings', 'x': 551.65, 'y': 445.8, 'scale': 0.997358, 'rotation': 108.5583},
    {'art': 'ground.decor-lines', 'x': 113.9, 'y': 424.2, 'scale': 0.999514, 'rotation': -98.5158},
  ],
};

/// Messages and labels of the mode, challenge and tutorial flow, verbatim.
const Map<String, Object?> messages = {
  'unlockExtreme': 'Well done, you have managed to defeat 200 waves in a normal game.  You have unlocked the extreme mode.',
  'completeDifficulty': 'Well done, you have managed to defeat 4000 kills in {difficulty} mode!  You can tick that one off.',
  'unlockSandbox':
      'Excellent work!  400 waves in {difficulty} mode has unlocked the sandbox.  Congrats!',
  'unlockSandbox2':
      'Excellent work!  400 waves in {difficulty} mode has unlocked the super sandbox.  w00t!',
  'unlockModding':
      'Excellent work!  4000 kills in all three modes unlocks the modding interface! Scha-weet!',
  'unlockChallenge':
      'Well done, you have completed the tutorial mode.  You have unlocked the challenge mode.',
  'waveLimitHit': "Message from Attackers:\nThat's it!  We give up!  We've sent the last of our army!\n\nWhatever you've got in Area 51, you can keep it!",
  'killTargetHit': "Kill Target Hit:\nWell played, you've reached your kill target!",
  'challengeBeaten': 'You beat the challenge! ',
  'challengeBeatenKills': 'You hammered through the kill target! ',
  'challengeBeatenWaves': 'You beat back every wave! ',
  'challengeBeatenTime': 'And all within the time limit too! ',
  'challengeBeatenEnd': 'Consider this challenge complete.',
  'challengeWonTitle': 'Challenge Passed!',
  'challengeWonText': 'Well done, you passed the challenge!',
  'challengeLostTitle': 'Challenge Failed.',
  'challengeLostText': "Oh noes, you didn't beat the challenge :( Why not try again?",
  'tutorialStart': 'This is tutorial mode!  The tutorial window will guide you through everything you need to know to play the game.',
  'tutorialUnlockChallenge': "Once you've played through the tutorial, have a go at the challenges, which you've now unlocked!.",
  'modeEasy': 'Easy Mode',
  'modeMedium': 'Medium Mode',
  'modeHard': 'Hard Mode',
  'modeExtreme': 'Extreme Mode',
  'modeSandbox': 'Sandbox Mode',
  'modeTutorial': 'Quick Tutorial',
  'modeMapping': 'Map Tools',
  'modeChallenge': 'Challenge Games',
  'modeModding': 'Mods',
  'lockedSandbox': 'Score 4000 kills on\nmedium to unlock',
  'lockedSandbox2': 'Score 4000 kills on hard\nto unlock the super sandbox!',
  'lockedExtreme': 'Make 2000 kills on any\ndifficulty to unlock',
  'lockedChallenge': 'Play the tutorial to\nunlock the challenges',
  'lockedModding': 'Complete easy, medium and hard\nmodes to enable modding',
  'customChallenge': 'Custom challenge',
  'source':
      'GameManager.as:modeUpdate, waveLimitHit, killTargetHit, gameWin; '
      'GameManagerTutorial.as:onLoad, setupFinal; turretinfo/TurretInfoChallengeOver.as:challengeWon, '
      'challengeLost; GameSelectMode.as:onLoad, toolTipSetup; GameSelectChallenge.as:challengeGet',
};
