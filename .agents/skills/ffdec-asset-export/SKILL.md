---
name: ffdec-asset-export
description: Export art, animation frames, sounds and scripts from the original Onslaught2.swf with JPEXS FFDec on this Mac, at the densities and in the formats the asset pipeline expects, map them to logical asset ids, and maintain the vector redraws of symbols that are only small bitmaps in the SWF (the creeps). Use when adding or regenerating any original asset, editing a redraw, or when the legacy export needs refreshing.
---

# FFDec asset export

## Facts (verified 2026-10-18)

| Item | Value |
|---|---|
| FFDec | 26.3.0, `~/Downloads/ffdec_26.3.0_macosx/FFDec.app/Contents/Resources/ffdec-cli.jar` (developer machine only; not a build dependency) |
| Java | OpenJDK 21 (Homebrew) on PATH |
| rsvg-convert | librsvg 2.63 (`brew install librsvg`, `/opt/homebrew/bin/rsvg-convert`); renders the vector redraws in `tool/art/` (developer machine only, not a build dependency) |
| SWF | `.legacy/Onslaught2.swf` (720×535 stage, AS2) |
| Symbol map | `.legacy/dissassembled/symbolClass/symbols.csv` (`id;"Name"`) |
| Existing exports | `.legacy/dissassembled/` (sprites 1× PNG, shapes SVG, sounds MP3, fonts, texts, frames), `.legacy/deobfuscated/` (readable scripts) |

```bash
FFDEC="$HOME/Downloads/ffdec_26.3.0_macosx/FFDec.app/Contents/Resources/ffdec-cli.jar"
SWF=.legacy/Onslaught2.swf
OUT=/tmp/ffdec-out        # never export into .legacy/ (rule R11); the pipeline copies what it needs
```

## 1. Find symbol ids

```bash
grep -i '"TurretRed"\|"Cannon"\|"Attacker0"' .legacy/dissassembled/symbolClass/symbols.csv
```
Game art symbols of interest: `Turret{Blue,Green,Red,Yellow,Sniper,Railgun,Fusion,Targeter,
Combonly}`, weapons `Cannon`, `Laser`, `MissileLauncher`, `SparkGun`, `Railgun`, legs
`CannonLegs`, `ElectricLegs`, creeps `Attacker0..8`, projectiles `Bullet..Bullet9`,
`Rocket..Rocket9`, `RocketLaser/Napalm/Nuke/Poison/Tazer`, `BFG`, `BFGTazer`, `ClusterBomb`,
`Landmine*`, `BlackHole`, blasts `Blast*`, `RocketTrail`, `BarrattBrass`, `PlayerBase`,
`Waypoint*`, `TurretRange*`, `BuildArea`, `CashEarned`, `TargetMode`, HUD icons.

## 2. Export

```bash
# Vector-crisp raster at 4× (44 px turret → 175 px); frames of animated sprites come out as 1.png, 2.png…
java -jar "$FFDEC" -zoom 4 -selectid 910,827,710 -format sprite:png -export sprite "$OUT/png4x" "$SWF"
# True vectors (SVG per frame; a few symbols embed bitmaps)
java -jar "$FFDEC" -selectid 910 -format sprite:svg -export sprite "$OUT/svg" "$SWF"
# All sounds (already in .legacy/dissassembled/sounds as MP3; re-export only if needed)
java -jar "$FFDEC" -format sound:mp3 -export sound "$OUT/sound" "$SWF"
# Readable scripts (deobfuscation ON; without these flags the output is control-flow obfuscated)
java -jar "$FFDEC" -config autoDeobfuscate=1,autoDeobfuscateIdentifiers=1,deobfuscateAs12RemoveInvalidNamesAssignments=1,simplifyExpressions=1,resolveConstants=1,as12DeobfuscatorExecutionLimit=200000 -export script "$OUT/scripts" "$SWF"
```
Export is quick (seconds). Omit `-selectid` to export everything.

## 3. Pipeline standards (`tool/export_assets.sh` implements these)

- Export at every density in `SCALES` in `tool/export_assets.sh` (1, 2, 3, 4, 6, 9) to
  produce one atlas set per density; never ship the 1× exports from
  `.legacy/dissassembled/sprites` as-is (too small for retina). The densities cover camera
  zoom × device pixel ratio at max zoom (measured: Pixel 10 ≈ 5.1, retina desktop window ≈ 6,
  iPad Pro ≈ 9.5); the renderer picks the sparsest one at least that sharp and loads its pages
  on demand (`ArtResolver`), so adding a density costs bundle size, not memory up front.
- Name every output by **logical asset id**, not symbol id: `turret.red.base`,
  `turret.red.weapon.f01`, `creep.0.f01`, `projectile.rocket3`, `blast.large.f05`,
  `sfx.fire.rocket.01`. The id → symbol mapping lives in `tool/asset_map.json` and is the
  only place symbol ids appear.
- Pack with `tool/pack_atlas.dart` (run by `tool/export_assets.sh` once per pack; re-run it
  alone on an existing export with `fvm dart run tool/pack_atlas.dart --ffdec <export dir>`,
  adding `--map tool/asset_map_enhanced.json` for the Enhanced pack). Each asset map names its
  `pack`, optional `theme` and whether it carries the original sounds (`"sounds": "legacy"`,
  Classic only). It lays out
  each density separately on trimmed pages of up to 2048 px (a sprite's frames kept together,
  a frame larger than a page on a page of its own) and emits
  `assets/images/<pack>/atlas_<N>x_<page>.png` plus one `manifest.json` (schemaVersion 2:
  per-scale frame rects, registration points from the SVG export). Standalone bitmaps
  (`"images"`, the ground) stop at 3×: they have no detail above their source.
- Preserve animation frame order and count (cannon recoil 17 frames, rocket trail 31,
  creeps 9, missile launcher per symbol); record counts in the manifest.
- Sounds: normalise loudness, keep MP3, name by event id with two-digit variant suffix.
- Fonts in the SWF (Franklin Gothic, Playbill, …) are not redistributable; use open
  substitutes (Libre Franklin for HUD text) and keep the "AREA 51" base as artwork.
- Commit generated atlases and the manifest; keep the script re-runnable; the
  asset-manifest test must pass after regeneration.
- Credit: original art by the original author; the project's credits screen keeps the
  attribution.

## 4. Vector redraws (symbols that are only bitmaps)

A few symbols are small embedded bitmaps in the SWF, not vector art: the nine creeps
(`creep.0`–`creep.8`, 17×18 and 24×24 px). No export adds detail to them; the owner compared
smoothed, crisp-pixel, ffmpeg xBR/hqx and AI upscales (Upscayl) and chose hand-made vector
redraws. Find such symbols by looking for `<image` in FFDec's SVG export.

- **The redraws are Enhanced-only.** Classic keeps the original bitmaps (FFDec's smoothed
  render at every density), so Classic stays faithful. The redraws form the **Enhanced asset
  pack**: `tool/asset_map_enhanced.json` → `assets/images/enhanced/`, loaded by
  `EnhancedAssetPack` and layered over Classic by `enhancedAssetPackProvider`
  (`[enhanced, classic]`); Classic games, menus and editors use `assetPackProvider`
  (`[classic]`). Nothing uses the Enhanced chain until Enhanced games exist
  (docs/ENHANCED_PLAN.md E0).
- Each redraw is `tool/art/<group>/<logical id>.svg` (creeps: `tool/art/creeps/creep.N.svg`),
  referenced as `"svg"` from the sprite's entry in `tool/asset_map_enhanced.json` (same id and
  symbol as in `tool/asset_map.json`). `pack_atlas.dart --map tool/asset_map_enhanced.json`
  renders it with `rsvg-convert` at every density into the frame FFDec exported for the
  original symbol, so the frame size and registration point match Classic exactly.
- Draw in frame coordinates: `viewBox="0 0 W H"` equal to the frame's size in world px (the
  `width`/`height` of FFDec's SVG for that frame), facing the way the sprite faces in its frame
  (creeps face +x, their direction of travel). Trace the original at 9× (crop it from the
  atlas or the crisp `png9x` export) so proportions and placement match.
- Style, as approved by the owner: gradient fills; outlines in a **darker shade of the fill
  they surround**, not black (the turrets' black outlines do not apply to creeps); round
  joins; keep everything inside the viewBox (round tips and outline strokes included); no
  decorative glare unless the original has one; keep the original's recognisable features
  (e.g. creep.2 is a dragon-dance head: four horns, white eyes, split curled mustache,
  unbroken teeth, cloud beard).
- Preview before packing: `rsvg-convert -w 216 -h 216 tool/art/creeps/creep.2.svg -o
  /tmp/creep2.png` (9×), on the ground colour beside a 6× turret for scale. Do not use
  QuickLook (`qlmanage`) to render: it paints an opaque background, mis-sizes images under
  ~480 px and squashes non-square ones.
- After editing a redraw, re-pack the Enhanced pack (above) and keep the asset-manifest tests
  green (`test/services/enhanced_asset_pack_test.dart` checks each creep has its SVG, matches
  the Classic frame it replaces at every density and is smooth at 9×; the Classic test checks
  Classic creeps stay the original bitmaps). Once Enhanced games exist, check it in game at
  max zoom (`android-emulator-qa`); until then compare renders beside a 6× turret.
