# Onslaught 3 Remastered — Implementation Plan (Flutter)

Companion to [ONSLAUGHT2_GAME_REFERENCE.md](ONSLAUGHT2_GAME_REFERENCE.md), which is the
behavioural spec extracted from the original ActionScript. This document is the *how*:
engine choice, architecture, data model, mobile UI redesign, asset pipeline, and a phased
build order with acceptance criteria.

Toolchain at time of writing: Flutter 3.47.6 (stable, via fvm), Dart 3.13, Flame 1.38.x.

---

## 0. Goals and non-goals

**Goals**
- Faithful recreation of the Onslaught 2 rules: 4 colour turrets, 7 modifiers, 5 super
  turrets, 20 combos, freakout, links, fusion, holding pattern, charge, 9 creep types,
  endless waves with the original HP curves, 12 maps + tutorial map, challenge mode with
  the 14 presets, sandbox, mod system, map editor.
- Cross-platform (iOS, Android, web, macOS, Windows, Linux) from one codebase.
- Touch-first UI in the style of Bloons TD 6 (side tray, tap-to-select, bottom sheet for
  the selected tower), in portrait and landscape (the HUD moves to where the screen has
  room, `docs/history/PORTRAIT_PLAN.md`), with pinch-zoom and pan over a map that is wider than the
  original 3:2 play area on a phone.
- **Data-driven from day one**: every number in the reference doc lives in JSON assets
  with a typed schema; code contains behaviour, not balance. The original "mod" system
  becomes "the data layer is editable", not a bolt-on.
- Deterministic, headless-testable simulation.
- **v1 is an exact behavioural copy; v2+ is free to change.** The UI, art/audio
  (including procedurally generated assets), features and content are isolated behind
  interfaces (§5) so they can be swapped later, while the original rules are frozen by a
  faithful-mode regression suite (§8).
- **Tests as guard rails from day one**: data contracts, rule tests, golden-state
  regression fixtures, balance bots, goldens and architecture tests gate every change.

**Non-goals (for v1)**
- The defunct online services (Playr score submit, map share/rate, Kongregate, MochiAds,
  GameGum). Replaced by local progression and share-strings; an online layer can come later.
- Pixel-identical visuals. We reuse the original vector art (re-exported from the SWF) but
  redraw the HUD.
- Multiplayer.

---

## 1. Engine and stack decision

### Decision: Flame 1.x on top of a pure-Dart simulation core

Flame is used for what it is good at (game loop, component tree, `CameraComponent`
with viewport/viewfinder, sprite batching, gesture plumbing, particles, `GameWidget`
overlays so the HUD is ordinary Flutter) and nothing else. **All game rules live in a
pure-Dart package with no Flame or Flutter import.** Flame components are thin views
that read simulation state each frame.

Why not plain `CustomPainter` + `Ticker`: we would re-implement camera math, input
hit-testing, component lifecycle and sprite atlases, with no upside; Flame itself is a
thin Dart layer over `dart:ui` Canvas, so control is not lost. Why not Flame 2.0: it is a
`-dev` prerelease; pin `flame: ^1.38.0` and revisit when 2.0 is stable.

### Package set

| Concern | Package | Notes |
|---|---|---|
| Game loop / rendering / camera / input | `flame` ^1.38 | `FlameGame`, `CameraComponent`, `World`, `SpriteComponent`, `TapCallbacks`, `DragCallbacks`, `ScaleDetector` |
| Audio | `flame_audio` (audioplayers) | SFX pool; original MP3s |
| App state | `flutter_riverpod` | settings, profile/progression, navigation state. The running simulation is **not** stored in Riverpod state (too chatty); it exposes `ValueListenable`s/streams |
| Models + JSON | none (hand-written) | immutable records with `fromJson(JsonReader)` validation in the pure core; no codegen |
| Routing | `go_router` | menu → mode → map → game |
| Persistence | `hive_ce` (all platforms incl. web) | profile, unlocks, best games, custom maps, mods, settings |
| Testing | `test`, `flame_test`, `alchemist` (goldens), `integration_test`, `coverage` (core) | core sim is tested headless; see §8 |
| Lint | `flutter_lints` + `very_good_analysis` (optional) | |

### Repository layout (single repo, Dart pub workspace)

```
onslaught3_remastered/
  pubspec.yaml                  # app
  lib/                          # Flutter app (presentation + platform glue)
    app/                        # MaterialApp, router, theme, DI
    features/
      menu/                     # mode select, map select, challenge picker, settings
      game/                     # GameScreen: Flame GameWidget + HUD overlays
        flame/                  # OnslaughtFlameGame, components, camera, input
        hud/                    # top bar, tower tray, selected-tower sheet, wave clock
      editor/                   # map editor screen
      mods/                     # data editor + import/export
      tutorial/
    services/                   # audio, persistence, share-codec, haptics
  packages/
    onslaught_core/             # PURE DART: data model, simulation, rules, RNG
      lib/src/data/             # typed definitions + JSON loaders + validation
      lib/src/sim/              # world state, systems, events
      lib/src/rules/            # targeting, combos, modifiers, economy, progression
      test/
  assets/
    data/                       # JSON: turrets, combos, projectiles, blasts, waves, maps, challenges, unlocks, strings
    images/                     # atlases (1x–9x) generated by tool/
    audio/
  tool/
    export_assets.sh            # FFDec → SVG/PNG → atlas; the Enhanced pack adds SVG redraws from tool/art/
    gen_data_from_legacy.dart   # one-off: tables in the reference doc → JSON (checked in)
  docs/
  .legacy/                      # original SWF + decompiles (reference only, excluded from build)
```

---

## 2. Simulation core (`packages/onslaught_core`)

### 2.1 Principles
- **Fixed timestep**: `Simulation.step(dtMs)` with a fixed 1/60 s step and an accumulator
  on the caller side. Original formulas are already time-based (px/s, ms), so the step
  size is free to differ from the original ~32 ms tick.
- **Game clock** = sum of steps × speed factor, frozen on pause (mirrors `GameClock`).
  Cosmetic timers that must ignore pause (black-hole suction in the original did) use the
  presentation layer's real clock instead.
- **Seeded RNG** (`Random(seed)`) threaded through the sim so a wave sequence is replayable;
  every random choice (waypoint jitter, display names, combo helper pick, mine point) goes
  through it.
- **No Flutter / Flame types**; use `vector_math` `Vector2` or a tiny `Vec2` value type.
- **Events out, commands in**: UI sends `GameCommand`s (`BuildTurret`, `Upgrade`, `Sell`,
  `Move`, `SetTargetMode`, `SendWave`, `Pause`…); the sim emits `GameEvent`s
  (`TurretBuilt`, `ProjectileSpawned`, `BlastStarted`, `CreepKilled`, `CashChanged`,
  `WeaponUnlocked`, `Message`, `GameOver`…) that the Flame layer and HUD consume. This keeps
  rendering, audio and UI decoupled and makes tests trivial.

### 2.2 World state
```
GameSession
  config: GameConfig (mode, difficulty, map, challenge, mod delta, seed)
  clock: GameClock
  economy: cash, totalSpent, lives, kills, shots, combos
  road: Road (polyline, mine points, length-parameterised lookup)
  creeps: List<Creep>
  turrets: List<Turret>
  projectiles: List<Projectile>        # all engines, see 2.4
  blasts, blackHoles, shockwaves, landmines
  waves: WaveScheduler
  progression: unlock watcher (kills → weapons, modes)
  objectives: ChallengeObjectives (wave limit, kill target, time limit, turret limit)
```

### 2.3 Systems (run in order each step)
1. `WaveSystem` – wave spacing / follow-mode / size & speed lists / HP curve.
2. `CreepMovementSystem` – segment-to-segment with jitter, slow + replenish, base hit.
3. `TurretRelationSystem` – recompute neighbour sets only on build/sell/move/upgrade
   (modifier auras, combo range 70, link range, fusion range, targeter joins).
4. `TurretSystem` – per turret: rotation toward bearing, target acquire (modes + cone),
   can-fire, combo-or-fire decision (recipe priority tables), freakout scheduling, yellow
   charge, red holding pattern, fusion store/discharge, targeter paint/dispatch, combonly
   scan/cycle/lock.
5. `ProjectileSystem` – shells, rockets (steer/orbit/on-board lasers & sub-rockets),
   instant beams (laser, rail, spark), cluster bombs, landmines, black holes, shockwave
   walkers, blasts (grow → damage → fade), napalm spawner.
6. `DamageSystem` – `hit(damage, by)`, `slow(amount, subtract|divide)`, kill credit,
   bounty, dirty kills.
7. `ObjectiveSystem` – challenge win/lose, time limit, kill target, wave limit; mode
   unlock milestones.
8. `CleanupSystem` – remove dead entities; emit events.

### 2.4 Projectile model
One `Projectile` entity with a `ProjectileSpec` (data) and a small behaviour enum rather
than 15 subclasses:

```
ProjectileSpec {
  id, kind: shell|rocket|beam|rail|spark|clusterBomb|landmine|blackHole,
  speed, turnRate, impactRadius, acquireRange, homing: perfect|steer|none,
  holdingCapable, offscreenRemove, noRotate,
  onboardLaser?: {type, damage, range, rateRpm},
  onboardRocket?: {type, damage, rateRpm},
  blast?: {type, damage, slow},
  cluster?: {type: rockets|sparks, qty, damage, holding, laser?: {damage}},
  napalm?: {qty, timingMs, jitter},
  blackHole?: {radius, durationMs, gravity},
  visual: {sprite, trail, tint, tier}
}
```
Combo recipes reference specs by id and may override fields (that is exactly what the
original `comboFire*` functions do by hand). Blasts are their own table (grow ms,
diameter, fade ms, slow mode).

### 2.5 Data schema (assets/data)
All files are JSON with a `schemaVersion`. Loaded once into an immutable `GameData`
object; a `ModDelta` (JSON merge-patch, same shape as the data) is applied on top at
session start. Validation reports path + reason on failure (dev builds assert; release
builds fall back to defaults).

| File | Contents |
|---|---|
| `turrets.json` | 16 turret definitions: cost, unlock kills, base stats, rotate, mustFace, upgrade tracks `[{cost, value}]`, flags (freak, link, fusion, combo, modifiable, joinable), modifier aura, special (`holding`, `charge`, `fusion`, `targeter`, `combonly`), sprite ids, fire sound, random display names, projectile id per damage level |
| `combos.json` | 20 recipes: id, leader colour, requirement `{red, green, blue, yellow}`, priority, recharge, projectile spec + overrides, helper "take" rule, blast, sound |
| `projectiles.json`, `blasts.json` | tables from reference §13 |
| `creeps.json` | 9 visual types (sprite, repoint flag, hp/speed multipliers = 1 for all in the original) |
| `difficulty.json` | HP-rate schedules, creep speed, starting cash per difficulty/sandbox |
| `waves.json` | wave size, spacing, creep spacing, size/speed list semantics |
| `maps/*.json` | 13 built-in maps `{id, name, base, road, thumbnail}` |
| `challenges.json` | 14 presets + picker option lists |
| `progression.json` | kill thresholds → weapon unlock; 2000/4000 milestones → modes |
| `targeting.json` | target mode list, cone spreads |
| `tutorial.json` | 24 pages: title, body, pointer target id, one-time cash grant |
| `strings/en.json` | all player-facing text (messages, tooltips, reviews) |
| `audio.json` | event → clip variants, pan rule |

A one-off generator (`tool/gen_data_from_legacy.dart`) produces the initial files from
the tables in the reference doc so the numbers are never hand-copied twice. The generated
JSON is committed; the tool is kept for audit.

### 2.6 Deliberate rule changes (tracked in `docs/DEVIATIONS.md`)
Default to faithful behaviour; fix clear bugs; keep balance quirks. Each row is a toggle in
`RulesProfile` (§5.4): `classic` keeps the original behaviour bit-for-bit for the regression
suite, `classicFixed` (the v1 default) applies the fixes below.

| Original quirk | Decision |
|---|---|
| Napalm drops use default 1e6 damage not the combo's 2.5e6 | fix (use combo value) |
| Poison-rocket blast damage skips leader modifiers | fix |
| `laser_rocket` laser-blast fields unimplemented | implement as data says (6 beams, 1e6, r300) behind a flag, default on |
| Landmines ignore `bullet_damage` | keep (blast only), drop the field |
| Black-hole kills: no cash/score | keep (balance) |
| Shockwave walker kills: no turret credit | give credit to the leader (stat only) |
| Holding rockets orbit forever | keep (owner decision 2026-10-21; the 20 s lifetime first chosen here stays an unused toggle) |
| Black-hole suction ignores pause | fix (game clock) |
| Fusion base damage 1e6 (class) vs 4e6 (data) | use 1e6 (what players experienced) |
| Tutorial 50-wave limit wiped ⇒ the tutorial never ends (2350-gaby unlocks challenge as it starts) | fix (tutorial ends at wave 50 and is ticked off) |
| Challenge picker "Extreme!" never offered; "3 mins" = 280 s; duplicate "8 Turrets" labels | fix the data |
| Time factor only in settings | add in-game 1×/2×/3× button (BTD6 style); keep the 50–200 % setting as a base factor |
| No deselect on empty-ground click | tap empty ground deselects (mobile convention) |
| First automatic freakout never scheduled (uninitialised `freak_next`) | fix (first freakout 60 s after it becomes available) |
| Spawn-ward shockwave walker removed during construction | fix (both walkers travel) |

---

## 3. Presentation layer (Flame + Flutter)

### 3.1 World, camera and aspect ratio
- World space = the original 720 × 480 px play area, origin top-left, y down. Keeping the
  unit means every range/speed in the data is correct as-is.
- Beyond the play area (owner 2026-10-31): in every orientation and skin, the ground continues
  mirror-tiled with an off-map tint and a border on the play-area edge (`GroundBeyond`,
  `PlayAreaEdge`). Placement remains restricted to the play area.
- Portrait (`docs/history/PORTRAIT_PLAN.md`, owner 2026-10-19; start zoom owner 2026-10-31): the
  map stays **upright** between the stats bar and the tray strip. A game starts zoomed out as far
  as turrets stay 20 pt across, which is the whole map on most phones; double-tap toggles that and
  the view covering the space (the play area's height fits, its width is cropped), and the player
  pans or pinches between them. The attract demo and the map editor start covering it. The view
  is presentation only: the world, every command and the replay are the same in either
  orientation.
- `CameraComponent` with `FixedResolutionViewport`-free setup: viewfinder zoom clamped to
  `[fitWholeMap, max(3 × fit, 2 × home)]`, position clamped so the visible rect stays inside the world rect
  plus margin. Pinch = zoom about the focal point (`ScaleDetector`), one-finger drag on
  empty ground = pan (with a small slop so taps still select), double-tap = toggle fit /
  2×. Desktop/web: wheel zoom, drag pan, keyboard shortcuts from the original mapping.
- Build placement, range circles and the editor all work in world coordinates; the camera
  does the conversion.

### 3.2 Rendering
- `RoadComponent` draws the polyline once into a cached `Picture` (31 px #666 stroke +
  28 px #B2885B core, round joins) — identical to the original look.
- Creeps, turrets, projectiles: `SpriteComponent`/`SpriteAnimationComponent` from atlases
  (see §6). Turret = base + rotating weapon child + upgrade pips.
- Beams/sparks/rail: custom `PositionComponent`s with `Canvas` paths (cheap).
- Blasts, smoke, brass, cash pop-ups: Flame `ParticleSystemComponent` / effects.
- HUD = Flutter widgets in `GameWidget.overlayBuilderMap`, driven by `ValueListenable`s
  exposed by the session (cash, lives, wave, timer, selected turret snapshot). No
  per-frame `setState` of the whole HUD.
- Target 60 fps with 300+ projectiles on a mid-range phone: batch sprites per atlas,
  avoid per-entity `Paint` allocation, object-pool projectiles in the sim.

### 3.3 Mobile-native UI (Bloons TD 6 as the reference)
The app follows the device (portrait and both landscapes). The regions below are the
landscape `bars` layout (Classic's only landscape layout, unchanged from v1); each screen
shape and skin places them through `HudLayout` (`lib/features/game/layout/hud_layout.dart`):
portrait puts the stats on top and the tray as a horizontal strip along the bottom, the
Enhanced skin moves a landscape phone's stats into a left rail (`rails`). Three HUD regions:

**Top bar** (thin, translucent): lives ❤ 10, cash $, wave N, next-wave countdown ring
(tap = send now), speed 1×/2×/3×, pause, menu. Challenge target badges sit under it.

**Right rail — tower tray** (vertical, scrollable, 56–64 pt cells): icon, cost, locked
state with kill-count-to-unlock; long-press = detail popover (the original review pips and
tooltip text). **Drag a cell onto the map** to build: ghost turret + range circle follows
the finger, green/red validity, release to place (BTD6 behaviour). Tap-select + tap-map is
also supported for accessibility. A "keep placing" toggle replaces Shift. The **Tower
placement** setting (`Settings.placement`) also offers **Drop and lock** (BTD6's option,
for phones where the finger hides the ghost): releasing the drag (or a tap on the map
after arming) drops the ghost and locks it, a one-finger drag anywhere on the map then
nudges it 1:1 (a tap moves it there; pinch still pans and zooms), and the placement bar's
**Place** (or **Move here** for a move) builds it where it is valid, with Cancel beside
it; another tray cell swaps the turret in place.

**Bottom sheet — selected tower** (slides up over the lower map edge, map stays
interactive): name, kills/shots, three upgrade buttons with cost, level pips and the
value preview (long-press = max), sell (refund shown), move, target-mode chip (tap cycles,
long-press opens the 8-mode picker), lock toggle, directional-arc chip (tap cycles
off/wide/med/narrow; dragging the arc handle on the map aims it), and a type-specific
card: Link, Freakout (next in Ns, "Buy now $x"), Holding, Charge bar, Fusion store, Modify
list, Combos ("combo with" list + next-combo countdown), Targeter **Join** (enter join
mode, then tap turrets to toggle joins; lines drawn on the map), Combonly (cycle preview,
"Lock this combo" button instead of blind tapping).

Other touch mappings: tap creep with "focus" chip active = attacker focus; range toggle
and combo-range toggle in a small settings popover; messages become toasts + a log sheet.
Tooltips/hover glows become long-press/pressed states. All floating windows become sheets.
Minimum hit target 44 pt. Haptics on place/sell/unlock.

### 3.4 Screens (go_router)
`/` main menu (attract demo behind it, as original) → `/mode` → `/map` → `/game`;
`/challenge` picker (+ presets + best stats) → `/map`; `/sandbox` → `/map`; `/tutorial`;
`/maps` (library/import) → `/editor`; `/mods`; `/settings`; game over / challenge over as
in-game dialogs with Restart / Main Menu.

---

## 4. Meta systems

- **Progression & persistence** (`hive_ce` boxes): `profile` (modes available/complete,
  per-difficulty best score/kills, challenge best games keyed by the encoded challenge
  string, tutorial done, and custom games' own records — owner decision 2026-10-19),
  `settings`, `maps` (custom), `mods`. Export/import of a profile as JSON. The MD5
  "tamper-proofing" is dropped.
- **Share strings**: maps and mods are shared as `ons3:map:<base64url(gzip(json))>` /
  `ons3:mod:…` so they fit in a message or QR code; the import screen validates them.
- **Audio**: `AudioService` maps `GameEvent` → clip variants with the original pan rule;
  settings for volume, mute, wave announce.
- **Settings**: wave spacing 5–40 s, wave-follow, remember, sound, pan, smoke on/max,
  base time factor, show ranges, show combo ranges, haptics, left-handed layout (tray on
  left).

---

## 5. Extensibility architecture (v1 faithful, v2+ replaceable)

v1 ships as an exact behavioural copy of the original. Everything that is *likely to
change later* (UI, art, audio, features, content) is isolated behind a small set of
interfaces so it can be swapped without touching the rules, and the rules themselves are
guarded by the faithful-mode regression suite (§8) so later changes are deliberate.

### 5.1 Layering and dependency rules (enforced by tests)
```
assets/data ──► onslaught_core (pure Dart: data, sim, rules)      ◄── tests drive this directly
                      │  GameEvents out / GameCommands in
                      ▼
            game session facade (ValueListenables + command sink)
             ▲                 ▲                   ▲
   presentation/flame    presentation/hud     services (audio, persistence, share)
   (world rendering)     (Flutter widgets)
             ▲                 ▲
          art pack           ui skin
```
- `onslaught_core` imports nothing from Flutter or Flame. The HUD imports nothing from
  Flame. Features talk to each other only through the session facade and events. An
  architecture test scans imports and fails the build on violations (§8.9).
- Rules never read file paths, widget state or platform APIs; they read `GameData` and
  the seeded RNG. That is what makes the UI, art and platform swappable.

### 5.2 Asset packs (art, audio, fonts) — swappable, including procedural
- Data references assets by **logical id** only (`sprite: "turret.red.base"`,
  `sound: "fire.rocket"`), never by file path.
- `AssetPack` interface: `manifest` (ids → descriptors), `loadSprite(id)`,
  `loadAnimation(id)`, `loadSound(id)`, `theme` (HUD colour/typography tokens).
  Packs resolve in a chain (`[userPack?, hdPack?, classicPack]`) so a new pack only
  needs to override what it changes.
- The ground is resolved through `AssetPack.ground(id)`, a sealed `GroundSource`:
  `ImageGround` (the classic sprite) or `ShaderGround` (a fragment shader in world
  coordinates). The sharp ground (`ProceduralGroundPack`, `shaders/ground.frag`) is layered
  in front (`[procedural, classic]`) when the player picks Ground: Sharp (Enhanced skin).
- v1 ships `ClassicAssetPack` (SWF-exported vectors rasterised to atlases). Future packs
  drop in beside it: an HD/restyled pack, or a **`ProceduralAssetPack`** that builds
  `Picture`s/`Image`s at load time from parameters (turret colour, tier, seed) using
  `dart:ui` Canvas or a shader. Procedural packs implement the same interface, so the
  renderer does not know the difference.
- The renderer resolves ids once at session start (`ArtResolver`) and, every frame, draws the
  density that covers camera zoom × device pixel ratio: the classic pack ships atlases at
  1×–9×, the 3× pages stay loaded as the fallback, denser pages load when first needed and are
  released when idle. Packs can supply SVG, raster, or a draw callback.
- Audio follows the same shape (`AudioPack`), with the original pan/variant rules living
  in `AudioService`, not in the pack.
- An **asset-manifest test** verifies that every id referenced by any data file resolves in
  the active pack chain (§8.10).

### 5.3 UI skins
- The HUD is built against a `GameViewModel` facade (typed `ValueListenable` snapshots:
  economy, wave, selected turret, tray items, messages; plus a `dispatch(GameCommand)`)
  and a `UiSkin` (`lib/app/ui_skin.dart`): `classic` keeps the v1 landscape screen exactly
  and adds only what a new screen shape needs; `enhanced` adds rails, the far-side turret
  panel, ground beyond the play area, the sharp-ground setting, the lifted ghost and the
  22 pt turret hit zone. A game's skin is `UiSkin.forProfile(config.profile)` (Enhanced
  mode, E0, selects it), or forced by `--dart-define=ENHANCED_SKIN=true`.
- A new UI is a new `HudLayout` implementation (and optionally new screens) that consumes
  the same view model. Widget tests run against a `FakeGameViewModel`, so a new skin is
  testable without the sim.
- No Flame types leak into widgets; the only bridge is `GameWidget` and the overlay map.
- Input mappings are data (`input_bindings.json`: gesture/key → command) so desktop
  shortcuts, controller support or a different touch scheme are additive.

### 5.4 Feature extension points
- **Behaviour registries**: turret specials (`holding`, `charge`, `fusion`, `targeter`,
  `combonly`, `modifier`, `link`, `freakout`), projectile kinds, blast kinds and creep
  behaviours are registered by id in `RulesRegistry`. Data refers to behaviours by id; a
  new mechanic = one new behaviour class + data entries, no edits to existing systems.
- **Content packs**: a `ContentPack` is a data overlay (new maps, turrets, combos, waves,
  challenge presets, strings) applied like a mod but shipped with the app and selectable
  per profile. Campaigns/levels later are content packs plus a `Progression` graph.
- **Rules profiles**: `RulesProfile.classic` pins every original quirk and constant
  (§2.6 table becomes toggles). New gameplay goes into a new profile; the classic profile
  is frozen by the regression suite, so "exact copy of the original" stays true even as
  v2 features land.
- **Procedural generation hooks**: `MapGenerator` (seed → `MapDefinition`, same type the
  editor and built-ins produce), `WaveComposer` (wave N → creep roster; the classic
  composer reproduces the original rotation and HP curve), `ProceduralAssetPack` (§5.2).
  Each hook has a classic implementation plus a test contract any new implementation must
  pass (e.g. generated maps must validate and be solvable by the balance bot).
- **Feature flags**: `FeatureFlags` (compile-time defaults + per-profile overrides +
  debug menu) gate unfinished features so trunk stays shippable.
- **Event bus**: new systems (achievements, analytics, replays, tutorials) subscribe to
  `GameEvent`s without touching the systems that emit them.

### 5.5 Versioned schemas and migrations
- Every persisted document (profile, settings, custom map, mod delta, share string,
  replay) carries `schemaVersion`; `Migrator` chains are tested with fixtures from each
  version (§8.11). Data assets are validated against the current schema at test time, so a
  schema change that breaks an old fixture fails CI rather than a player's save.

---

## 6. Asset pipeline (`tool/export_assets.sh`)
The SWF art is vector; the earlier PNG export is 1× and too small for retina. Pipeline:

1. `ffdec-cli -format sprite:svg -export sprite` for every game symbol listed in
   `symbols.csv` (turrets, weapons, legs, creeps 0–8, bullets/rockets, blasts, base,
   waypoints, HUD icons). The SVGs reference embedded bitmaps only for a few textures.
2. Rasterise at 1×, 2×, 3×, 4×, 6× and 9× (verified: `ffdec-cli -zoom 4 -format sprite:png`
   renders the 44 px red turret as a crisp 175 px PNG) and pack each density into its own
   atlas pages with one `manifest.json`; keep per-frame animation strips (cannon recoil 17
   frames, missile launcher, rocket trail 31 frames, creeps 9 frames). 9× covers max zoom
   on high-density screens (measured: Pixel 10 ≈ 5.1 device px per world px, retina
   desktop ≈ 6, iPad Pro ≈ 9.5).
   - Symbols that are only small bitmaps in the SWF (the nine creeps) cannot gain detail.
     Classic keeps them as they are (smoothed); the Enhanced asset pack
     (`assets/images/enhanced/`, from `tool/asset_map_enhanced.json`) holds vector redraws
     from `tool/art/creeps/`, rendered with `rsvg-convert` into the same frames and layered
     over Classic for Enhanced games only. The ground bitmap stays capped at 3×.
3. Sounds: the 42 MP3s already exported; normalise loudness, rename to event ids.
4. Fonts: Franklin Gothic is not redistributable; use an open metric-compatible font
   (e.g. Libre Franklin) for the HUD and keep the "AREA 51" base as artwork.
5. Everything generated is committed; the script is re-runnable.

---

## 7. Build phases, order and acceptance criteria

Each phase ends with green tests and a runnable app on at least iOS simulator, Android
emulator and macOS.

### Phase 0 — Foundations (1 week)
- Dart pub workspace (root `pubspec.yaml` `workspace:` + `packages/onslaught_core`), lint, CI (analyze + test + web build).
- Data schema + `GameData` loader + validator; `gen_data_from_legacy` produces all JSON.
- Asset export script; atlases checked in; `flame`, `flame_audio`, `hive_ce`, router, Riverpod wired; empty `GameScreen` with camera pan/zoom over the Classic map road.
- Test infrastructure (§8): `SimTestHarness`, `FixtureRecorder`, `FakeGameViewModel`, golden
  setup, architecture test, coverage thresholds, CI pipeline (PR + nightly jobs).
- Extension seams in place from the first commit: `AssetPack` chain with `ClassicAssetPack`,
  `GameViewModel` facade, `RulesRegistry`, `RulesProfile.classic`, `FeatureFlags`, schema versions.
- **Done when**: `flutter test` validates every data file; the architecture test passes; the
  Classic road renders and pans/zooms on a phone; CI is green on a PR.

### Phase 1 — Core loop (1–2 weeks)
- Road, creeps (movement, jitter, HP bar, base hit, lives), wave scheduler with difficulty
  curves, cash/bounty, Blue turret with shells, targeting modes, upgrades, sell, move,
  game over. Headless test: "10 blue turrets on Classic survive to wave 20 on easy".
- HUD v1: top bar, tray with drag-to-build, selected-tower sheet (upgrades/sell/move/target).
- Tests: creep movement/jitter/base-hit, wave curve per difficulty, bounty, Blue stats and
  upgrades, targeting modes; first regression fixtures ("Classic easy, blue only, 20 waves");
  HUD widget + golden tests for the three panels.
- **Done when**: a full easy game is playable with Blue only and the fixtures are recorded.

### Phase 2 — Four colours + specials (1–2 weeks)
- Green (beam, link pooling), Red (rockets, steering, holding pattern), Yellow (spark,
  slow, charge, fast/lock-off default), freakout, modifier auras (7 types) with
  added/mult stacking and `max(mult, 0.2)` floor, effective-range ring, weapon unlocks by
  kills, messages/toasts, audio.
- Tests: modifier stacking matrix (every modifier × every colour), link pooling, holding
  dispatch, charge/slow, freakout timing; regression fixture per colour; audio-event mapping test.
- **Done when**: every stat in the selected-tower sheet matches the reference formulas in unit tests.

### Phase 3 — Combos and ordnance (2 weeks)
- Combo capability (damage track maxed), 70 px neighbourhood, recipe priority per leader
  colour, helper "take" + recharge, all 20 recipes; projectile kinds: cluster bomb/blast/
  spark, landmines on mine points, BFG family (on-board lasers/rockets), nuke, napalm
  spawner, poison gas, laser/tazer rocket, black hole (suction, dirty kills, projectile
  capture), shockwave (blast + two road walkers).
- Blast table, slow semantics (subtract vs divide, floor 5, replenish +2/s).
- Performance pass with 300 projectiles.
- Tests: one scenario + one regression fixture per recipe (20), blast-table membership,
  slow semantics, black-hole/shockwave behaviour, perf budget test at 300 projectiles.
- **Done when**: each recipe has a scenario test asserting spawned entities and damage totals.

### Phase 4 — Super turrets (1 week)
- Targeter (paint, join up to 3, touch join mode), Sniper (instant + brass), Railgun
  (piercing 900 px beam), Fusion (absorb green/yellow fire, store, discharge, glow tiers),
  Combonly plate (scan, cycle, lock, consume helpers).
- Tests: join FIFO and dispatch, rail hit-zone geometry, fusion store maths and glow tiers,
  combonly scan table (all 20 outcomes); regression fixture "sandbox2 everything".
- **Done when**: sandbox2 with all 16 turrets is playable.

### Phase 5 — Modes, progression, menus (1–2 weeks)
- Main menu with attract demo, mode/map/challenge screens, sandbox options sheet, tutorial
  (24 pages, pointer arrows, 50-wave end), challenge objectives/time/turret limits and
  presets, unlock milestones, best games, settings, game-over/challenge-over dialogs.
- Tests: unlock milestone table, challenge objective/time/turret-limit outcomes for every
  preset, best-game comparison rule, profile migration fixture v1; E2E smoke flow in CI.
- **Done when**: a new profile can unlock extreme → sandbox → challenge → modding through play (and via a debug unlock-all toggle).

### Phase 6 — Map editor + sharing (1 week)
- Touch editor: drag start/base, tap to add waypoint, drag to move, midpoint insert
  handles, delete via handle button, 20 px snap grid, undo/redo, validate (start, base,
  min length), save/load/delete, play, share string import/export, minimap thumbnails.
- Tests: map validation rules, share-codec property tests, editor widget tests, `MapGenerator`
  contract test (built-ins + a stub generator must pass the same checks).
- **Done when**: a user-made map round-trips through a share string and plays.

### Phase 7 — Mod/data editor (1 week)
- Generic editor generated from the data schema (number/int/bool/string/indexed-array
  widgets with min/max/step/unit descriptors from the original asset library), delta
  storage, activate switch, signature display, import/export, "reset item/asset/all".
- Tests: delta apply/clear semantics, min/max validation per descriptor, import replaces
  whole mod, signature stability, mod migration fixture.
- **Done when**: changing Blue damage in the editor changes the next game and exports as a share string.

### Phase 8 — Polish and release (1–2 weeks)
- Particles/juice, accessibility (large text, colour-blind-safe turret colour badges),
  localisation hooks, platform builds (iOS, Android, web, macOS, Windows, Linux), app
  icons/splash, crash-free soak test at 3× speed to wave 300.
- Screen fit (`docs/history/PORTRAIT_PLAN.md`, done 2026-10-19): portrait and landscape with live
  switching, the HUD per screen shape (`HudLayout`), responsive menus, editor and mods,
  safe areas on every edge, the window-too-small prompt; Enhanced-skin extras (rails,
  far-side panel, ground beyond the map, sharp ground) behind `UiSkin`.
- Tests: accessibility checks, large-text goldens, nightly bot/perf jobs promoted to release gates.

Total: roughly 10–13 weeks of focused work; phases 2–4 can overlap with 5 since they touch different packages.

---

## 8. Testing and guard rails

Tests are the executable spec of the original game and the safety net for every later
change. The rule: **behaviour that is covered by the faithful-mode regression suite can
only change by deliberately updating a fixture in the same PR.**

### 8.1 Layers
1. **Data contract tests** (`onslaught_core/test/data/`): every JSON asset parses, validates
   against the schema (ranges from the original descriptors: range 10–800, rate 1–300,
   etc.), and is referentially complete (every projectile/blast/sprite/sound/map id
   referenced exists; maps lie inside the play area; upgrade tracks are monotonic). A
   snapshot test regenerates the data from `gen_data_from_legacy` and diffs it, so the
   checked-in numbers can never silently drift from the reference doc.
2. **Rule unit tests**: one file per rule in §2–§4 of the reference — effective-stat
   formula and the `max(mult, 0.2)` floor, upgrade cost/value lookup, targeting modes and
   cones, combo capability and recipe priority per colour, helper take/recharge, blast
   membership (circle, no falloff), slow subtract/divide/floor/replenish, HP curve by wave
   and difficulty, bounty scaling by wave size, sell refund, unlock thresholds, freakout
   scheduling, charge accumulation, fusion store/discharge, holding dispatch, link pooling.
3. **Scenario tests**: `SimTestHarness` builds a session from data + seed, feeds scripted
   `GameCommand`s, steps N ticks and asserts state ("Blue at (100,100) kills the first
   creep of wave 1 by tick 240"; "nuke recipe spawns BlastHuge with 60M damage").
4. **Faithful-mode regression (golden-state) tests**: canonical scenarios record the full
   `GameEvent` log plus periodic state hashes to JSON fixtures. Replays must match exactly.
   Fixtures are re-recorded only with `tool/fixture.dart record` (`--update-goldens` is for
   goldens) and reviewed in the PR diff. This
   suite is what freezes "v1 = the original".
5. **Determinism tests**: same seed + commands ⇒ identical events and state hashes, run
   twice in one process and on every platform: the VM on macOS and Linux CI runners and the
   web in Chrome (dart2js and dart2wasm, `tool/web_regression.dart`), which must replay the
   VM-recorded fixtures exactly. Fixtures are never per-platform (owner, 2026-10-20); sin,
   cos and atan2 go through a pure-Dart fdlibm port so no result depends on the host's libm.
6. **Balance regression bots**: canned build orders per map/difficulty (e.g. "Classic,
   easy, blue rush", "Incoming, hard, red+green combos") run headless at max speed; the
   wave reached and cash curve must stay within a tolerance band. Runs on every data
   change and nightly, and doubles as a perf soak.
7. **Performance budgets**: core step time with 300 projectiles / 100 creeps / 60 turrets
   under a per-tick budget on CI (soft-fail with trend report); device frame-time captured
   by the integration run and reported.
8. **Presentation tests**: widget tests for every HUD piece against `FakeGameViewModel`;
   golden tests (`alchemist`) for HUD states (no selection, each turret type selected,
   locked/unlocked tray, challenge badges) at phone/tablet/desktop sizes and light/dark;
   road-render goldens per built-in map; `flame_test` for camera clamping, zoom bounds,
   drag-to-build hit paths and world↔screen conversion.
9. **Architecture tests**: a source-scanning test enforces §5.1 (no Flutter/Flame imports
   in `onslaught_core`; no Flame in `hud/`; features only via facade), and a
   "no magic numbers in rules" check (numeric literals in `rules/` and `sim/` must come
   from `GameData` except an allowlist such as 0, 1, 360).
10. **Asset-manifest tests**: every asset id in data resolves in the active pack chain;
    atlases contain every frame the animations request; every audio event has ≥1 clip.
11. **Persistence and codec tests**: round-trip + migration fixtures per schema version for
    profile, settings, maps, mods and share strings; property tests for the share codec.
12. **Integration / E2E** (`integration_test`, optionally `patrol`): smoke flows —
    menu → map → place → send wave → sell → game over; editor create → save → share →
    import → play; mod edit → activate → verify in game — on iOS simulator, Android
    emulator, Chrome and macOS.
13. **Accessibility checks**: semantics labels present for every control, 44 pt targets,
    text scaling to 1.3× without overflow (golden at large text).

### 8.2 CI gates
- **Every PR**: `dart format --set-exit-if-changed`, `flutter analyze` (warnings fatal),
  unit + scenario + regression + widget + golden + architecture + data tests, the
  regression and determinism suites in Chrome (dart2js and dart2wasm), coverage
  thresholds (core ≥ 85 %, app ≥ 70 %, enforced per package), web and macOS build,
  integration smoke on Chrome + macOS.
- **Nightly**: balance bots, perf budgets, device integration (iOS sim, Android emu),
  3× soak to wave 300, dependency audit.
- **Release**: all of the above plus platform builds and a manual checklist.
- Branch protection on `main`; pre-commit hook runs format + analyze; a CODEOWNERS entry
  on `assets/data/**` and `test/**/goldens/**` so fixture updates are reviewed.

### 8.3 Tooling
`test`, `flame_test`, `alchemist` (goldens), `integration_test` (+ `patrol` for native
dialogs if needed), `coverage` + `lcov` thresholds, a tiny in-repo
`architecture_test` (source scan), and the `SimTestHarness` / `FakeGameViewModel` /
`FixtureRecorder` utilities built in Phase 0.

### 8.4 Definition of done (every phase, every PR)
- New behaviour has rule tests and at least one scenario; new recipe/turret/projectile
  has a regression fixture; new UI has widget + golden coverage; new persisted field has
  a migration fixture; data edits come with regenerated snapshots; CI green.

---

## 9. Open decisions for you
1. **Art direction**: reuse the re-exported vector art as-is (fast, faithful) vs. a
   restyle pass later. Plan assumes reuse for v1.
2. **Monetisation/online**: none planned; the online hooks are deleted, not stubbed.
3. **Name/IP**: the original is Gaby Vanhegan's; the plan treats this as a personal
   remaster. Credits screen keeps the original attribution.
4. **Sim tick**: 60 Hz fixed (plan) vs. the original ~31 Hz. 60 Hz is smoother for homing
   and costs little; choose 30 Hz only if low-end Android profiling demands it.
5. **Left-handed layout** and **portrait support**: left-handed planned as a setting;
   portrait done (2026-10-19, `docs/history/PORTRAIT_PLAN.md`): the app follows the device, no
   orientation setting.

## 10. Immediate next steps (Phase 0 kick-off)
1. Create `packages/onslaught_core` and move the data schema in; write `gen_data_from_legacy`.
2. Run `tool/export_assets.sh` and commit atlases.
3. Add dependencies, lock Flame at `^1.38.0`, set landscape-only, build the empty camera scene.
4. Build the test harness and CI first, then write the first ten core tests from reference §4–§5 formulas and record the first regression fixture.
5. Land the extension seams (`AssetPack`, `GameViewModel`, `RulesRegistry`, `RulesProfile`) as empty-but-wired interfaces before any feature code depends on concrete types.
