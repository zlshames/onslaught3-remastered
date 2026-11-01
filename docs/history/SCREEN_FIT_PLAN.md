# Screen fit (portrait and landscape, phones, tablets, desktop, web) — plan

Status: **implemented** (2026-10-19) through `docs/PORTRAIT_PLAN.md`, with the owner's
2026-10-19 changes in §11: the portrait map is **upright** and fills the screen, panned
along (P1/P2 superseded, so §5.1–§5.2's quarter turn, `WorldLabel` and the turned pan axis
were not built); §4.2 (rails), §4.4 in landscape, §6.1–§6.2 and §7 are **Enhanced skin
only**; ground beyond the play area also shows in Classic portrait. The owner's decisions,
landscape (D1–D6) and portrait (P1–P3, P4–P8), are recorded in §11.

## 1. Goal

Make every screen shape, in either orientation, a good place to play, while the game itself
stays identical on every device:

- **portrait and landscape**, switching automatically when the player turns the device or
  resizes the window, in the middle of a game, without losing their place;
- **HUD layout per screen shape**: the HUD goes where the screen has spare room, so the map
  gets as much of the screen as possible;
- **minimum touch-target size**: turrets, HUD controls and placement stay comfortable to
  tap on the smallest supported phone;
- **no empty bands**: the space beyond the 720×480 play area looks like part of the world,
  with the playable edge still clear;
- **sharp ground art**: the ground stays crisp on large, high-density screens and when
  zoomed in.

### Non-goals

- **No change to map geometry.** The world stays 720×480 world px for every device and
  orientation; road points, base position, ranges, speeds and spacing are untouched.
  Changing the world per device would make the game different on a tablet and a phone,
  break the regression fixtures, challenge best stats, replays and map share strings, and
  contradict tenet 1 (`docs/REMASTER_PLAN.md` §3.1 already fixes the world unit). Portrait
  play **turns the view**, not the world (§5).
- **No simulation or data changes.** All work is in `lib/` and the platform orientation
  settings. Nothing in `packages/onslaught_core`, `assets/data` or the fixtures changes, and
  the balance bots are unaffected.

## 2. Where things stand

Maps are already data (`assets/data/maps/*.json`: road points + base), the road is drawn as
vector strokes by `RoadComponent`, and `CameraRig` scales the fixed world to the screen:
fit zoom = `min(free.width / 720, free.height / 480)`, where "free" is the screen minus the
HUD insets. Resolution is solved; **aspect ratio**, **orientation** and **physical size** are
not. The app is locked to landscape (`lib/main.dart`, `ios/Runner/Info.plist`,
`android:screenOrientation="sensorLandscape"`), and `docs/REMASTER_PLAN.md` §9 item 5 lists
portrait as "not planned"; this plan reverses that.

Today the HUD is the same everywhere: a 48 pt top bar (`TopBar.height`), a 76 pt tower tray
on the right (`TowerTray.width`) and a 112 pt turret sheet over the bottom of the map
(`TurretSheet.height`). Computed from those constants (safe-area insets are typical values,
not measured; verify on devices in step 1):

| Screen (logical pt) | Fit zoom | Map on screen | Turret (36 world px) | Empty space beside the map |
|---|---|---|---|---|
| iPhone 17 Pro 874×402 | 0.74 | 531×354 (54 % of screen) | **27 pt** | 205 pt wide |
| Pixel 10 AVD 923×411 | 0.76 | 544×363 (52 %) | **27 pt** | ~300 pt wide |
| iPhone SE 667×375 | 0.68 | 490×327 (64 %) | **25 pt** | 100 pt wide |
| iPad Pro 11" 1210×834 | 1.58 | 1134×756 (85 %) | 57 pt | 6 pt tall |
| iPad 10th gen 1180×820 | 1.53 | 1104×736 (84 %) | 55 pt | 12 pt tall |
| Desktop 1280×720 | 1.40 | 1008×672 (73 %) | 50 pt | 196 pt wide |
| Web, portrait phone 390×844 | 0.44 | 314×209 (20 %) | **16 pt** | 540 pt tall |

What this shows:

1. **Tablets are already fine in landscape.** Their shape (≈1.45:1 after the HUD) nearly
   matches the world's 1.5:1.
2. **Phones and 16:9 screens waste height on the top bar and width on side bands.** The
   top bar takes 12 % of a phone's height, which is the dimension that limits zoom.
3. **Turrets are ~27 pt on phones**, below the 44 pt minimum hit target the plan already
   requires (`docs/REMASTER_PLAN.md` §3.3). The tap hit radius is `turretSpacing / 2` =
   18 world px (`SessionGameViewModel.turretAt`), so it shrinks with zoom.
4. **Portrait with the map upright is unplayable** (16–21 pt turrets on phones): a 3:2 map
   on a 9:19.5 screen. Turned a quarter, the map is 2:3 and fits a portrait phone as well as
   landscape does (§5).
5. **Smaller issues**: rig insets leave out the left safe area; the sheet's `right:` ignores
   `padding.right`; `dragTo`'s "over the HUD" test hard-codes the current layout. Every
   layout change has to touch three places that must agree.
6. **Bands**: the ground is drawn only over 720×480; outside it is flat `PackTheme.offMap`.
7. **Ground sharpness**: the original ground is a **611×475 JPEG** (`1022.jpg`) stretched to
   720×480 (`docs/legacy/ENGINE_NOTES.md` §8.5). Our `@2x`/`@3x` files are cubic upscales of
   it (`tool/pack_atlas.dart`), so they hold no extra detail. On an iPad Pro at fit it is
   drawn at ~3.7× its source density, ~11× at maximum zoom. Re-exporting cannot fix this:
   the ground is a bitmap in the SWF. (Turrets and creeps are vector shapes and *can* be
   re-exported at higher densities; see §7.4.)

## 3. Design: one `HudLayout` decides everything

A pure function computes the layout from the screen, and everything else reads from it:

```dart
// lib/features/game/layout/hud_layout.dart
enum HudLayoutKind { bars, rails, portrait, unsupported }

class HudLayout {
  static HudLayout resolve(Size screen, EdgeInsets safe, {HudLayoutKind? previous});

  final HudLayoutKind kind;
  final int mapTurns;      // 0 = map upright, 1 = turned a quarter (§5)
  final Rect stats;        // lives, cash, wave, countdown, speed, pause, menu
  final Rect tray;         // tower tray
  final EdgeInsets mapInsets;   // fed to CameraRig.setInsets (all four edges)
  bool isOverHud(Offset p);     // used by tray drags instead of hard-coded constants
  Rect panelFor(Offset turretScreenPos); // where the selected-turret panel opens (§4.4)
}
```

- **Choosing the layout.** Each candidate (layout × map turn) gives a fit zoom; take the
  largest, with ~5 % hysteresis toward `previous` so a resizing desktop window does not
  flicker between layouts. No device lists and no orientation flags: a portrait phone, a
  tall browser window and a portrait iPad all pick the portrait layout because it gives the
  biggest map.
- **One source of truth.** `GameScreen` positions overlays from the layout's rects,
  `CameraRig` gets `mapInsets` and `mapTurns`, and `dragTo` asks `isOverHud`. This fixes the
  issues in §2.5 by construction.
- **Tuning lives in Dart.** HUD sizes are presentation tuning, not balance (the same as
  `CameraSettings`), so they stay as constants in a `HudMetrics` class, not in
  `assets/data`.
- **Unit tested** with no widgets: a device matrix in both orientations asserts the chosen
  layout and turn, that no fixed HUD region covers the fitted map, and the minimum turret
  size.

## 4. HUD layout per screen shape

### 4.1 `bars` (landscape tablets, 16:10 and squarer screens): today's layout

Top bar + right tray, as today. Only change: insets come from `HudLayout`, including all
safe-area edges.

### 4.2 `rails` (landscape phones, 16:9 desktop and wider screens)

No top bar. The stats move into a **left rail** the same width as the tray, so the HUD sits
in the side bands the map does not use, and the map gets the full height:

| Screen | Fit zoom bars → rails | Map share of screen | Turret size |
|---|---|---|---|
| iPhone 17 Pro | 0.74 → 0.83 | 54 % → 68 % | 27 → 30 pt |
| Pixel 10 AVD | 0.76 → 0.86 | 52 % → 67 % | 27 → 31 pt |
| iPhone SE | 0.68 → 0.72 | 64 % → 71 % | 25 → 26 pt |
| Desktop 1280×720 | 1.40 → 1.50 | 73 % → 84 % | 50 → 54 pt |

(Tablets lose zoom with rails, 1.58 → 1.47 on iPad Pro, so the chooser keeps them on
`bars`.)

- `TopBar`'s contents become a `StatsBar` with an `axis`: horizontal in `bars` and
  `portrait`, vertical in `rails`. The seven controls (lives, cash, wave, countdown ring,
  speed, pause, menu) at 44 pt fit a 402 pt rail with room for spacing. Cash and score use a
  compact number format in the rail.
- Rails sit inside the safe area; the map and ground draw under the notch and the home
  indicator (they are decoration there, not controls).
- Challenge target badges (Phase 5) go under the stats in the left rail.

### 4.3 `portrait` (portrait phones and tablets, tall windows)

The map is turned a quarter (§5) and the HUD stacks above and below it:

- **top**: the `StatsBar`, horizontal, 48 pt;
- **bottom**: the tower tray as a **horizontal, scrolling strip** (~88 pt with costs), in
  thumb reach. Dragging a cell up onto the map builds; the ghost sits above the finger
  (§6.2), which in portrait is also the direction of travel.

| Screen (portrait) | Map upright | Map turned (chosen) | Map share of screen |
|---|---|---|---|
| iPhone 17 Pro 402×874 | 0.56, 20 pt turrets | **0.84, 30 pt** | 69 % |
| Pixel 10 411×923 | 0.57, 21 pt | **0.86, 31 pt** | 67 % |
| iPhone SE 375×667 | 0.52, 19 pt | **0.71, 26 pt** | 70 % |
| iPad Pro 11" 834×1210 | 1.16, 42 pt | **1.43, 52 pt** | 70 % |
| Desktop window 600×900 | 0.83, 30 pt | **1.06, 38 pt** | 72 % |

Portrait phones get the same map size as landscape phones with rails, so neither orientation
is the "lesser" one.

### 4.4 Selected-turret panel

On phones the 112 pt bottom sheet covers 28 % of a landscape screen and often the turret it
describes. The panel opens **on the side of the screen away from the selected turret**, like
Bloons TD 6:

- `rails`: a ~240 pt side panel over the left or right half of the map, whichever does not
  hold the turret. The sheet's rows become a vertical list; the type-specific cards
  (Link, Freakout, Combos, …) already stack.
- `bars` and `portrait`: a sheet at the bottom (over the tray in portrait), or at the top
  when the turret is in the lower part of the map.
- At fit the camera cannot pan, so choosing the side is enough. When zoomed in and the
  turret would still be covered, the camera pans just enough to keep it visible.
- The panel never changes fit zoom; the map does not jump when a turret is selected.

## 5. Portrait: turning the view, not the world

### 5.1 The camera turns a quarter

`CameraRig` gains `mapTurns` (0 or 1). With a quarter turn the world's 720 px axis runs down
the screen and the 480 px axis across it:

- `screenToWorld` / `worldToScreen`, the visible rect, fit zoom and the pan clamp all apply
  the turn; Flame's `camera.viewfinder.angle` draws it. Only quarter turns exist, so the maths
  stays exact (axis swaps and sign flips, no trigonometry drift).
- Everything in the simulation, input commands, replays and fixtures stays in world
  coordinates. A tap is turned into a world point by the rig exactly as today; a game played
  half in portrait and half in landscape is the same game and replays the same.
- **Direction** (§11 P2): the world's left edge goes to the bottom of the screen. Eight of
  the thirteen maps start their road at the left edge, so creeps usually enter at the
  bottom and march up the screen.

### 5.2 What turns with the world and what does not

- **Turns**: ground, road, turrets, creeps, projectiles, blasts, range circles, the base.
  The art is top-down, so it reads correctly at any quarter turn. Headings and turret
  rotations are already world angles (`entity_layer.dart`) and need no change.
- **Stays upright**: anything a player reads. There is no world-space text today; from now
  on any label drawn in the world (cash pop-ups, combo names, tutorial callouts) uses a
  `WorldLabel` component that counter-rotates by the view turn. The tutorial's pointers
  (Phase 5) anchor to world points, never to fixed screen positions.
- **Directional-arc handle** (Phase 2/3): dragged in screen space, converted through the
  rig, so it aims correctly in both orientations.
- **Stereo pan**: `AudioService.panFor` uses world x, which in portrait runs vertically. Pan
  uses the world axis that runs **across the screen**: x over 720 when upright (exactly the
  original rule), y over 480 when turned. Sounds pan with what the player sees.

### 5.3 Turning the device mid-game

- The orientation lock is lifted: `SystemChrome.setPreferredOrientations` allows portrait-up
  and both landscapes (not upside-down on phones); `Info.plist` lists the same for iPhone and
  all four for iPad; Android uses `screenOrientation="fullUser"` so the player's rotation
  lock is respected.
- On a change, `HudLayout` re-resolves. The camera keeps the world point at the centre of
  the map area and the relative zoom (a fitted view stays fitted), and animates the turn
  (~250 ms).
- The game keeps running (no auto-pause; it is a casual switch). A tray drag in progress is
  cancelled; a selected turret stays selected and its panel reopens in the new layout; an
  armed tap-to-build stays armed.
- Desktop and web need nothing special: resizing a window to tall triggers the same switch.

### 5.4 The rest of the app

The home screen (`lib/features/menu/home_screen.dart`) and every Phase 5 screen (mode, map
and challenge pickers, settings, sandbox options, game over) are built responsive from the
start: one layout that reflows by width breakpoint, tested in both orientations. Cheaper
than retrofitting, since most of those screens do not exist yet.

## 6. Minimum touch-target size

The default view stays **fit** (whole road visible), because a tower-defence player must see
the whole road. Small screens are handled in input, not by zooming in by default:

1. **Turret hit radius in screen space.** `turretAt` gets a minimum radius:
   `max(turretSpacing / 2, 22 pt / zoom)`, with the nearest turret winning. Turrets are at
   least 36 world px apart, so each owns a tap zone at least ~30 pt across even on the
   smallest phone, and an ambiguous tap still picks one turret. Presentation only; no rule
   changes.
2. **Ghost above the finger.** On touch input (not mouse), a tray drag draws the placement
   ghost and range circle ~40 pt above the finger (screen up, in either orientation) so the
   finger does not hide the spot being judged. The build command uses the ghost's position,
   so what you see is what is built. Tap-to-build is unchanged.
3. **HUD hit targets checked by tests.** Widget tests run Flutter's
   `meetsGuideline(iOSTapTargetGuideline)` and `androidTapTargetGuideline` on the game
   screen at every golden size, so a cramped control fails CI rather than a playtest.
4. **Pinch, double-tap 2× and the zoom buttons stay** for players who want bigger targets.

## 7. Empty bands and sharp ground

### 7.1 Ground beyond the play area

A `GroundComponent` replaces the plain ground sprite:

- inside 720×480 it draws the ground exactly as today (unchanged look);
- outside it continues the same image with **mirror tiling** (`ImageShader` with
  `TileMode.mirror`), which has no seams even though the original texture does not tile;
- it covers the rig's visible rect each frame (cheap: one shader-filled rect), so any
  aspect ratio, orientation, margin pan or zoom shows ground rather than flat colour.

### 7.2 The playable edge stays clear

Placement is restricted to the play area, so the outside must read as "not here":

- an `offMap` tint (`PackTheme.offMap` at ~45 % opacity) over everything outside 720×480;
- a thin border on the play-area edge. The original draws border lines there (shape 1139,
  depth 157, `ENGINE_NOTES.md` §8.5), so this is also more faithful.

### 7.3 Sharp ground

The source has no more detail to give (§2.7). Chosen (D3): a **procedural ground** drawn by a
fragment shader (`dart:ui` `FragmentProgram`, no new package) painting dirt/grass noise in
world coordinates, colour-matched to the classic ground. It is sharp at any zoom and density,
infinite and seamless (so it also fills bands), and turns with the view like everything
else. Risks to measure: web renderer support and low-end Android frame time; if needed, cache
it to an image per zoom step.

It ships through the asset-pack seam (`docs/REMASTER_PLAN.md` §5.2): the world still names
`ground.classic`, and the pack decides how it is drawn. Today `AssetPack` only returns sprite
frames, so it gains a ground resolver returning a sealed `GroundSource`:
`ImageGround(SpriteFrame)` or `ShaderGround(assetPath, uniforms)`. The classic pack keeps
returning the original image; the sharp ground lives in a `procedural` pack layered in front
through `AssetPackChain`, behind a **Ground: Classic / Sharp** setting (classic is the v1
default).

The original's two ground decorations (the translucent tan patch, shape 1026, and the line
decoration, shape 1024) are vector shapes, so the sharp ground draws them as vector too.

Quick win regardless: check the Flame ground sprite's `FilterQuality` and set it to `medium`
so the classic ground's magnification is smooth rather than blocky.

### 7.4 Not in this plan: sprite density (D6)

Turrets, creeps and the base are vector shapes in the SWF and are exported at 1×/2×/3×, and
`ClassicAssetPack.preferredScale` is fixed at 3. On a tablet at maximum zoom they look soft.
A 4× export (picking the density from `devicePixelRatio × maxZoom`) is a small
`ffdec-asset-export` job, left out by the owner's decision.

**Done separately (2026-10-19, outside this plan):** the owner later asked for art that stays
sharp at every zoom and screen. The classic pack now ships atlases at 1×, 2×, 3×, 4×, 6× and
9× (`tool/export_assets.sh`, `SCALES`); every `SpriteFrame` lists its densities and
`atDensity(zoom × devicePixelRatio)` picks the sparsest one at least that sharp. In game,
`ArtResolver` keeps the 3× pages loaded as the fallback, loads a denser page the first time a
sprite on it needs it, draws the sharpest page it already has meanwhile, and releases pages
no sprite has drawn for 3 s. `PackSprite` picks its density from its size × device pixel
ratio. Sprites (the ground included) are drawn with `FilterQuality.medium`, which also covers
the §7.3 quick win. The ground stays capped at 3× (a bitmap source, item 7 in §2). The nine
creeps are bitmaps too (17×18 and 24×24 px, not vector), so no export adds detail; Classic
keeps them as they are. After comparing smoothed, crisp-pixel, xBR/hqx and AI upscales, the
owner chose vector redraws (darker-shade outlines, gradient fills) for **Enhanced games
only**: `tool/art/creeps/creep.N.svg`, packed from `tool/asset_map_enhanced.json` into the
Enhanced asset pack (`assets/images/enhanced/`, `[enhanced, classic]`), rendered with
`rsvg-convert` into the frames FFDec exported, so sizes and registration points match.

## 8. Unsupported shapes

With portrait supported, "unsupported" only means a window too small for any layout: no
candidate gives a turret of at least ~20 pt at fit (for example a desktop window dragged very
small). The game auto-pauses and shows **"Make the window bigger"**, and resumes when the
shape becomes playable. This uses the pause path from `docs/REPLAY_PLAN.md` §7 if it has
landed, otherwise a local pause. Phones and tablets never hit it.

## 9. Testing

- **Unit**: `HudLayout` over a device matrix in both orientations (chosen kind and turn,
  hysteresis, no HUD over the fitted map, minimum turret size, `unsupported` thresholds);
  `CameraRig` with insets on all four edges and with `mapTurns` 0 and 1 (`screenToWorld` after
  `worldToScreen` is the identity, fit and clamp match the swapped axes, turning keeps the
  centre world point and relative zoom); the screen-space hit radius; audio pan from the across-screen axis.
- **Widget**: `GameScreen` at every golden size: overlays do not overlap each other,
  tap-target guidelines pass, a drag released over any HUD region cancels, the turret panel
  opens on the far side; a resize from landscape to portrait mid-game keeps the selection
  and cancels a drag.
- **Golden**: the game screen in all layouts; `GroundComponent` with margin, tint and border;
  the turret panel on both sides; `WorldLabel` upright in a turned view. Sizes (D5, extended
  for portrait): today's four plus iPhone SE 667×375, iPad 10th gen 1180×820, a 1440×900
  laptop, and portrait iPhone 17 Pro 402×874, iPhone SE 375×667 and iPad Pro 11" 834×1210.
- **Manual QA** (`ios-simulator-qa`, `android-emulator-qa`, `flutter-run-and-hot-reload` for
  web and macOS, reported with `qa-report`): rotate iPhone and iPad simulators and the Pixel
  AVD mid-wave in both directions; Chrome device emulation in both orientations; a macOS
  window dragged through every shape.
- **Performance**: frame time of the procedural ground and of the turn animation on the Pixel
  AVD and a real mid-range Android (the emulator alone is not representative).
- **Replays and fixtures**: a scenario that rotates mid-game must produce the same event log
  as one that does not (proves the turn never reaches the simulation).
- `fvm flutter analyze`, `fvm flutter test` and the core tests on every step. Fixtures do
  not change; if one does, something leaked into the simulation.

## 10. Build order (small, finished steps)

Each step compiles, passes tests and leaves the game shippable. Steps 1–7 are best done soon
after Phase 1 lands, before Phases 2–5 add more HUD and screens, so those are built for
every layout from the start. Steps 9–10 fit Phase 8 (polish) or earlier.

1. **`HudLayout` with `bars` only.** Move the overlay positions, rig insets (all four safe
   edges) and `dragTo` onto it, with a `mapTurns` field fixed at 0. No visible change except
   the safe-area fix. Measure the real safe areas on the simulators and correct §2's table.
2. **`rails` layout** and the zoom-based chooser with hysteresis; `StatsBar` with an axis.
3. **Quarter-turn camera**: `mapTurns` in `CameraRig`, the viewfinder angle, `WorldLabel`,
   audio pan from the across-screen axis. Tested with a forced turn; the app is still landscape-locked.
4. **`portrait` layout and the orientation unlock**: horizontal tray strip, the chooser's
   portrait candidates, platform orientation settings, live switching (§5.3), home screen
   reflow. Standards updates (§11 P3) land here.
5. **Turret panel on the far side**, in all three layouts, and the camera nudge when zoomed
   in.
6. **Touch targets**: screen-space hit radius, ghost above the finger, tap-target guideline
   tests, and fixes for any control they flag.
7. **Unsupported shapes** screen (tiny windows) with auto-pause and resume.
8. *(Phase 5, ongoing)* every new screen built responsive with goldens in both orientations.
9. **`GroundComponent`**: mirror-tiled ground beyond the play area, off-map tint, border,
   ground `FilterQuality`.
10. **`GroundSource` seam** in `AssetPack` and the procedural ground behind the setting.

Docs travel with the step that changes them (rule: docs stay in sync):

- `docs/REMASTER_PLAN.md` §0 (goals), §3.1 (bands, tint, border, layouts, view turn), §3.3
  (HUD regions per screen shape, panel placement, "Landscape only" removed), §5.2 (ground
  sources), §9 item 5 (portrait now planned);
- `.agents/architecture.md` (`HudLayout`, the view turn, `WorldLabel`, the `GroundSource`
  seam, the shader asset);
- `.agents/skills/golden-tests/SKILL.md` and `test/goldens/devices.dart` (D5);
- `.agents/skills/ios-simulator-qa/SKILL.md` and `android-emulator-qa/SKILL.md` (they say
  the game is landscape-only; add how to rotate mid-game);
- the tenet and overview wording in §11 P3.

No `docs/DEVIATIONS.md` rows: no game rule changes.

## 11. Owner decisions

### Landscape, accepted (2026-10-18)

- **D1 — Wide-screen layout:** two rails on landscape phones and 16:9 screens, chosen by fit
  zoom with hysteresis (§4.2).
- **D2 — Turret panel:** opens on the side away from the turret (§4.4); extended to portrait.
- **D3 — Sharp ground:** procedural fragment-shader ground, opt-in for v1 through a
  Ground: Classic / Sharp setting; classic stays the default (§7.3).
- **D4 — Portrait:** ~~rotate prompt~~ **superseded**: the owner wants portrait play with
  automatic switching (§4.3, §5). The prompt survives only for tiny windows (§8).
- **D5 — Golden sizes:** add the sizes in §9 to `test/goldens/devices.dart` and the
  golden-tests skill, in the step that first needs them.
- **D6 — Sprite density:** left out of this plan (§7.4).

### Portrait, accepted (2026-10-18)

- **P1 — Portrait map:** turned a quarter so it fills a portrait screen (30 pt turrets on
  phones), not upright (20 pt turrets; not playable on phones).
- **P2 — Turn direction:** fixed for every map, with the world's left edge at the bottom so
  most maps send creeps up the screen (one orientation to learn), not chosen per map.
- **P3 — Standards wording (R24).** The owner approved these changes to text they control:
  - `.agents/tenets.md` §6: "Landscape phones with touch are the primary device." →
    "Phones with touch, in portrait or landscape, are the primary device; the game adapts
    when the player turns the device.";
  - `AGENTS.md` tenet 6 summary: "Touch and landscape phones are the primary target" →
    "Touch phones in either orientation are the primary target", and "a touch-first
    landscape UI" → "a touch-first UI for portrait and landscape";
  - `.agents/project-overview.md`: "(primary, landscape only)" → "(primary, portrait and
    landscape)".
  Applied in step 4, together with the orientation unlock (done 2026-10-19).

### Implementation, accepted (2026-10-19)

- **P4 — Classic landscape is frozen:** visually and mechanically identical to v1 (proven by
  the unchanged CI goldens and the classic layout guard test). Classic gets portrait, the
  portrait HUD, live switching, the orientation unlock, responsive menus/editor/mods and the
  safe-area fixes. Rails (§4.2), the far-side panel in landscape (§4.4), ground beyond the
  play area in landscape (§7.1–7.2), sharp ground (§7.3), the ghost lift and the bigger
  turret hit zone (§6.1–6.2) are **Enhanced only**, gated by `UiSkin`.
- **P5 — Portrait map upright, filling the screen (supersedes P1 and P2):** the map is not
  turned; its home view covers the space between the stats bar and the tray strip (the
  play area's height fits, its width is cropped) and the player pans along it, pinches out
  to the whole map, or double-taps between the two.
- **P6 — Ground beyond the map in Classic portrait:** the ground runs on past the play area
  (mirror-tiled, tinted, with the border) whenever the view fills a portrait screen, in
  Classic too; Classic landscape keeps the plain off-map colour.
- **P7 — The map editor follows the same rule** (upright, filling, panned in portrait).
- **P8 — No orientation setting:** the app follows the device. No turn animation (nothing
  turns any more); `UIRequiresFullScreen` is set on iPad for v1.

## 12. Files

New:

- `lib/features/game/layout/hud_layout.dart` — `HudLayout`, `HudLayoutKind`, `HudMetrics`
- `lib/features/game/hud/stats_bar.dart` — `StatsBar` (from `top_bar.dart`), horizontal or
  vertical
- `lib/features/game/hud/unsupported_shape.dart` — "make the window bigger" prompt
- `lib/app/ui_skin.dart` — `UiSkin` (Classic / Enhanced presentation)
- `lib/features/game/flame/ground_component.dart` — ground beyond the play area (mirror
  tiling), the shader ground, the off-map tint and border
- `GroundSource`, `ImageGround`, `ShaderGround` live in `lib/services/assets/asset_pack.dart`
- `shaders/ground.frag` + `lib/services/assets/procedural_ground_pack.dart`
- `test/features/game/layout/hud_layout_test.dart`, `classic_layout_guard_test.dart`,
  `test/features/game/view_shape_sim_test.dart`, goldens under `test/goldens/game/`

Changed:

- `lib/main.dart`, `ios/Runner/Info.plist`, `android/app/src/main/AndroidManifest.xml` —
  orientation unlock
- `lib/features/game/game_screen.dart` — overlays and `dragTo` from `HudLayout`
- `lib/features/game/hud/top_bar.dart`, `tower_tray.dart`, `turret_sheet.dart` — layout-aware
  (the tray gains a horizontal strip form)
- `lib/app/camera_rig.dart` (shared with the editor) — insets on all edges, the filled home
  view, panel nudge, `panToShow`
- `lib/features/game/flame/onslaught_flame_game.dart` — `setLayout`, ground components,
  hit radius
- `lib/features/game/game_view_model.dart` — `turretAt` minimum radius
- `lib/features/menu/home_screen.dart` — reflows in portrait
- `lib/services/assets/asset_pack.dart`, `classic_asset_pack.dart` — ground resolver
- settings screen and persistence — the Ground setting
- `pubspec.yaml` — `flutter: shaders:` entry
