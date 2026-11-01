# Onslaught 2 — engine behaviour notes

How the original engine behaves: formulas, timings, combo recipes, quirks, sound and art
mappings, each with a `File.as:function` citation into `.legacy/deobfuscated/`. Written once on
2026-10-18 by reading the deobfuscated source (agent-assisted). Spot-verified against the source:
class defaults beat `ModDefaults.as` (`mods/ModManager.as:modObject` applies deltas only), Blue
damage step 8 = 18 400 (`turrets/TurretBlue.as` ctor), the Yellow charge formulas
(`turrets/TurretYellow.as:onUpgrade`), Red holding thresholds (`turrets/TurretRed.as`), every
sound file name. Re-checked on 2026-10-20 against the 2350-gaby SWF that replaced 2221-nyehi in
`.legacy/` (the values are the same; §8's symbol ids are the new SWF's). Values used by the data live in [`legacy_values.json`](legacy_values.json)
(tables: [`LEGACY_VALUES.md`](LEGACY_VALUES.md)); this file is the narrative. Items marked
"probably" / "verify" are unconfirmed and need a decision before the phase that implements them.

Source root: `.legacy/deobfuscated/` (paths below are relative to `__Packages/` unless they start
with `.legacy/`). Citation format: `File.as:function` (or `:class vars`
for prototype defaults). "ctor" = constructor. Numbers already parsed elsewhere (ModDefaults,
Combos numeric data, maps, presets, type_names) are referenced, not re-extracted, except where
the class code disagrees with them.

Global timing facts used throughout:

| Fact | Value | Citation |
|---|---|---|
| SWF version / frame rate / stage | SWF 8, 31 fps, 720×535 (play area 720×480) | SWF header (FFDec swf2xml); `GameStatus.as:class vars` (`game_area_x/y`, `game_screen_x/y`) |
| Game clock | advances once per frame by real Δt × `game_speed/100`, frozen while paused / game over; a separate "eternal" clock always advances | `GameClock.as:update` |
| VisualEffect tweens | linear, 32 ms interval; default clock = **eternal (real time)**; `pausable:true` or `use_eternal_clock:false` → game clock | `VisualEffect.as:effectSetup` |
| Default object tick | `frame_space = 32` ms | `OnslaughtObject.as:class vars` (OnslaughtObject) |
| Turret tick | 70 ms (Fusion 64 ms; Combonly 1000 ms while choosing) | `turrets/Turret.as:class vars`, `turrets/TurretFusion.as:class vars`, `turrets/TurretCombonly.as:onLoad` |
| Rocket tick | 32 + U(0,10) ms (per-rocket random) | `RocketEngine.as:ctor` |
| ClusterBomb, FreakoutEngine, BlackHole debris | `onEnterFrame` (every frame, 31 fps) | `ClusterBombEngine.as:onEnterFrame`, `FreakoutEngine.as:onEnterFrame`, `BlackHole.as:onEnterFrame` |
| Manager ticks | AttackerManager 200 ms, WaveManager 200 ms, TurretManager 66 ms, BulletManager prune 1000 ms | respective `class vars` / ctor |

---

## 1. Combo recipes per leader colour

### 1.0 Shared combo mechanics

| Rule | Exact behaviour | Citation |
|---|---|---|
| Combo capable | when `upgradeAsPercent("damage") == 100` (damage track fully bought); sets `combo_fired = combo_next = now` | `turrets/Turret.as:comboActivate` |
| Never combos | `combo_never = true`: all modifiers, Targeter, Sniper, Fusion, Railgun, Combonly (Combonly is its own system, §4.8) | each class `class vars` |
| Neighbourhood | other active, non-`combo_never` turrets with centre distance `<= combo_range` (70 px) at (re)scan; incremental add uses `< 70` | `Turret.as:comboGetInRange`, `comboNotifyNew` |
| Leader may combo | `active`, `combo_capable`, `now − weapon_fired >= weapon_rate_msec` and `now >= combo_next` | `Turret.as:comboCanFire` |
| Helper counted | same `comboCanFire()` test on the helper (so a helper must itself be combo-capable, reloaded and past its own `combo_next`) | `Turret.as:comboCountColours` |
| Leader after firing | `combo_next = now + recharge`; `weapon_fired = now`; plays **"Combo"**; attaches `SpecialFire` clip | `Turret.as:comboFired`, `comboFireBullet` |
| Helper "taken" | `combo_fired = now`, `combo_next = now + recharge − 1`, `combo_assist_count++`, attaches `SpecialTake` clip, `turretBearTarget(leader, true)` (turns toward leader while it has no target). Helper's `weapon_fired` (reload) is **not** touched (except link helpers, which fire a laser) | `Turret.as:comboTake` |
| `combo_rate` | `combo_rate = 7`, `combo_rate_msec = 1000/(7/60)` is computed but **never read** – no extra combo cooldown exists | `Turret.as:modifyUpdate` (only writer); no reader anywhere |
| Pick helpers | `comboPickOne` = `arrayPick(list,1)` → one uniformly random element (returns `[undefined]` on an empty list, which `comboTake` then ignores); `comboPickTwo` = `arrayPick(list,2)` → two distinct random elements (returns the list itself if it has exactly 2) | `OnslaughtObject.as:arrayPick` |
| Link-take | `comboTakeLink(greens)`: pick one green G; value = `G.linkFire(leader,0)` + `G.weapon_damage_effective` (G fires its link-pool laser at the leader); G is taken (`comboTake`) unless `combo_silent`; returns 0 if no green | `Turret.as:comboTakeLink` |
| Poison-take | `comboTakePoison(yellows)`: pick one yellow Y; value = `Y.weapon_poison_effective` (20 if no yellow / undefined); Y taken unless silent | `Turret.as:comboTakePoison` |
| Leader damage scaling | every `*_damage` field is passed through the leader's `modifyDamage()` unless noted "raw" | each `comboFire*` |
| Projectile defaults | anything not set by the combo falls back to `Projectile` defaults: `blast_damage 1 000 000`, `blast_poison 1`, `cluster_damage 1 000 000`, `cluster_qty 5`, `cluster_holding true`, `cluster_rocket "Rocket9"`, `cluster_type "ClusterBlast"`, `laser_range 200`, `laser_rate 120`, `laser_type "LaserBeam"`, `rocket_damage 1 000 000`, `rocket_rate 120`, `rocket_type "Rocket9"`, `napalm 16/75/30` | `Projectile.as:class vars` |
| Spawn origin | leader's `Weapon.FirePoint` (Red: rotates through `FirePoint0..3`), heading = `Weapon._rotation`; landmines override origin to the turret centre | `Turret.as:comboFireBullet`, `.legacy/deobfuscated/DefineSprite_909_MissileLauncher/frame_1` |
| `combo_silent` | Combonly firing: no helpers taken, no link/poison take | `TurretCombonly.as:comboFire` |

Helper requirement counts below are counts **besides the leader**, `≥` unless written `==`.
"Takes" lists what `comboTake` is applied to. All rows play "Combo" at fire time; the "Sound"
column is the impact sound (`sound_blast`, played by `Projectile.projectileBlast` when the blast spawns).

### 1.1 Blue leader — `turrets/TurretBlue.as:comboFire` (priority order, first match fires)

| # | Function (`Turret.as`) | Combos key | Needs {R,G,B,Y} | Projectile linkage | Blast | Cluster | Sound | Takes | Hand-set fields |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `comboFireBigLaserClusterLandmine` | `big_laser_cluster_landmine` | R≥2, G≥1, B≥1 | `LandmineBigClusterLaser` (LandmineEngine) | `BlastLarge` | rockets (`ClusterBlast`, Rocket9) with lasers (`cluster_laser true`, `cluster_laser_damage` = modified data value, **no link pool**) | BlastMedium | 2 red, 1 blue, 1 green (plain take) | `_x,_y` = turret centre, `move_speed 220` (unused), `mine_location` = random minepoint |
| 2 | `comboFireBigClusterLandmine` | `big_cluster_landmine` | R≥2, B≥1 | `LandmineBigCluster` | `BlastLarge` | rockets (no lasers) | BlastMedium | 2 red, 1 blue | as #1, `cluster_laser false` |
| 3 | `comboFireBigLaserClusterBomb` | `big_laser_clusterbomb` | R≥2, G≥1 | `ClusterBomb` | `BlastLarge` | rockets with lasers; `cluster_laser_damage = modifyDamage(linkTake + data)` | BlastMedium | green via `comboTakeLink`, 2 red | — |
| 4 | `comboFireBigClusterBomb` | `big_clusterbomb` | R≥2 | `ClusterBomb` | `BlastLarge` | rockets | BlastMedium | 2 red | — |
| 5 | `comboFireSparkyLandmine` | `sparky_landmine` | B≥1, Y≥1 | `LandmineSparky` | `BlastSmall` | sparks (`ClusterSpark`), `cluster_qty` from data; `cluster_damage` **not set → 1 000 000 raw** | BlastMedium | 1 red **(if any is ready — not required)**, 1 blue, 1 yellow | as #1 |
| 6 | `comboFireSparkyClusterBomb` | `sparky_clusterbomb` | R≥1, Y≥1 | `ClusterBomb` | `BlastSmall` | sparks | BlastSmall | 1 red, 1 yellow | `cluster_type "ClusterSpark"` |
| 7 | `comboFireLaserClusterBomb` | `laser_clusterbomb` | R≥1, G≥1 | `ClusterBomb` | `BlastMedium` | rockets with lasers; `cluster_laser_damage = modifyDamage(linkTake + data)` | BlastMedium | green via `comboTakeLink`, 1 red | — |
| 8 | `comboFireBigLandmine` | `big_landmine` | R≥1, B≥1 | `LandmineBig` | `BlastLarge` | none | BlastMedium | 1 red, 1 blue | as #1 |
| 9 | `comboFireClusterBomb` | `clusterbomb` | R≥1 | `ClusterBomb` | `BlastSmall` | rockets | BlastSmall | 1 red | — |
| 10 | `comboFireLandmine` | `landmine` | B≥1 | `Landmine` | `BlastSmall` | none | BlastSmall | 1 blue | as #1 |
| — | else | — | — | normal `turretFire` (Bullet…Bullet9) | | | | | |

Unreachable: `Turret.as:comboFireBigSparkyClusterBomb` (`big_sparky_clusterbomb`: ClusterBomb,
BlastLarge, sparks, BlastMedium, takes 2 red + 1 yellow) is never called by any `comboFire`.

Landmine minepoints: `comboFindMinepoints` keeps every road minepoint with distance ≤
`upgradeGetMax("range")` (the **maximum** range of the range track, not current range); cached
until the turret moves. Each landmine is pushed to `combo_mines` (never read).

### 1.2 Red leader — `turrets/TurretRed.as:comboFire`

| # | Function | Key | Needs | Projectile | Blast | Cluster | Sound | Takes | Hand-set fields |
|---|---|---|---|---|---|---|---|---|---|
| 1 | `comboFireNuke` | `nuke` | B≥2 | `RocketNuke` (RocketEngine) | `BlastHuge` | none | **BlastLarge** | 2 blue | `move_speed` = data (150), `holding_capable true` |
| 2 | `comboFireNapalm` | `napalm` | R≥1, Y≥1, B≥1 | `RocketNapalm` | `BlastNapalm` (spawner, §3.2) | none | none (no `sound_blast` set → silent impact and silent drops) | 1 yellow, 1 blue, 1 red | `napalm_quantity/timing/jit` from data; `move_speed` not set → 250; `bullet_damage` not set by opts → leader's `weapon_damage_effective` (comboFireBullet default) |
| 3 | `comboFirePoisonGas` | `poison_rocket` | B≥1, G≥1 | `RocketPoison` | `BlastPoison` | none | BlastMedium | 1 green, 1 blue (plain) | `move_speed` 150, `holding_capable true`, `blast_poison = 2`, **`blast_damage` raw (not modified)** |
| 4 | `comboFireTazerRocket` | `tazer_rocket` | Y≥1 | `RocketTazer` | none | none | none | yellow via `comboTakePoison` | `laser_capable true`, `laser_type "Spark"`, `laser_range` data, `laser_rate` default 120/min, `bullet_poison` = helper yellow's `weapon_poison_effective` (20 fallback), `move_speed` 100, `holding_capable true` |
| 5 | `comboFireLaserRocket` | `laser_rocket` | G≥1 | `RocketLaser` | none | none | none | green via `comboTakeLink` | `bullet_damage` and `laser_damage` = `modifyDamage(linkTake + data)`, `laser_rate` default 120, `move_speed` 100, `holding_capable true`, `laserblast*` copied but **never used** |
| — | else | normal `turretFire` (Rocket…Rocket9) | | | | | | | |

### 1.3 Green leader — `turrets/TurretGreen.as:comboFire`

| # | Function | Key | Needs | Projectile | Blast | Sound | Takes | Hand-set fields |
|---|---|---|---|---|---|---|---|---|
| 1 | `comboFireRocketBFG` | `rocket_bfg` | R≥2, B≥1 | `BFG` (RocketEngine) | `BlastBFG` | BlastBFG | **1 red** (not 2), 1 blue | `pool = this.linkFire(this,0)` added to bullet/blast/laser/rocket damage before `modifyDamage`; `move_speed` 60, `target_reacquire true` (unused by engine), `offscreen_remove true`, `offscreen_lock true`, `no_rotate true`, `holding_capable true`, `laser_capable true` (laser_range 250, laser_rate 180 from data), `rocket_capable true` (sub-rocket `Rocket9` every 500 ms), `impact_range 10` |
| 2 | `comboFireBFG` | `bfg` | R≥1, B≥1 | `BFG` | `BlastBFG` | BlastBFG | 1 red, 1 blue | same as #1 without rockets |
| — | else | normal `linkFire` laser | | | | | | |

`linkFire(this,0)` on the leader: if the leader has no link-capable neighbours it fires a 0-damage
laser at itself and returns **0**; otherwise it returns `own weapon_damage_effective + Σ 1.25 ×
(helper pool)` and fires that laser at itself (no sound). (`Turret.as:linkFire`)

### 1.4 Yellow leader — `turrets/TurretYellow.as:comboFire`

| # | Function | Key | Needs | Projectile | Blast | Sound | Takes | Hand-set fields |
|---|---|---|---|---|---|---|---|---|
| 1 | `comboFireBlackHole` | `blackhole` | Y≥2, **G == 1** | `BlackHole` (placed, not flown) | — | "BlackHole" played twice (combo fn + BlackHole ctor) | 2 yellow, 1 green | `hole_location` = random point from `comboFindBlackHolePoints` (minepoints within `combo_hole_range` = 90 px of the leader), `hole_duration` = `blackhole_duration`, `weapon_range` = `blackhole_radius` |
| 2 | `comboFireShockwave` | `shockwave` | Y≥1, **B == 1, G == 1** | `Spark` (instant) | `BlastShockwave` (spawned by the Spark at the target) | none | green via `comboTakeLink`, 1 yellow, 1 blue | `bullet_damage`, `weapon_damage`, `blast_damage` = `modifyDamage(linkTake + data)`; `bullet_poison` = data (100, subtract on target); `blast_poison` = data (75, divide) |
| 3 | `comboFireTazerBFG` | `tazer_bfg` | R≥1, **B == 1** | `BFGTazer` (RocketEngine) | `BlastBFG` | BlastBFG | 1 red, 1 blue | as BFG but **no link pool**, `laser_type "Spark"`, `bullet_poison = int(leader.weapon_poison_effective)`, 20 if ≤ 0 (passed to its sparks) |
| 4 | (no combo) `chargeFire` if `charge_cur > 0`, else `turretFire` | | | | | | | |

---

## 2. Projectile engines

### 2.1 Class registry (linkage → engine)

`Bullet, Bullet2..Bullet9 → ShellEngine`; `BulletSniper → BulletSniper`; `Rocket, Rocket2..9,
RocketLaser, RocketNapalm, RocketNuke, RocketPoison, RocketTazer, BFG, BFGTazer → RocketEngine`;
`LaserBeam → LaserEngine`; `RailLaser → RailLaser`; `Spark → SparkEngine`; `ClusterBomb →
ClusterBombEngine`; `ClusterBlast → ClusterBlastEngine`; `ClusterSpark → ClusterSparkEngine`;
`Landmine, LandmineBig, LandmineBigCluster, LandmineBigClusterLaser, LandmineSparky →
LandmineEngine`; `BlackHole → BlackHole`; `Shockwave → Shockwave`; `Blast* → blasts.Blast*`.
(`.legacy/deobfuscated/<Linkage>.as`, one `Object.registerClass` each.)

### 2.2 Engine constants

| Engine | Constant | Value | Citation |
|---|---|---|---|
| **ShellEngine** (Blue) | speed | 900 px/s | `ShellEngine.as:class vars` |
| | steering | perfect: heading snapped to target every tick | `ShellEngine.as:update` |
| | hit | distance < 3 px (`impact_range`) or distance < this tick's step | `ShellEngine.as:update` |
| | on hit | `attackerHit(bullet_damage, turret)` only (bullet_poison ignored, no blast) | `ShellEngine.as:targetHit` |
| | target lost | removed silently, no retarget | `ShellEngine.as:update` |
| | tick | 32 ms interval | `ShellEngine.as:ctor` |
| **BulletSniper** | hit | instant `attackerHit` at `onLoad` | `BulletSniper.as:onLoad` |
| | tracer | 1 px line, colour 0x777733, alpha 75, from `a·(dx,dy)` to `(a+b)·(dx,dy)` with `a = U(0,0.5)`, `b = U(0,0.5)+0.1`; removed after a 32 ms interval | `BulletSniper.as:onLoad` |
| | brass | calls `turret.brassFire()` (§4.9) | `BulletSniper.as:onLoad` |
| **RocketEngine** (Red, combo rockets, BFG, cluster rockets) | speed | 250 px/s default (combo override `move_speed`: nuke 150, poison 150, laser/tazer rocket 100, BFGs 60; napalm keeps 250) | `RocketEngine.as:class vars`; Combos data |
| | turn | 270 °/s; shortest way; snaps when remaining angle < this tick's turn; `no_rotate` disables turning | `RocketEngine.as:update` |
| | impact | `impact_range` 8 px (BFG/BFGTazer/RocketBFG 10); hit if dist² < step² or dist² < impact² → rocket snaps onto target, then blast → cluster → `attackerHit(bullet_damage)` → remove | `RocketEngine.as:update`, `targetHit` |
| | reacquire | every tick `targetAvailableOrAcquire(current, self, 1000, "near")`: keeps current while alive and within 1000 px, else nearest creep within 1000 px (box + circle, not cached) | `RocketEngine.as:update`; `OnslaughtObject.as:targetAvailableOrAcquire` |
| | holding (orbit) | no target & `holding_capable`: keeps flying at speed while turning at 270 °/s × `holding_dir` (±1, 50/50) ⇒ circle radius = 250 / (270·π/180) = **53.05 px**, passing through the point where holding began (not centred on the turret); `offscreen_remove` forced false; no lifetime | `RocketEngine.as:ctor`, `update` |
| | `holding_initially` | orbit regardless of targets until `targetThis()` is called by the turret | `RocketEngine.as:update`, `targetThis` |
| | no target, not holding | flies straight, sets `offscreen_remove = true` | `RocketEngine.as:update` |
| | offscreen removal | if `offscreen_remove` or `offscreen_lock`: removed when `x < −width`, `x > 720 + width`, `y < −height`, `y > 535 + height` | `RocketEngine.as:update` |
| | on-board laser | if `laser_capable` and dist²(target) ≤ `laser_range²` and `now − laser_fired ≥ 60000/laser_rate`: spawn `laser_type` (LaserBeam or Spark) at rocket with `laser_damage`, `bullet_poison` | `RocketEngine.as:update`, `laserFire`; `Projectile.as:ctor` |
| | sub-rockets | if `rocket_capable` and has a target: every `60000/rocket_rate` (= 500 ms) spawn `rocket_type` (Rocket9) aimed at target with `rocket_damage`, inheriting `holding_capable`; **no range check** (`rocket_range` 300 unused) | `RocketEngine.as:rocketFire` |
| | smoke | one `RocketTrail` per tick while `GameStatus.rocket_smoke`; ring of `rocket_smoke_max` = 100 clips | `RocketEngine.as:update`; `SmokeManager.as:rocketSmoke` |
| | tick | 32 + U(0,10) ms | `RocketEngine.as:ctor` |
| **Blue bullet choice** | `weapon_type = upgrade_bullet[upgrade_damage_level]` after every upgrade; table: L0 `Bullet` (initial), L1 `Bullet`, L2 `Bullet2`, … L9 `Bullet9` (pure art tiers; all ShellEngine) | `TurretBlue.as:ctor`, `onUpgrade` |
| **Red rocket choice** | same rule: L0/L1 `Rocket`, L2 `Rocket2` … L9 `Rocket9` | `TurretRed.as:ctor`, `onUpgrade` |
| **LaserEngine** (`LaserBeam`, Green) | delivery | instant `attackerHit(bullet_damage)` in ctor (poison ignored) | `LaserEngine.as:laserFire`, `targetHit` |
| | visual | line from origin to target, alpha starts 80, fades to 0 over `laser_persist` 350 ms (pausable); Glow(tier glow, size, strength 5) + Blur(4,4) | `LaserEngine.as:ctor`, `laserFire` |
| | colour tiers | `laserGetType(damage)`: 0–<50 green/green w1; 50–120 green/red w1; 120–400 green/blue w1; 400–1500 yellow/green w3; 1500–3900 yellow/red w3; 3900–9300 yellow/blue w3; 9300–19500 red/green w5; 19500–35000 red/red w5; 35000–60000 red/blue w5; 60000–100000 0x660198/green w6; 100k–200k 0x660198/red w6; 200k–400k 0x660198/blue w6; 400k–750k 0xFF007F/green w7; 750k–900k /red w7; 900k–1M /blue w7; 1M–2M 0x42C0FB/green w8; 2M–3M /red w8; 3M–4M /blue w8; 4M–5M 0x0000EE/green w9; 5M–6M /red w9; 6M–7M /blue w9; 7M–8M 0x333333/green w10; >8M white / glow 0xAA0000 size 8, w10 (colour/glow; glow size 5 unless noted) | `LaserEngine.as:laserGetType` |
| | black hole | immune (`black_hole_affect false`) | `LaserEngine.as:class vars` |
| **RailLaser** (Railgun) | geometry | beam from fire point toward target, length scaled to **900 px**; 5 strokes widths 40/30/20/10/3, alphas 20/30/40/50/75 ⇒ half-width 20 px (round caps also extend 20 px past both ends) | `RailLaser.as:laserFire`, `railGetType` |
| | damage | one pass 32 ms after spawn: every creep whose **centre point** hit-tests the drawn beam shape takes full `bullet_damage` once | `RailLaser.as:railHurt` |
| | visual | removed after `laser_persist` 125 ms (pausable timer, no fade) | `RailLaser.as:class vars`, `laserFire` |
| | colour tiers | ≤4M: 4 white + 1 0x33CC33 core; ≤9M: 3 white + 2 green; ≤15M: 2 white + 3 green; ≤25M: 2 white + 3 0xFF3333; >25M: 3 white + 2 0xFF33FF | `RailLaser.as:railGetType` |
| **SparkEngine** (Yellow, Fusion, spark lasers, cluster sparks, shockwave visuals) | delivery | instant in ctor: if `blast` → `projectileBlast()` first; then `attackerPoison(bullet_poison, true)` (subtract) then `attackerHit(bullet_damage)`; with `target_coords` instead of a target: visual (+blast) only | `SparkEngine.as:ctor`, `targetHit` |
| | default poison | `bullet_poison = 1` | `SparkEngine.as:class vars` |
| | segments | `base = max(3, floor(dist/11))`; `n = floor(U(0,6) + base)` (base … base+5); vertices i = 1 … n−1 at fraction i/n, each jittered by `U(0,11) − 5.5` in x and y (last segment to the target is not drawn) | `SparkEngine.as:sparkDraw` |
| | visual | line alpha 75, Glow(glow, size, strength 4) + Blur(3,3); fades over `laser_persist` 400 ms (pausable); tier table `sparkGetType` (50 bands, e.g. 50–<75 0x9999FF/white w6 … ≥130M 0xAAAAAA glow 0x33CC33 size 32 w32) or `spark_visual` override | `SparkEngine.as:sparkDraw`, `sparkGetType` |
| | black hole | immune | `SparkEngine.as:class vars` |
| **ClusterBombEngine** | speed | 750 px/s, perfect homing | `ClusterBombEngine.as:class vars`, `update` |
| | tick | every frame (`onEnterFrame`) | `ClusterBombEngine.as:onEnterFrame` |
| | hit | if dist < 3 px: direct `attackerHit` **only (no explode, not removed – repeats every frame while within 3 px)**; if dist < step: `attackerHit` then explode | `ClusterBombEngine.as:update`, `targetHit` |
| | target lost | explode in place (blast + cluster) | `ClusterBombEngine.as:update`, `clusterExplode` |
| **ClusterBlastEngine** (rocket fan) | fan | `cluster_qty` × `cluster_rocket` (Rocket9); rocket i (0-based) heading `(i+1)/qty·360°`, spawned 30 px out along that heading; `bullet_target false` (auto-acquire nearest ≤1000), `holding_capable = cluster_holding`, `laser_capable = cluster_laser`, `laser_damage = cluster_laser_damage` (laser_range 200, rate 120 defaults) | `ClusterBlastEngine.as:onLoad` |
| **ClusterSparkEngine** | fan | `cluster_qty` Sparks, heading `(i+1)/qty·360°`, 40 px out; target `list[i % len]` where list = all creeps in the ±220 px box (`cluster_range`), no circle check; damage `cluster_damage`; poison `cluster_poison` = 20 (never overridden) subtract; plays "Tazer" once; if no creeps, the sparks have no target and vanish | `ClusterSparkEngine.as:class vars`, `onLoad` |
| **LandmineEngine** | jitter | `mine_location.x/y += floor(U(0,10) − 5)` (integer −5 … +4) | `LandmineEngine.as:ctor` |
| | throw | tween from turret centre to mine location over **1000 ms** (pausable), regardless of distance; `move_speed 220`/`bullet_speed 220` are unused | `LandmineEngine.as:ctor` |
| | arming | `mine_planted` when the tween completes | `LandmineEngine.as:ctor` |
| | check | every 150 ms (`frame_space_plant`) once planted: any creep inside the ±20 px box (`mine_range`) → blast + cluster → remove. **No direct `bullet_damage`**, no lifetime, `offscreen_remove` unused | `LandmineEngine.as:update` |
| **BFG / BFGTazer** | see RocketEngine with `no_rotate`: flies **straight** along the launcher's heading at 60 px/s; only hits a creep that passes within 10 px (or the step); fires lasers (Spark for BFGTazer) at its current nearest target within 250 px at 180/min; removed when off screen (`offscreen_lock`) | `Turret.as:comboFireBFG/TazerBFG/RocketBFG`; `RocketEngine.as:update` |

---

## 3. Blasts

### 3.1 BlastEngine table (`BlastEngine.as:blastSetup`, class vars; `blasts/*.as`)

Lifecycle (`BlastEngine.as:ctor/onLoad/update/blastDamage`): start size `blast_start` = 10 px
(width = height); grow linearly to `size` over `time` ms (game clock); at the end of growth deal
damage once: every creep in the ±size/2 box with centre distance ≤ size/2 gets
`attackerPoison(weapon_poison)` (**divide** mode) then `attackerHit(weapon_damage, turret)` — no
falloff; then fade alpha 100→0 over `decay` ms (game clock) and remove.
`weapon_damage`/`weapon_poison` come from the projectile's `blast_damage`/`blast_poison`
(defaults 1 000 000 / 1). Blasts are ordinary bullets: a black hole can capture them (§3.3).

| Linkage / class | `blast_type` | grow ms | start px | diameter px | damage radius | fade ms | poison mode | Citation |
|---|---|---|---|---|---|---|---|---|
| (napalm drop) `BlastSmall` with `blast_type:"tiny"` | tiny | 60 | 10 | 70 | 35 | 1500 | divide by 1 (no slow) | `BlastEngine.as:blastSetup`; `blasts/BlastNapalm.as:update` |
| `BlastSmall` | small | 70 | 10 | 100 | 50 | 1500 | divide by `blast_poison` (1) | `blasts/BlastSmall.as` |
| `BlastMedium` | medium | 80 | 10 | 160 | 80 | 1750 | divide (1) | `blasts/BlastMedium.as` |
| `BlastLarge` | large | 80 | 10 | 190 | 95 | 2000 | divide (1) | `blasts/BlastLarge.as` |
| `BlastHuge` | huge | 90 | 10 | 250 | 125 | 2500 | divide (1) | `blasts/BlastHuge.as` |
| `BlastPoison` | poison | 80 | 10 | 190 | 95 | 2500 | divide by 2 (poison gas) | `blasts/BlastPoison.as`; `Turret.as:comboFirePoisonGas` |
| `BlastBFG` | bfg | 80 | 10 | 190 | 95 | 2500 | divide (1) | `blasts/BlastBFG.as` |
| `BlastShockwave` | shockwave (not in table → class vars used) | 105 | 10 | 200 | 100 | 2500 | divide by `blast_poison` (75 from combo; class default 100) | `blasts/BlastShockwave.as:class vars` |
| `BlastNapalm` | tiny (only used as the drops' type) | — (never grows; its own sprite stays at 10 px until done) | 10 | — | — | — | — | `blasts/BlastNapalm.as` |

### 3.2 BlastNapalm spawner (`blasts/BlastNapalm.as:update`)

| Param | Value |
|---|---|
| count | `napalm_quantity` 16 (from combo data via `Projectile.projectileBlast`) |
| spacing | `napalm_timing` 75 ms (setInterval, real time; skipped while paused); first drop immediately on load |
| step | 15 px per drop (`napalm_space`) along `blast_angle` = the rocket's `_rotation` at impact |
| jitter | `round(U(0,30) − 15)` px independently in x and y (`napalm_jit` 30) |
| drop | `bulletNew("BlastSmall", {weapon_damage: this.blast_damage, blast_type:"tiny"})` ⇒ tiny blast (60 ms / 70 px / 1500 ms). `this.blast_damage` on the BlastNapalm is the **Projectile default 1 000 000** (the combo's blast damage arrives as `weapon_damage` and is ignored); drop poison = default 1 |
| sound | `sound_blast` undefined ⇒ silent |
| end | after 16 drops `blast_done` → removed |

### 3.3 Black hole (`BlackHole.as`, `OnslaughtObject.as:blackHoled`, `AttackerEngine.as:attackerBlackHoled`)

| Param | Value | Citation |
|---|---|---|
| position | `hole_location` (random minepoint within 90 px of leader) | `BlackHole.as:ctor`; `Turret.as:comboFindBlackHolePoints` |
| radius | `weapon_range` = `blackhole_radius` (120) | `BlackHole.as:class vars`; Combos |
| duration | `hole_duration` (3000 ms), measured on the game clock from construction | `BlackHole.as:update` |
| open / close | scale 0→100 % + alpha 0→100 over 200 ms; close: 100→0 over 200 ms then remove (eternal clock) | `BlackHole.as:ctor`, `update` |
| scan | every 200 ms (setInterval, starts after the open tween) | `BlackHole.as:update` |
| creeps | in ±radius box and centre distance ≤ radius, not already holed → `attackerBlackHoled`: `black_holed = true`, movement & replenish stopped, `cash_bounty = 0`, then tweened to the hole centre and scaled to 25 % over `distance / gravity` s (gravity 500 px/s) on the **eternal clock**; on completion `attackerDead(true)` = dirty kill: no `attackerKilled` (no cash, no kill count, no turret credit) | `BlackHole.as:update`; `AttackerEngine.as:attackerBlackHoled/onBlackHoled/attackerDead`; `OnslaughtObject.as:blackHoled` |
| holed creep | ignores `attackerHit`/`attackerPoison` but **stays in `AttackerManager.attackers` and remains targetable** (turrets waste shots on it until removed) | `AttackerEngine.as:attackerHit`; `OnslaughtObject.as:targetAcquire` (no black_holed check) |
| bullets | every entry of `BulletManager.bullets` inside the ±radius **box** (no circle) with `black_hole_affect == true` → `projectileBlackHoled` (interval and current effect cleared, sucked in the same way, removed without effect). Affected: shells, rockets, BFGs, cluster bombs, landmines, **blasts** (incl. napalm drops). Immune: LaserBeam, RailLaser, Spark, BlackHole, Shockwave | `BlackHole.as:update`; `Projectile.as:projectileBlackHoled`; class vars |
| debris | one `BlackHoleDebris` per frame at a random offset in ±60 px, tweening to the core in 100 ms; `Swirl` rotates +29°/frame | `BlackHole.as:onEnterFrame`; `BlackHoleDebris.as:ctor` |
| `blackhole_eject` | data key exists (false) and is described in the mod editor ("ejected into an alternate universe instead of simply being destroyed?") but **no game code reads it** – no effect | `Combos.as:init`; `mods/ModDefaults.as` (desc only) |

### 3.4 Shockwave walkers (`Shockwave.as`, spawned by `blasts/BlastShockwave.as:preBlast`)

| Param | Value | Citation |
|---|---|---|
| spawn point | the blast is moved to the **target's position** (`target_x/target_y`) before spawning | `BlastShockwave.as:preBlast` |
| walkers | two: A `waypoint_from = target.waypoint_cur − 1`, `move_direction +1` (toward base); B `waypoint_from = target.waypoint_cur`, `move_direction −1` (toward spawn) | `BlastShockwave.as:preBlast` |
| speed | 150 px/s along road waypoints (pausable tweens), `repoint` true | `Shockwave.as:class vars`, `updateMove` |
| duration | 3000 ms (pausable timer) or until `waypoint_cur ≤ 0` / `> waypoint_total` | `Shockwave.as:onLoad`, `update` |
| tick | 32 ms setInterval (skipped while paused) | `Shockwave.as:onLoad`, `shockWaveSpark` |
| hit box | creeps in the ±10 px box (`weapon_range` 10), no circle | `Shockwave.as:shockWaveSpark` |
| decay | `f = 1 − (now − time_start)/3000`; damage `= max(0, f × bullet_damage)` via `attackerHit(d)` (no turret credit); slow `= max(0, f × bullet_poison)` via `attackerPoison(p, true)` (subtract) | `Shockwave.as:shockWaveSpark` |
| values | `bullet_damage` = blast's `weapon_damage` (the combo's modified `blast_damage`), `bullet_poison` = blast's `weapon_poison` (= `blast_poison`, **75**) | `BlastShockwave.as:preBlast` |
| visual | each tick a Spark ZapFrom→ZapTo, colour 0x55FF55, glow white size 4, width 8, alpha `f×100 + 10` | `Shockwave.as:shockWaveSpark` |
| blast sparks | the BlastShockwave also emits 15 decorative sparks (no target), colour 0x9999FF, alpha `(1 − k/15)×100`, random offsets within ±width/4, at random 100–799 ms intervals | `BlastShockwave.as:onBlast/blastSpark` |
| not targetable | walkers are created through BulletManager, not AttackerManager | `BlastShockwave.as:preBlast` |
| construction quirk | `Shockwave` extends `AttackerEngine`, whose ctor calls `update()` with `waypoint_cur = 1`; for walker B this makes `waypoint_cur = 0` → `updateRemove()` → `removeMovieClip()` during construction (before `onLoad`), so the spawn-ward walker never runs. Confirmed by reading the code (not observed in Flash). **Decision (2026-10-18): fixed under `RulesProfile.shockwaveBothWalkers`** (`docs/DEVIATIONS.md`) | `AttackerEngine.as:ctor`; `Shockwave.as:update`; `OnslaughtObject.as:removeMyself` |

---

## 4. Turret specials

### 4.1 Common: stats, rotation, firing

| Rule | Value | Citation |
|---|---|---|
| Effective stat | `max(0, (base + added) × max(mult, 0.2))` for damage, range, rate, poison | `Turret.as:modifyStat`, `modifyUpdate` |
| Reload | `weapon_rate_msec = 1000 / (rate_effective/60)`; can fire when `now − weapon_fired > weapon_rate_msec` (strict) | `Turret.as:modifyUpdate`, `turretCanFire` |
| Rotation | `weapon_rotate` °/s (default 270), shortest way | `Turret.as:turretBearTowards` |
| Must face | when `weapon_must_face`, fire only if `|bearing − rotation| < 1°` or `< this tick's turn step` (then snapped) | `Turret.as:turretBearTowards`; each `turretTryFiring` |
| Cash value / resale | `cash_value` += every upgrade cost; sell refunds `ceil(cash_value × 0.7)` | `Turret.as:upgradeDamage…`; `TurretManager.as:turretSell` |
| Upgrade sounds | "UpgradeDamage" / "UpgradeRange" / "UpgradeRate", failure "UpgradeNo" | `Turret.as:upgradeDamage/Range/Rate` |

Per-type defaults (class code; ModDefaults values are only applied as deltas when a mod is active, see §R):

| Type | rotate °/s | must face | default target mode | lock | modifiable | combo | joinable | directional cone available | freak capable | Citation |
|---|---|---|---|---|---|---|---|---|---|---|
| Blue | 270 | yes | near | on (`target_reacquire false`) | yes | yes | yes | yes | yes | `TurretBlue.as`, `Turret.as` |
| Green | 270 | yes | near | on | yes | yes | yes | yes | no | `TurretGreen.as` |
| Red | 270 | **no** (set in ctor) | near | on | yes | yes | yes | yes | no | `TurretRed.as:ctor` |
| Yellow | 720 | **no** (ctor) | **fast** | **off** | yes | yes | yes | yes | yes | `TurretYellow.as` |
| Targeter | 360 (idle spin 90) | must bear before painting | **fast** | **off** | yes | never | yes (it can join another targeter) | yes | no | `TurretTargeter.as` |
| Sniper | 90 | yes | near | on | **no** | never | yes | yes | no (levels never reach 4) | `TurretSniper.as` |
| Fusion | 90 | yes | near | on | **no** | never | yes | yes | no | `TurretFusion.as` |
| Railgun | 90 | yes | near | on | **no** | never | yes | yes | no | `TurretRailgun.as` |
| Combonly | 270 | must bear to fire | near | on | yes | own system | yes | yes | no | `TurretCombonly.as` |
| Modifiers (7) | — | — | — | — | no | never | **no** (`join_possible false`) | **no** | no | `TurretModify.as:ctor` |

`target_type_num` starts at 0 for every turret, so the first cycle from Yellow/Targeter's "fast"
goes to index 1 "far". Lock toggle shows "Lock On"/"Lock Off". (`Turret.as:turretTargetModeCycle`,
`turretTargetModeLockToggle`)

### 4.2 Green link (`Turret.as:linkGetInRange/linkFire`, `TurretGreen.as`)

| Rule | Value |
|---|---|
| Link-capable | Green only (`link_capable true`) |
| Link range | each green lists other link-capable turrets within **its own** `weapon_range_effective` (centre distance ≤); recomputed on upgrade, modifier change, move, and any turret add (asymmetric if ranges differ) |
| Offered | every tick `link_offered = turretCanFire()` (reloaded) |
| Fire | leader (has target, reloaded, no combo) calls `linkFire(target, dmg_eff, true)`: if no link neighbours → normal shot; else every neighbour with `link_offered` is marked used, turns toward the leader, and recursively `linkFire(leader, 0, false)` (fires its own pooled laser **at the leader**, no sound, consumes its reload); pool = `own dmg_eff + Σ 1.25 × helper_pool` (`link_mult` 1.25, compounding per chain depth) |
| Max helpers | no limit (all offered neighbours, recursively) |
| Credit | leader `link_fire_count++`, helpers `link_assist_count++` |

### 4.3 Red holding pattern (`TurretRed.as`)

| Rule | Value |
|---|---|
| Unlock | `onUpgrade`: damage level ≥ 0 and range level ≥ 3 and rate level ≥ 3 → `holding_pattern = true` (permanent) |
| Max held | `holding_max` 4 (counts array entries, including rockets destroyed since) |
| Filling | every tick if `holding_pattern` and reloaded and held < 4: fire a round with `holding_initially = holding_capable = true`, no target (uses reload, plays "Rocket") |
| Dispatch | when the turret has a target: normal shot, then every held rocket gets `targetThis(target)` and the list is cleared |
| Normal rockets | when `holding_pattern` is on, all its rockets get `holding_capable = true` (orbit if target lost) |
| Orbit radius | 53.05 px (from 250 px/s and 270 °/s), circle through the launch point |
| On sell | held rockets are sent at `targetAcquire(self, 720, "weak")` |

### 4.4 Yellow charge (`TurretYellow.as`)

| Rule | Formula / value |
|---|---|
| `charge_rate` | `10 + 2 × rate_level` per second (`charge_rate_base` 10) |
| `charge_max` | `100 + 10 × damage_level` (`charge_base` 100) |
| Accumulate | every tick `charge += charge_rate × Δt/1000`, capped at `charge_max` |
| Charged shot | used whenever `charge_cur > 0` (any amount); cost `charge_use` 50, floor 0 |
| Poison boost | `c = charge_cur/100`; shot poison = `(weapon_poison + modify_poison_added + 3c) × max(modify_poison_mult,0.2)` (temporarily swapped into `weapon_poison_effective`) |
| Damage boost | `charge_damage = (weapon_damage + added) × max(mult + c, 0.2)` is **computed and shown in the info panel only; the shot still uses `weapon_damage_effective`** |
| `weapon_poison` | on every upgrade: `max(1, 10 × floor(damage_level / 7 × 100) / 100)` → levels 0..7: 1, 1.4, 2.8, 4.2, 5.7, 7.1, 8.5, 10 (`weapon_poison_max` 10); initial 1 |
| Sparks | poison is applied **subtractively** (`attackerPoison(p, true)`) |

### 4.5 Freakout (`Turret.as:freakoutNow/freakoutNext/freakoutActivate`, `FreakoutEngine.as`, `turretinfo/TurretInfoBlue.as`)

| Rule | Value |
|---|---|
| Capable | Blue, Yellow (`freak_capable`) |
| Available | after any upgrade with damage lvl ≥ 4, range lvl ≥ 0, rate lvl ≥ 4 |
| First schedule | intended `freak_next = now + 60000`, but guarded by `freak_next == false` while `freak_next` is `undefined` (never initialised) — under SWF8 semantics `undefined == false` is false, so **no automatic first freakout is scheduled**; and the buy-now cost `floor((undefined − now)/1000) × 250` is NaN, which `CashManager.cashAvailable` (`cash >= NaN`) never accepts, so **no freakout ever happens** (corrected in Phase 2; this row first said they start once bought). Confirmed by reading `turrets/Turret.as:freakoutActivate`, `turretinfo/TurretInfoBlue.as`, `CashManager.as` (not observed in Flash). **Decision (2026-10-18): fixed under `RulesProfile.freakoutAutoStart`** (`docs/DEVIATIONS.md`) |
| Next | `next = now + freak_space/2 + U(0, freak_space/2) − rate_level × freak_rate_mult × 1000` (freak_space 80000, rate_mult 4 ⇒ 40 s + U(0,40 s) − 4 s × rate_level) |
| Warning | attach `TurretFreakWarning`, play "FreakoutWarn"; wait > 3000 ms (`freak_warn_time`, game clock) |
| Active | `modifyGain` damage_mult +3, range_mult +0, rate_mult +4 (×4 damage, ×5 rate while no other mods), "FreakoutStart"; lasts > 5000 ms (`freak_length`); weapon jitters by `floor(U(0,4))` px per frame toward its rest point |
| End | gains removed, weapon re-centred, "FreakoutEnd" |
| Buy now | info-panel button only: cost = `floor((freak_next − now)/1000) × freak_now_cost_sec` (250 $/s remaining). **Key F is "attacker focus", not freakout** (`KeyboardManager.as`, keycode 70 → `attackerFocusTry`) |

### 4.6 Targeter (`TurretTargeter.as`, `TurretJoiner.as`)

| Rule | Value |
|---|---|
| Range / rate | 120 px; "rate" 240/min → paints/triggers every 250 ms; damage 0; `weapon_type` undefined |
| Upgrades | range only: 250→140, 350→170, 500→200, 700→230 |
| Paint target | `targetAvailableOrAcquire(..., "fast")` (fastest creep, bbox+circle), lock off; must finish bearing (360 °/s) before painting; idle spin 90 °/s |
| Beam | 1 px 0xFF4444 alpha 60 + Glow(0xFF4444) from FirePoint to target |
| Trigger | when reloaded: `weapon_fired = now`; for each joined turret: `turretTryFiring(target)` (bypasses the joined turret's own range check; still needs its reload/facing) and `turretBearTarget(target)` |
| `join_max` | 3; joining a 4th drops the oldest (FIFO `shift`) |
| Joinable | any turret with `join_possible != false` → everything except the 7 modifiers |
| Joiner snap | candidates in ±30 px box around the cursor, nearest one; rejected if distance > 17 px; snaps cursor to it if < 17 px; must be inside `PlayArea`; dropping on an already-joined turret unjoins it |
| Join lines | 5 px 0xFF9900 alpha 20, 0.3 s fade |

### 4.7 Fusion (`TurretFusion.as`)

| Rule | Value |
|---|---|
| Stats (class) | damage **1 000 000**, range 300, rate 30/min, rotate 90, tick 64 ms; upgrades damage 5000→3M, 7500→10M, 10000→35M; range 4000→400, 4000→500; rate 5000→60, 8000→90 |
| Feeders | `fusion_capable`: Green, Yellow, within the fusion's `weapon_range_effective` (= base range; Fusion can't be modified) |
| Feeding | each fusion tick, iterate the feeder list (creation order — `arrayPick(list, len)` returns the list unshuffled) and let **the first reloaded feeder** fire `turretFire(fusion, its dmg_eff)` (LaserBeam / Spark at the fusion; plays its sound, consumes its reload, drops Yellow's target via lock-off). At most one feeder per tick; feeders keep shooting creeps on their own ticks |
| Absorb | `store_damage += damage × 1.15`, `store_poison += poison × 1.15` (Spark feeders only carry poison) |
| Discharge gate | `now − weapon_fired > 6000` (`store_time`) **and** normal reload (2000 ms at rate 30) and facing |
| Discharge | `d = min(dmg_eff, store_damage)`; Spark with damage `d + dmg_eff`, poison `min(100, store_poison)` (subtract); `store_damage −= d`, `store_poison −= min(100, store_poison)` (fires even with empty store) |
| Glow tiers | `u = floor(store_damage / 500000)`, `m = u mod 80`, size alternates ×1.1 pulse each tick: `u = 0` (store exactly 0) hidden; `0 < u < 80` white (size m) "FusionLow"; `80 ≤ u < 160` white 80 + blue m "FusionMed"; `160 ≤ u < 240` white + blue 80 + red m "FusionHigh"; `u ≥ 240` all 80 "FusionMax" (sound = `sound_fire` of the next discharge) |

### 4.8 Combonly (`TurretCombonly.as`, `CombonlyPlate.as`)

| Rule | Value |
|---|---|
| Ranges | scanning uses `combo_range` **70 px** (Turret default); firing range `weapon_range` 300; `weapon_rate` 250/min (240 ms) |
| Scan | `comboCountColoursRegardless` (active + combo_capable neighbours, reload ignored). Per colour the **last** matching rule wins, in this order (needs include the plate's chosen colour turret itself): Blue: Landmine{b2} → ClusterBomb{b1 r1} → BigLandmine{b2 r1} → SparkyLandmine{b2 y1} → BigClusterBomb{r2 b1} → LaserClusterBomb{r1 g1 b1} → SparkyClusterBomb{r1 y1 b1} → BigLaserClusterBomb{r2 g1 b1} → BigClusterLandmine{r2 b2} → BigLaserClusterBombLandmine{r2 b2 g1}. Red: LaserRocket{g1 r1} → TazerRocket{y1 r1} → Nuke{b2 r1} → PoisonGas{r1 g1 b1} → Napalm{r2 y1 b1}. Yellow: BlackHole{y3 g1} → TazerBFG{r1 y1 b1} → Shockwave{y2 g1 b1}. Green: BFG{r1 g1 b1} → RocketBFG{r2 g1 b1} |
| Cycle | update every 1000 ms; in "cycle" mode advances one colour option per second, tinting `TheColour` (0.5 s tween, alpha 75): Red 0xFF0000, Green 0x01BA01, Blue 0x0000FF, Yellow 0xFFCC00 |
| Consume | click while a colour shows: re-checks counts; `arrayPick` the needed turrets per colour; each consumed turret becomes inactive, its `cash_value` is **added to the plate's** `cash_value` (no refund now), 2 s blur + fade + slide to the plate, then `turretSold` + removed |
| Become weapon | attaches Cannon/MissileLauncher/Laser/SparkGun (+CannonLegs / ElectricLegs) with 1.5 s fade; then `combo_capable` and normal 70 ms ticking |
| Fire | needs bearing reached + `comboCanFire` (240 ms reload and `combo_next` = recharge only); fires the chosen `comboFire*` with `combo_silent` (no helpers; link/poison takes return 0/20 because its lists hold removed turrets) |
| Plate rings | Ring1 +360° every 4871 + U(0,500) ms, Ring2 −360° every 2917 + U(0,500) ms while active |

### 4.9 Sniper brass (`TurretSniper.as:brassFire`, `BarrattBrass.as`)

Casing spawned at `Weapon.BrassPoint`, tweened in 400 ms to `BrassPointTo` ± U(−10,10) px with
rotation 2160 + U(0,2160)°; ring of `sniper_brass_max` = 15 per turret; each casing starts a
1000 ms fade-out after 8000 ms (real-time interval). Sniper stats (class): dmg 3 000 000, range 300,
rate 30, rotate 90; upgrades dmg 5000→7M, 7500→15M, 10000→55M; range 4000→400, 4000→500; rate
5000→45, 8000→60. Sound "Sniper".

### 4.10 Railgun (`TurretRailgun.as`)

dmg 4 000 000, range 300, rate 30, rotate 90; upgrades dmg 5000→9M, 7500→15M, 10000→25M; range
4000→400, 4000→500; rate 5000→60, 6000→90. Weapon `RailLaser` (§2.2). Fire sound **"Tazer"**.

### 4.11 Modifier aura (`TurretModify.as`)

Radius = the modifier's **base** `weapon_range` (80; one upgrade 1500 → 130), centre distance ≤
radius; applies `modifyGain` of all six terms (`*_added`, `*_mult`) to every turret in range
(targets with `modify_possible false` ignore it). Re-asserted on upgrade/move; removed on sell or
when a target leaves. Stacks additively with other modifiers and freakouts. Class values: RangeUp
range +100; DamageUp dmg mult +0.4; RateUpExchange dmg −0.4, range −0.1, rate +0.6; RangeUpExchange
range +100, rate −0.25; RateUp rate +1.2; DamageUpBig dmg +1; DamageUpBigExchange dmg +1, range
−0.3, rate −0.3. Display names: Ranger, Boom, SpeedEx, RangerEx, Speed, BigBang, BigBangEx.

---

## 5. Targeting (`OnslaughtObject.as`, the real `OnslaughtObject`)

| Item | Value | Citation |
|---|---|---|
| Mode list (cycle order) | `near` "Nearest", `far` "Furthest", `weak` "Weakest", `strong` "Strongest", `slow` "Slowest", `fast` "Fastest", `old` "Oldest", `young` "Youngest"; unknown → near | `ctor`, `targetAcquire` |
| Metric | near/far: distance²; weak/strong: `energy`; slow/fast: `move_speed`; old/young: `age = now − created_at` | `targetAcquire`; `AttackerEngine.as:age` |
| Direction | minimise for weak, near, slow, young (strict `<`, start 1e38); maximise for far, strong, fast, old (strict `>`, start 0 — a candidate with value 0 can never be chosen); ties → first in `AttackerManager.attackers` iteration order | `targetAcquire` |
| Acquisition | 1) square box ±range around the source (turrets cache the box until upgrade/modify/move; projectiles/blasts rebuild every call); 2) optional cone filter; 3) circle `dist² < range²` (strict) | `targetAcquireBySlice`, `targetAcquire` |
| Keep current | `targetAvailableOrAcquire`: keeps the current target if it still exists, is in the box, `dist ≤ range` and passes the cone; otherwise re-acquires | `targetInRange`, `targetAvailableOrAcquire` |
| Cone spreads | off (`TA_MODE_NONE`), wide 50°, medium 30°, narrow 15° (half-angles: drawn wedge = 2 × spread) ; default spread value 30 | `class vars`; `TurretRangeAngled.as:draw` |
| Cone cycle | none → wide → medium → narrow → none; direction = bearing from turret to mouse at the time of setting | `Turret.as:turretTargetDirectional/Set` |
| Cone test | `d = (target_angle_deg + 360 − (bearing₀₋₃₆₀ + 360)) mod 360` with AS2 sign-preserving `%`; accept if `|d| < spread` in the slice and `|d| ≤ spread` in keep-current. No wrap-around handling: a cone pointing at e.g. 355° rejects a creep at 5° | `targetAcquireBySlice`, `targetInRange` |
| Must face | `|bearing − rotation| < 1°` or `<` this tick's turn step → snap & allow fire | `turrets/Turret.as:turretBearTowards` |
| Focus (key F) | `attackerFocus(att)` sets `weapon_target = att` on every `turret_subtype == "weapon"` turret (still subject to keep-current range check next tick) | `AttackerManager.as:attackerFocus` |

---

## 6. Creeps (`AttackerEngine.as`, `AttackerManager.as`, `WaveManager.as`)

| Item | Value | Citation |
|---|---|---|
| Classes | `Attacker0..8` are all `AttackerEngine`; no per-type HP/speed/bounty multipliers | `.legacy/deobfuscated/Attacker*.as` |
| Type per wave | `(wave_num − 1) mod 9`; whole wave is one type | `WaveManager.as:update` |
| Repoint (rotate `Body` to face next waypoint, snapped at each waypoint) | types 1, 3, 4, 5, 7, 8 (`attacker_point = [F,T,F,T,T,T,F,T,T]`) | `WaveManager.as:ctor`; `AttackerEngine.as:updateMove` |
| Spawn | at road point 1 + `round(U(0,19) − 9.5)` px in x and y (`waypoint_jitter` 19 ⇒ −9 … +9) | `AttackerEngine.as:ctor` |
| Waypoint jitter | every leg targets `waypoint + round(U(0,19) − 9.5)` (re-rolled each time `updateMove` runs, i.e. also after every slow/replenish) | `AttackerEngine.as:updateMove` |
| Movement | linear pausable tween over `distance / move_speed` s; reaching past the last waypoint → `roadBaseHit()` and removal | `AttackerEngine.as:update/updateMove/attackerHitBase` |
| Fade-in | alpha 0→100 over 225 ms (eternal clock) | `AttackerEngine.as:onLoad` |
| Scale | `Body._xscale = _yscale = 100 + (scale_bump − 1) × 6` %, `scale_bump = 10 / wave_size` (1 if `attacker_size_change` false) | `AttackerEngine.as:onLoad`; `AttackerManager.as:waveSend` |
| HP / bounty per wave | `energy_start = attacker_energy × 10/wave_size`; `cash_bounty = round(wave_num × 10/wave_size)`; `attacker_energy *= attacker_upgrade_rate` each wave | `AttackerManager.as:waveSend/_waveNext` |
| Spacing | one creep every > 700 ms (checked on a 200 ms tick) | `WaveManager.as:update` |
| Hit rule | no hitbox: everything tests the creep centre point (shell 3 px, rocket 8/10 px, blast ≤ size/2, rail beam shape, landmine ±20 box, shockwave ±10 box, black hole ≤ radius); size/scale is visual only | engines above |
| Damage | `energy −= dmg`; ≤ 0 → `hit_by.turretKill()` (if given), "AttackerDead", `attackerKilled` (cash, kills); else "AttackerHit" (no asset → silent), health text = `ceil(energy/energy_start × 100)` | `AttackerEngine.as:attackerHit` |
| Slow | `minus == true`: `speed −= p`; else `speed /= p`; then `speed = max(speed, 5)`; re-tweens the current leg | `AttackerEngine.as:attackerPoison` |
| Replenish | while `speed < move_speed_init`, a 1000 ms pausable timer (one at a time) adds +2 px/s (capped at initial), skipped while paused | `AttackerEngine.as:updateMove/attackerReplenish` |
| Speeds | easy 60, medium 60, hard 80, extreme 80 px/s (challenge speed list overrides) | `AttackerManager.as:ctor` |

---

## 7. Sounds (`SoundPlayer.as`, `.legacy/dissassembled/symbolClass/symbols.csv`, `.legacy/dissassembled/sounds/`)

Playback rule (`SoundPlayer.as:play/classCount`): candidates = `Event` (if a library entry
exists) plus `Event01 … Event99` that exist; one picked uniformly at random. Pan (only when a
source clip is given and `sound_pan_max > 0`): `pan = (1.6 × max(1, x) / 720 − 0.8) × 100`
(−80 … +80). Volume = `GameStatus.sound_volume` (80). New `Sound` each play (16-channel counter
is cosmetic). Nothing plays if sound is off / volume 0.

Exported files are `<symbolId>_<name>.aif.mp3` (42 MP3s, ids 951–992) plus `-1.wav`.

| Event (code) | Library key(s) | Asset (symbol id) | Exported file(s) | Played by |
|---|---|---|---|---|
| Cannon | Cannon01, Cannon02 | ONS2_cannon_2shrt.aif (976), ONS2_cannon_3.aif (975) | 976_ONS2_cannon_2shrt.aif.mp3, 975_ONS2_cannon_3.aif.mp3 | Blue `sound_fire` |
| Laser | Laser01 | ONS2_laser_09_var.aif (970) | 970_… | Green |
| Rocket | Rocket01..03 | ONS2_rocket_09 (961), _05 (962), _03 (963) | 961_, 962_, 963_… | Red |
| Tazer | Tazer01 | ONS2_taser_30.aif (959) | 959_… | Yellow, Railgun, ClusterSpark |
| Sniper | Sniper01 | sniper_03.aif (956) | 956_… | Sniper |
| FusionLow / FusionMed / FusionHigh / FusionMax | same names | Fusion_Low_01 (980), Fusion_Med_01 (978), Fusion_Hi_01 (981), Fusion_Max_01 (979) | 980_, 978_, 981_, 979_… | Fusion discharge |
| BlastSmall | BlastSmall | BlastSmall_01.aif (988) | 988_… | impact `sound_blast` |
| BlastMedium | BlastMedium | BlastMed_01.aif (989) | 989_… | impact |
| BlastLarge | BlastLarge | BlowUp_02.aif (987) | 987_… | Nuke impact |
| BlastBFG | BlastBFG | BFG_01.aif (992) | 992_… | BFG impacts |
| BlackHole | BlackHole01 | black_hole_01.aif (990) | 990_… | black hole (twice) |
| Combo | Combo | combo_16.aif (985) | 985_… | every combo |
| FreakoutWarn | FreakoutWarn | FreakWarning_01.aif (982) | 982_… | freakout |
| FreakoutStart | FreakoutStart01 | freakout_up_20.aif (983) | 983_… | freakout |
| FreakoutEnd | FreakoutEnd | freakout_dn_20_shrt.aif (984) | 984_… | freakout |
| NextWave | NextWave01 | ONS2_nextWave_02.aif (968) | 968_… | WaveManager ctor |
| Build | Build | ONS2_turretmade_inv_4.aif (958) | 958_… | turret placed |
| Sell | Sell | weapon_sale_01.aif (951) | 951_… | sell |
| Weapon | Weapon01 | ONS2_newWeapon_1.aif (969) | 969_… | unlock |
| UpgradeDamage / UpgradeRange / UpgradeRate | …01 | ONS2_chime_04.aif (974) | 974_… | upgrades |
| UpgradeNo | UpgradeNo | ONS2_raspberry_chirp_short.aif (966) | 966_… | failed upgrade |
| ClickBuild, TurretSelect | same | cartfall_14.aif (986) | 986_… | rack click, select |
| ClickButton, ClickTab | …01 | ONS2_click_01.aif (973) | 973_… | UI |
| ClickMin / ClickMax | same | ONS2_close_01 (972) / ONS2_open_01 (967) | 972_, 967_… | UI |
| ClickLeft / ClickRight | …01 | ONS2_ratchet_04.aif (965) | 965_… | UI |
| RackPrev / RackNext | …01 | ONS2_ratchet_05.aif (964) | 964_… | weapon rack |
| Pause / UnPause | same | pause_03 (957) / un_pause_03 (955) | 957_, 955_… | pause |
| AttackerDead | AttackerDead01 | ONS2_explode_05shrt_02.aif (971) | 971_… | creep killed |
| AttackerHit | — (no entry) | — | — | silent |
| BaseHit | BaseHit01 | ONS2_scream_03.aif (960) | 960_… | creep reaches base |
| BaseDead | BaseDead01 | ONS2_basehit_02.aif (977) | 977_… | base destroyed |
| BaseWarn3 / 2 / 1 | same | vox_3/2/1_lives_remaining (952/953/954) | 952_, 953_, 954_… | lives voice |
| Message | Message01 | ONS2_raspberry_mid_31.aif — **not in the SWF** | — | silent |
| (unused) Chime, Click, ClickUpgrade | Chime01/02, Click01, ClickUpgrade01 | ONS2_chime_02/03 (**not in SWF**), ONS2_click_06 (991), ONS2_click_01 | 991_… | never played by code |

---

## 8. Art symbols (`symbols.csv` id → class; frames from `.legacy/dissassembled/sprites/` = SWF frameCount)

Child structure from FFDec `-swf2xml` (scratch dump). "f" = frames.

### 8.1 Turrets (all bodies share base shape 818 and three `TurretUpgradeLevels` 556 pips: IndicateRate/Range/Damage)

| Class (id) | Body shape | Legs | Weapon (id, frames, labels) |
|---|---|---|---|
| TurretBlue (828) | 819 | CannonLegs (821) | Cannon (827, 20f: Idle 1, Firing 2, Reset 20) |
| TurretGreen (866) | 853 | — | Laser (861, 16f: Idle, Firing); flags TurretLinkGreen (863) = LinkOfferedFlag, TurretLink (865) = LinkWantedFlag |
| TurretRed (910) | 900 | — | MissileLauncher (909, 18f: Idle, Firing, Reset 18; 4 tubes `Fired0..3` = sprite 904 (15f, "Fire") containing Missile (903); FirePoint0..3) |
| TurretYellow (923) | 919 | ElectricLegs (845) | SparkGun (922, 11f: Idle, Firing) |
| TurretSniper (918) | 911 | CannonLegs (821) | unnamed sprite 917 (22f: Idle 2, Firing 3, Reset 22; BrassPoint/BrassPointTo) |
| TurretFusion (852) | 843 | ElectricLegs (845) | unnamed sprite 851 (11f: Idle, Firing) |
| TurretRailgun (882) | 867 | — | Railgun (881, 18f: Idle, Firing) |
| TurretTargeter (945) | 942 | CannonLegs (821) | TargetBeacon (944, 1f) |
| TurretCombonly (932) | 924 + 929 | (attached later) | Spinner = CombonlyPlate (928; rings CombonlyPlateRing 927 ×2); TheColour = CombonlyWhite (931); also CombonlyBlue 934, CombonlyGreen 936, CombonlyRed 938, CombonlyYellow 940 |
| TurretRangeUp (890) | 883 | — | RadarDish (889, 6f: Start 1, Scan 3, Bounce 5); RadarSweep 887, RadarBlipPoint 886 |
| TurretRangeUpExchange (891) | 883 | — | RadarDish 889 + ModifyExchanger (841) |
| TurretDamageUp (837) | 829 | — | DamageUp (836, 50f) |
| TurretDamageUpBig (839) | 838 | — | DamageUp (836) |
| TurretDamageUpBigExchange (842) | 838 | — | DamageUp (836) + ModifyExchanger (841) |
| TurretRateUp (898) | 892 | — | RangerPulse (897, 25f, Pulse 2) |
| TurretRateUpExchange (899) | 892 | — | RangerPulse (897) + ModifyExchanger (841) |
| Firing Point (824) | marker used as `FirePoint` in weapons | | |

### 8.2 Creeps (each = `Body` sprite with one bitmap-filled shape + `HealthBar` text)

| Class (id) | frames | Body sprite → shape → bitmap (`.legacy/dissassembled/images/`) |
|---|---|---|
| Attacker0 (710) | 9 | 708 → 707 → 706.png (17×18) |
| Attacker1 (705) | 9 | 703 → 702 → 701.png (24×24) |
| Attacker2 (700) | 9 | 698 → 697 → 696.png |
| Attacker3 (695) | 9 | 693 → 692 → 691.png |
| Attacker4 (690) | 9 | 688 → 687 → 686.png |
| Attacker5 (685) | 9 | 683 → 682 → 681.png |
| Attacker6 (680) | 9 | 678 → 677 → 676.png |
| Attacker7 (675) | 9 | 673 → 672 → 671.png |
| Attacker8 (670) | 1 | 667 → 666 → 665.png (24×24) |

### 8.3 Projectiles and effects

| Class (id) | frames | Notes |
|---|---|---|
| Bullet (770), Bullet2 (771), Bullet3 (773), Bullet4 (775), Bullet5 (777), Bullet6 (778), Bullet7 (780), Bullet8 (782), Bullet9 (784) | 1 each | Bullet/Bullet2 share shape 769; Bullet5/Bullet6 share 776 |
| BulletSniper (785) | 1 (empty) | tracer drawn in code |
| Rocket (728), Rocket2 (730), Rocket3 (732), Rocket4 (734), Rocket5 (736), Rocket6 (738), Rocket7 (740), Rocket8 (726), Rocket9 (724) | 1 each | all contain sprite 712 + own body shape |
| RocketNuke (718), RocketPoison (716), RocketNapalm (720), RocketLaser (722), RocketTazer (714) | 1 each | same construction |
| BFG (815), BFGTazer (817) | 5 | BFGOrb1 (808, 42f), BFGOrb2 (812, 38f), BFGOrb3 (814, 64f); BFG body shape 786 is also BlastBFG's shape |
| ClusterBomb (768) | 1 | |
| Landmine (748), LandmineBig (752), LandmineBigCluster (754), LandmineBigClusterLaser (758), LandmineSparky (762) | 19 each ("Beep" 1) | |
| LaserBeam (744), Spark (741), RailLaser (46) | 1 (empty) | drawn in code |
| ClusterBlast (35), ClusterSpark (36) | 1 | invisible spawners |
| Shockwave (743) | 1 | ZapFrom/ZapTo markers (742) |
| BlackHole (802) | 1 | Swirl (801), Core (742) |
| BlackHoleDebris (804) | 1 | |
| BlastSmall (799), BlastMedium (793), BlastNapalm (794) | 1 | share shape 792 (scaled at runtime) |
| BlastLarge (791), BlastHuge (789), BlastPoison (796), BlastShockwave (798), BlastBFG (787) | 1 | |
| RocketTrail (267) | 31 | |
| BarrattBrass (240) | 1 | |
| SpecialFire (215) / SpecialTake (218) | 14 / 14 | combo leader / helper flashes |
| TurretFreakWarning (226) | 20 ("Start") | |
| CashEarned (72) | 19 | |
| TargetMode (221) | 1 | contains Crosshair (22) + text |
| Crosshair (22), AttackerFocus (24) | 1 | |
| FusionGlow (232), FusionGlowBlue (234), FusionGlowRed (236), FusionGlowWhite (238) | 1 | |
| TurretComboInRange (223), TurretHighlight (228) | 1 | |

### 8.4 Map, build and HUD

| Class (id) | frames | Notes |
|---|---|---|
| PlayerBase (255) | 1 | 10 life lights `Life1..Life10` = sprite 254 (10f: Alive 1, Dead 6) |
| Waypoint (244) | 5 | road point markers (hidden in game) |
| WaypointInsert (242), WaypointPath (259), BuildWaypoint (260), MinePoint (257) | 1 | editor; map-editor start/base markers are unnamed sprites 1159 (`WaypointStart`) and 1168 (`WaypointBase`) on frame 42 |
| TurretRange (198), TurretRangeEffective (230), TurretRangeAngled (941, drawn in code) | 1 | |
| BuildArea (200), BuildShape (211), MoveShape (208), CanBuild (210) | 1 | |
| CannotAfford (203), CannotBuild (205) | 10 each ("Start") | |
| TurretJoiner (950): CanJoin (946), CannotJoin (947), AlreadyJoined (949) | 1 | |
| WeaponRack (188), WeaponRackItem (196; Hover 190, ItemPoint = WeaponRackPoint 195), WeaponRackSliding (1110; mask 1105, buttons 1109), BuildPanel (1126), ReviewWeapon (1117), ReviewModifier (1125), ReviewRating (1115) | 1 | rack icons are **live turret clips** (inactive, rotated 60°), 48 px pitch (`WeaponRackItem.as:itemPopulate`, `WeaponRack.as`) |
| WaveClock (78), MIniClock (1144), TimeLimit (1145), KillTarget (1149), WaveLimit (1153), LittleWaves (1151), DeadSmiley (1147), Padlock (647), BigTick (645), SoundMute (625), GamePause (31), UpgradePanel (636), UpgradeGraph (522), MiniMap (186), MiniMapWhite (1034), TurretInfo (620) | 1 | HUD |

### 8.5 Game background / ground (main timeline frame 37 "GameStart"; same layers on frames 42 and 47)

| Depth | Item | Detail |
|---|---|---|
| 1 | sprite 1095 → shape 1022 | clipped bitmap fill of **image 1021.jpg (611×475)**, placed at (0,0) with scale 1.17839 × 1.01051 ⇒ covers 720×480. This is the ground texture under the road |
| 3 | sprite 1026 → shape 1025 | translucent tan decoration, fill RGBA(183,158,133, 89/255), at (491.5, 174.35) scale 1.212 |
| 5 | sprite 1024 → shape 1023 | line decoration at (149.65, 304.85) scale 1.4718 |
| 7 | shape 1096 | HUD strip x 0–720, y 480–535: linear grey gradient #333333 → #7B7B7B → #1E1E1E → #1A1A1A (ratios 24/83/167/255) |
| 149 | `Game` (GameManager, 39) | RoadManager draws the road inside it: 31 px #666666 stroke + 28 px #B2885B core (`RoadManager.as:roadBuild`); minepoints every 4 px: `n = floor(segment/4)` points at fractions i/n, rounded to integers, tagged with the segment's end-waypoint index |
| 155 | `PlayArea` (sprite 1140, invisible) | hit-test area for build/join |
| 157 | shape 1141 | border lines |

(The intro/menu frame 35 places shape 1022 directly at depth 1, with scale 1.17839 × 1.12631 ⇒ covers the whole 720×535 stage, the attract demo's road and turrets included. The stage cuts off what runs past its edges: the round caps of roads that start on an edge, and creeps walking in. Its decorations, under the road: sprite 1024 at (546.7, 46.35) scale 1 at depth 2, sprite 1026 at (129.1, 87.7) scale 1 at depth 4, sprite 1026 at (551.65, 445.8) scale 0.997 turned 108.56° at depth 6, sprite 1024 at (113.9, 424.2) scale 0.9995 turned −98.52° at depth 8. Both engines' placements are in `world.groundArt` and `attract.groundArt`.) Other bitmaps: 1003.jpg
(302×56, shape 1004 in sprite 1014) and 999.png (285×133, shape 1000 in sprite 1001) are
menu/credits art.

---

## R. Reference doc discrepancies (`docs/ONSLAUGHT2_GAME_REFERENCE.md`)

1. **§4 / §5 values come from ModDefaults, not the classes.** `ModManager.modObject` only applies
   per-asset *deltas*; with no active mod the class constructors win. Known class-vs-ModDefaults
   differences: Blue damage step 8 amount = **18 400** in `TurretBlue.as:ctor` (doc/ModDefaults
   19 400); Fusion base damage 1 000 000 vs 4 000 000 (doc quirk 10 already notes);
   `TurretDamageUpBig.turret_cost` static = 85 000 (unused — `GameManager` cost table says 8 500).
2. **§4 `combo_rate = 7/min ⇒ 8571 ms` is wrong**: `combo_rate_msec` is computed but never read;
   the only combo cooldown is each recipe's `recharge` (leader) / `recharge − 1` (helpers).
3. **§4 freakout**: the first automatic freakout is never scheduled (`freak_next` undefined vs
   `== false` guard), and buying one is impossible too (its cost is NaN until something is scheduled), so in the original freakouts never happen; buy cost is **$250 × seconds
   remaining** (`floor((freak_next − now)/1000) × 250`), not a flat 250; **key F is "attacker
   focus"**, freakout has no key (info-panel button only). Doc omits 3000 ms warning on game
   clock and weapon jitter (≤ 4 px/frame).
4. **§4 must-face**: doc correct (1° or one tick); omits that turrets tick every 70 ms (Fusion
   64 ms), not 32 ms.
5. **§4 targeting**: missing the AS2 cone wrap-around bug (cones spanning 0° reject one side),
   strict `>`-from-0 for maximise modes, turret bbox caching, and that spreads are half-angles.
   `target_type_num` starts at 0 for all, so Yellow/Targeter cycle "fast → far".
6. **§5 Yellow charge**: the charge does **not** raise damage — `charge_damage` is display-only;
   only poison is boosted (`+3 × charge/100` added to poison). Doc's "`+charge/100` damage mult"
   is unimplemented.
7. **§5 Green link**: link range is each green's own *effective* range (asymmetric); recursion
   compounds 1.25 per depth; helpers fire their laser at the leader and spend their reload; no
   helper limit.
8. **§5 Red holding**: orbit circle passes through the launch point (not around the turret);
   held count includes dead rockets; normal rockets also get `holding_capable` once unlocked.
9. **§7 Fusion**: feeders do not fire "instead of at creeps" — only the first reloaded feeder per
   64 ms fusion tick fires into it (others keep shooting creeps); discharge also needs normal
   reload/facing; fires even with empty store; doc omits damage/range/rate upgrade tracks (dmg
   5000→3M, 7500→10M, 10000→35M; range 4000→400/500; rate 5000→60, 8000→90) and glow tier maths.
10. **§7 Targeter**: joined turrets fire at the painted target **ignoring their own range**; joins
    are FIFO-replaced at 3; Targeters can join other Targeters; paints only after bearing.
11. **§7 Combonly**: "range 300" is only firing range; it scans with the 70 px combo range;
    per-colour option = last matching rule (list in §4.8); consumed turrets' value goes into the
    plate's `cash_value` with no refund until the plate is sold.
12. **§7 Sniper/Railgun**: Railgun rate track (5000→60, 6000→90) missing; Railgun fire sound is
    "Tazer".
13. **§8 Blue table**: Sparky Landmine also takes a red helper if one is ready; its spark
    `cluster_damage` is never set (1 000 000 raw, poison 20). "Landmines fly (220 px/s)" is wrong:
    they tween to the mine point in a fixed 1000 ms (`move_speed` unused). Big Laser Cluster
    Landmine takes its green with a plain take (no link pool), unlike Laser/Big Laser Cluster
    Bomb which add the green's link pool to the cluster laser damage. `big_sparky_clusterbomb`
    exists but is unreachable.
14. **§8 Red**: Napalm impact and drops are silent; Napalm rocket flies at 250 px/s; Poison-gas
    blast damage raw (doc quirk 2 ok); Laser Rocket "laser-blast of 6 beams" never happens (doc
    quirk 3 ok, but the prose in §8 still claims it).
15. **§8 Green**: Rocket BFG needs R≥2 but takes only **one** red; the "green link pool" added to
    BFG damage is `linkFire(self,0)` = 0 when the green has no link neighbours (own damage is not
    added in that case). BFG "reacquires targets" but `no_rotate` means it flies **straight** and
    only detonates on a creep within 10 px of its path.
16. **§8 Yellow**: recipe tests use **exact** counts: Black Hole needs G == 1, Shockwave B == 1 and
    G == 1, Tazer BFG B == 1. Shockwave adds the green's link pool to all its damage. "BlackHole"
    sound plays twice.
17. **§10 / §13 sounds**: "AttackerHit/Dead (`ONS2_explode_05shrt_02`, `ONS2_scream_03`,
    `cartfall_14`)" is wrong — AttackerDead = explode_05shrt_02; `ONS2_scream_03` = **BaseHit**;
    `ONS2_basehit_02` = **BaseDead**; `cartfall_14` = ClickBuild/TurretSelect; AttackerHit has no
    asset. Chime01/02 (ONS2_chime_02/03) and Message01 (ONS2_raspberry_mid_31) are referenced but
    not in the SWF. 42 MP3s (+`-1.wav`), not 43.
18. **§13 Rocket**: reacquire keeps the current target while it is within 1000 px (doesn't pick
    nearest every tick); sub-rockets ignore `rocket_range`; doc omits per-rocket 32–42 ms tick.
19. **§13 Spark**: segment count is `max(3, floor(d/11)) + U{0..5}`; doc's "≈ dist/11" ok-ish.
20. **§13 Cluster bomb**: within 3 px it deals direct damage every frame without exploding (quirk);
    explodes on target loss.
21. **§13 Blasts**: blast poison is divide-mode with default 1 (no slow) except poison gas (2) and
    shockwave (75); BlastNapalm's own sprite never grows; blasts can be swallowed by black holes.
22. **§13 Black hole**: holed creeps are immune but **still targetable**; bullets are captured by a
    square box (not the radius circle), including blasts and landmines; `blackhole_eject` has no
    effect; suction, open/close tweens and debris run on real time, duration on game time.
23. **§13 Shockwave walkers**: slow uses `blast_poison` (75), damage uses the modified
    `blast_damage`; blast centred on the target, not the impact point; the spawn-ward walker is
    probably destroyed during construction (AttackerEngine ctor quirk); 15 decorative sparks.
24. **§3 creeps**: jitter is re-rolled on every slow/replenish re-tween; spawn jitter integer
    −9…+9; HP/bounty scale with `10/wave_size`; no per-type stats.
25. **§11**: the ground under the road is bitmap **1021.jpg** stretched to 720×480 plus two
    decorative overlays; the bottom 55 px HUD strip is a grey gradient (not described in doc).
26. **§6 modifiers**: aura radius uses the modifier's *base* range; Targeter is modifiable
    (modifiers do affect it); the doc omits that modifiers stack with freakout mults.
