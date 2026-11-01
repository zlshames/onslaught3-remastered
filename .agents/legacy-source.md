# Reading the original game

The original is `.legacy/Onslaught2.swf` (Flash, ActionScript 2, version "2350-gaby", from
Slipcor's "Onslaught 2.2" projector on itch.io; 720×535 stage). It replaced the earlier
"2221-nyehi" build on 2026-10-20; `docs/ONSLAUGHT2_GAME_REFERENCE.md` ("Changes in 2350-gaby")
lists what differs. Everything in `.legacy/` is read-only reference (rule R11).

## Which export to read
- `.legacy/deobfuscated/` — **use this**. Readable AS2 classes under `__Packages/`
  (e.g. `turrets/Turret.as`, `GameManager.as`, `RoadManager.as`, `Combos.as`,
  `mods/ModDefaults.as`, `BulletManager.as`, `RocketEngine.as`, `blasts/*.as`).
- `.legacy/dissassembled/scripts/` — the same code exported without FFDec's deobfuscation
  passes; read `deobfuscated/` instead. The rest of `.legacy/dissassembled/` is useful: `sprites/` (1× PNG frames),
  `shapes/` (SVG), `sounds/` (42 MP3 + one WAV), `fonts/`, `texts/`, `frames/` (rendered timeline
  screens: 37 = game HUD, 42 = map editor, 25 = every asset), `symbolClass/symbols.csv`
  (symbol id → class/asset name).

Every class is under `__Packages/` with its own name (the 2221-nyehi export's misfiled
`OnslaughtObject`, `MathCache`, `ModValue` and `ModValueBoolean` and its `DoInitAction_*.as`
copies are gone). Sprite and button scripts are `DefineSprite_<id>_<Class>/`; symbol ids differ
from 2221-nyehi's, so look them up in `symbolClass/symbols.csv` rather than reusing old ids.

## Where each rule lives
| Topic | File(s) |
|---|---|
| Turret base: upgrades, modifiers, combos, links, freakout | `__Packages/turrets/Turret.as` |
| Colour turrets, specials | `turrets/TurretBlue.as`, `TurretGreen.as`, `TurretRed.as`, `TurretYellow.as` |
| Modifiers, super turrets | `turrets/TurretModify.as` + subclasses, `TurretSniper.as`, `TurretRailgun.as`, `TurretFusion.as`, `TurretTargeter.as`, `TurretCombonly.as` |
| Targeting modes, cone, trig | `__Packages/OnslaughtObject.as` |
| Combo data | `__Packages/Combos.as` |
| All default numbers + mod descriptors | `__Packages/mods/ModDefaults.as` |
| Waves, creeps, HP curves | `AttackerManager.as`, `WaveManager.as`, `AttackerEngine.as` |
| Projectiles / blasts | `Projectile.as`, `ShellEngine.as`, `RocketEngine.as`, `LaserEngine.as`, `RailLaser.as`, `SparkEngine.as`, `Cluster*Engine.as`, `LandmineEngine.as`, `BlastEngine.as`, `blasts/*.as`, `BlackHole.as`, `Shockwave.as` |
| Maps, road, placement | `RoadManager.as`, `BuildShape.as`, `MoveShape.as`, `GameManagerMapping.as`, `mapping/*.as` |
| Modes, unlocks, challenges, prefs | `GameManager.as`, `GameSelect*.as`, `GameSettings.as`, `PrefData.as` |
| HUD / info panels | `turretinfo/*.as`, `UpgradePanel.as`, `WeaponRack*.as`, `WeaponReviews.as`, `KeyboardManager.as` |
| Tutorial | `GameTutorial.as` |

Everything above has already been distilled into `docs/ONSLAUGHT2_GAME_REFERENCE.md`;
go to the source only to resolve a question the reference does not answer, then add the
answer to the reference.

## AS2 reading tips
- `attachMovie(name, …, initObj)` copies `initObj` fields onto the instance **before** the
  constructor runs; class-level `var x = 5` are prototype defaults that init values override.
- `_rotation` is degrees, 0 = +x, y down. Rates are "per minute": `msec = 1000 / (rate / 60)`.
- `setInterval(this, "update", ms)` is the per-object tick; `GameClock.timeNow()` is game
  time (scaled, frozen on pause).
- "Poison" means a movement slow, never damage over time.

## Re-exporting (developer machine only)
FFDec 26.3 lives at `~/Downloads/ffdec_26.3.0_macosx/FFDec.app/Contents/Resources/ffdec-cli.jar`
(Java 21 via Homebrew). Readable scripts need deobfuscation on:
```bash
java -jar "$FFDEC" -config autoDeobfuscate=1,autoDeobfuscateIdentifiers=1,deobfuscateAs12RemoveInvalidNamesAssignments=1,simplifyExpressions=1,resolveConstants=1,as12DeobfuscatorExecutionLimit=200000 -export script OUT .legacy/Onslaught2.swf
```
Hi-res art: `-zoom 4 -format sprite:png -export sprite OUT swf` (vector-crisp) or
`-format sprite:svg`. Select symbols with `-selectid` using `symbols.csv`.
