# Portrait mode and screen fit — implementation plan

Status: **implemented 2026-10-19**, with one owner change made while building it: the
portrait map is **upright and fills the screen** (the player pans along it and pinches out to
see it all) instead of turned a quarter, and the ground runs on past the map in Classic
portrait too (`docs/SCREEN_FIT_PLAN.md` §11 P5–P6). So §2's quarter turn, `Upright` /
`WorldLabel`, the turned audio pan axis, the editor's turned canvas and the turn-animation
question were dropped; `CameraRig` gained a `fill` home view instead. Other deviations from
the text below: `UiSkin.offersRails` instead of a `layoutKinds` set (lib/app must not import
a feature's enum); a portrait layout is a candidate only on screens taller than wide (an
upright map makes the bottom strip win on squares otherwise); the compact sheet's four action
buttons go two by two below 440 wide (not 300) so Move and Sell keep their prices readable;
dialogs keep their fixed widths (a `SizedBox` width already shrinks to a narrow dialog, and
`ConstrainedBox` would have re-laid-out landscape goldens) and gain a 16 px margin below 480
wide; the editor's help stays an inline panel (full width above the strip) rather than a
bottom sheet. Originally: drafted 2026-10-19, awaiting the owner's go-ahead. Companion to
[SCREEN_FIT_PLAN.md](SCREEN_FIT_PLAN.md) (the approved design): this document turns it into build
steps against the Phase 8 code, adds the owner's 2026-10-19 decisions (whole plan in scope, Classic
landscape frozen, Enhanced-only extras behind a `UiSkin` seam, the editor turns too, no orientation
setting) and corrects the design doc where today's code differs from it.

## Context

The game is locked to landscape in four places (`lib/main.dart`, `ios/Runner/Info.plist`,
`AndroidManifest.xml`, `web/manifest.json`) and the in-game HUD is placed by three constants
(`TopBar.height` 48, `TowerTray.width` 76, `TurretSheet.height` 112) hard-coded in
`lib/features/game/game_screen.dart:424-548`. Nothing reads orientation.

`docs/SCREEN_FIT_PLAN.md` (approved 2026-10-18, commit `308a7e0`, **not started**) already
designs portrait + landscape screen fit, and the owner's decisions there stand:
**P1** portrait turns the map a quarter (upright gives 20 pt turrets, unplayable);
**P2** the world's left edge goes to the screen bottom (creeps march up on 8 of 13 maps);
**P3** pre-approved wording changes to tenets/AGENTS/overview; **D1–D5** rails, far-side
panel, sharp ground, golden sizes.

Owner decisions in this session (2026-10-19):
1. **Scope = the whole screen-fit plan** (all ten steps).
2. **Classic landscape must not change**, visually or mechanically. Classic gets portrait,
   the portrait HUD, live switching, the orientation unlock, responsive menus/editor/mods
   and safe-area fixes. Everything else (rails, far-side panel in landscape, ground tiling/
   tint/border, sharp ground, ghost lift, bigger hit radius) is **Enhanced only**.
3. The **map editor canvas also turns** a quarter in portrait.
4. **No orientation setting**; the app follows the device.

Enhanced mode does not exist in code yet (`docs/ENHANCED_PLAN.md` E0 unstarted;
`RulesProfile` has only `classic`/`classicFixed`; `lib/app/providers.dart:165` pins
`classicFixed`). `UiSkin` is named as the seam in `docs/REMASTER_PLAN.md` §5.3 but has no
code. This plan creates it so the Enhanced-only work can land now, gated, and E0 later
selects it with no further change.

Nothing in `packages/onslaught_core`, `assets/data` or the regression fixtures changes.
Note: the screen-fit plan's §12 puts `CameraRig` under `lib/features/game/camera/`; it
actually lives at `lib/app/camera_rig.dart` (shared with the editor). Fix the doc.

---

## 1. The gating seam: `UiSkin` (new `lib/app/ui_skin.dart`)

```dart
enum UiSkin {
  classic, enhanced;
  static UiSkin forProfile(RulesProfile p) => p.id == 'enhanced' ? enhanced : classic;
  Set<HudLayoutKind> get layoutKinds => this == classic ? {bars, portrait} : {bars, rails, portrait};
  bool get farSidePanelInLandscape => this == enhanced;
  bool get groundBeyondPlayArea => this == enhanced;   // tiling, tint, border, FilterQuality
  bool get sharpGroundOffered => this == enhanced;
  double get ghostLiftPt => this == enhanced ? 40 : 0;
  double get turretHitPt => this == enhanced ? 22 : 0; // 0 = today's 18 world px only
}
```

- `FeatureFlags` (`lib/app/feature_flags.dart`) gains `enhancedSkin` from
  `--dart-define=ENHANCED_SKIN=true` (default false) so QA and goldens can exercise the
  Enhanced skin before E0 lands. Document beside `DEBUG_OVERLAY` in `.agents/workflow.md`.
- `uiSkinProvider` in `providers.dart` (flag, else `forProfile(rulesProfileProvider)`) for
  menus, attract view and settings. In `_GameViewState` the skin comes from
  `GameConfig.profile` per game, so an E0 Enhanced game picks the skin automatically.
- Widgets, `HudLayout.resolve`, `OnslaughtFlameGame` and the editor take the skin as a value.

**Classification of ambiguous items** (default: gate anything visible in a Classic landscape
golden or that changes where a Classic action lands):

| Item | Skin | Why |
|---|---|---|
| Safe-area insets on all four edges (today only top+right, `game_screen.dart:453-455`) | both | bug fix; goldens have zero padding so none moves |
| StatsBar / TurretSheet compact forms below **560 pt** width | both | never triggers in landscape (narrowest: iPhone SE 667 − 76 tray = 591); portrait phones are 375–430 |
| Portrait sheet at the top when the turret is low on screen | both | portrait is new for Classic; no precedent to preserve |
| Unsupported-shape prompt + auto-pause (tiny desktop windows) | both | no phone/tablet produces it; unplayable there today anyway |
| Turret hit radius `max(18 world px, 22 pt / zoom)` | **Enhanced** | changes which turret (or empty ground) a Classic tap picks; one constant to flip if the owner wants it in Classic |
| Ghost 40 pt above the finger | **Enhanced** | changes where a Classic drag-build lands |
| Ground `FilterQuality.medium`, tiling, tint, border, sharp ground | **Enhanced** | visible in Classic landscape |
| `rails` layout, far-side panel in landscape | **Enhanced** | owner |

---

## 2. `CameraRig` quarter turn (`lib/app/camera_rig.dart`)

Verified against Flame 1.38.2 (`viewfinder.dart:63-67`, `transform2d.dart:170-183`): the
viewfinder draws `screen = C + R(−angle) · zoom · (w − center)`. P2 (world +x → screen up)
needs **`camera.viewfinder.angle = +π/2`** for `mapTurns = 1`. Check: world (0,0) lands
bottom-left, (0,480) bottom-right, so the world's left edge spans the screen bottom.

The turn is two exact axis swaps, no trigonometry:

```dart
int mapTurns = 0;                                    // 0 or 1
double get viewAngle => mapTurns * math.pi / 2;
Offset _turn(Offset w)   => mapTurns == 0 ? w : Offset(w.dy, -w.dx);   // world dir → screen dir
Offset _unturn(Offset s) => mapTurns == 0 ? s : Offset(-s.dy, s.dx);   // screen dir → world dir
Offset turnToWorld(Offset s) => _unturn(s);                            // editor arrow keys

static double fitZoomFor(Size viewport, EdgeInsets insets, int turns, Size world); // HudLayout uses it
double get fitZoom => fitZoomFor(viewport, insets, mapTurns, world.size); // turned: min(free.h/720, free.w/480)
Rect get visible   => turned ? (viewport.height/zoom × viewport.width/zoom) : today
Offset get _freeOffset => _unturn(free.center - viewport.center) / zoom;
void panBy(Offset d) { center -= _unturn(d) / zoom; _clampCenter(); }
void zoomAbout(z, focal) { anchor = screenToWorld(focal); zoom = clamp; center = anchor - _unturn(focal - vc) / zoom; _clampCenter(); }
Offset screenToWorld(p) => center + _unturn(p - vc) / zoom;
Offset worldToScreen(w) => _turn(w - center) * zoom + vc;
_clampCenter(): halfW/halfH from the free extent measured along world axes (swapped when turned).
void applyTo(Canvas c) => c..translate(vw/2, vh/2)..rotate(-viewAngle)..scale(zoom)..translate(-center); // editor painters
```

**Order-independent reframe.** A rotation reaches the rig as `setInsets`/`setMapTurns` (from
`_buildGame`, new MediaQuery) and `onGameResize` (when the `GameWidget` lays out), in either
order. Route all three through one `_reframe(mutate)`: remember `wasFit`, `relativeZoom` and
`seen = center + _freeOffset` (world point at the centre of the map area), mutate, then
`fit()` if it was fitted, else restore relative zoom and `center = seen − _freeOffset`. This
is §5.3 of the screen-fit plan by construction; today's `resize` test still passes.

Flame side (`lib/features/game/flame/onslaught_flame_game.dart`):
- `_applyCamera()` adds `..angle = rig.viewAngle`; `CameraReadout` gains `mapTurns`.
- `setLayout(HudLayout)` replaces `setHudInsets`: sets insets + turns, pushes `viewAngle` to
  `EntityLayer`, re-applies the camera.
- `CameraInputLayer` needs **no change**: all its deltas/positions are viewport coordinates
  and the rig turns them.
- **No turn animation in the first ship** (deviation from §5.3 "animates the turn", flag for
  the owner): an animated viewfinder angle over a discrete rig turn would misplace taps for
  250 ms, and the OS already animates the window rotation. Revisit on device (step 14).

### World drawing that must stay upright
New `lib/features/game/flame/world_label.dart`: `Upright` (a `PositionComponent` that sets
`angle = -layer.viewAngle` each update) and `WorldLabel` (upright text) for any future
world text. `EntityLayer` gets `double viewAngle`. Apply counter-rotation to:
- colour-badge letter (`entity_layer.dart:289-295`, drawn via `paintColourBadge`): rotate
  before the (12, −12) offset so it stays at the turret's **screen** top-right;
- creep HP bar (`entity_layer.dart:249-259`): stays a horizontal bar above the creep;
- freakout warning sprite at (0, −24) (`entity_layer.dart:429-442`): parent under `Upright`.
- Everything else (range circles, ghost, beams, combo signs, smoke, road, ground, base) turns
  with the world as intended.

Audio: `AudioService.panFor` (`lib/services/audio/audio_service.dart:83-87`) takes the cue
position + `mapTurns`: upright uses x/720 (unchanged rule), turned uses y/480. `GameAudio`
passes the position; `_GameViewState` sets `mapTurns` from the layout.

---

## 3. `HudLayout` (new `lib/features/game/layout/hud_layout.dart`, pure Dart, no Flame)

```dart
enum HudLayoutKind { bars, rails, portrait, unsupported }
abstract final class HudMetrics { statsBarHeight 48, trayRailWidth 76, trayStripHeight 88,
  sheetHeight 112, sidePanelWidth 240, compactBelow 560, hysteresis 0.05, minTurretPt 20 }

class HudLayout {
  static HudLayout resolve(Size screen, EdgeInsets safe, {required UiSkin skin, HudLayoutKind? previous});
  final HudLayoutKind kind; final int mapTurns; final UiSkin skin;
  final Rect stats, tray, map;          // overlay rects; `map` is what the rig fits into
  final Axis trayAxis, statsAxis;       // tray: vertical (bars/rails) | horizontal (portrait)
  final double fitZoom;
  EdgeInsets get mapInsets;             // → CameraRig.setInsets (all four edges)
  bool isOverHud(Offset p) => stats.contains(p) || tray.contains(p);
  SheetEdge sheetEdgeFor(Offset? turretScreen);  Rect panelFor(Offset? turretScreen);
  Rect get hint, toasts, objectives, tutorialWindow;   // derived from `map`
}
```

- **Chooser**: candidates `(bars,0)`, `(portrait,1)` and, Enhanced only, `(rails,0)`; each
  scores `CameraRig.fitZoomFor(...)`; largest wins; keep `previous` if within 5 %; if the
  best gives a turret under 20 pt → `unsupported` (keeps the last good rects). No orientation
  flags, no device lists. Sanity: 923×411 → bars (Classic) / rails (Enhanced); 402×874 →
  portrait (0.84 vs 0.45); 834×1210 → portrait; 1210×834 → bars (1.575 beats rails 1.47).
- **Classic `bars` reproduces today's numbers exactly** (`mapInsets = top 48+safe, right
  76+safe`) plus the two missing safe edges. A **classic layout guard test** pins this.
- Rects: bars/portrait `stats = (0,0,w,48+safe.top)`; rails `stats = (0,0,76+safe.left,h)`;
  tray rail `(w−76−safe.right, stats.bottom, w, h)`; portrait strip `(0, h−88−safe.bottom, w, h)`.

### `GameScreen` refactor (`lib/features/game/game_screen.dart`)
- `_buildGame`: `layout = HudLayout.resolve(MediaQuery.sizeOf, padding, skin, previous)`;
  `_game.setLayout(layout)`; `_sound.mapTurns`; `_onLayoutChanged(prev, next)`.
- Every overlay (lines 463-548) positions from layout rects: stats, tray (`axis`), sheet
  (`panelFor` + `edge`), placement hint / toasts / objectives / custom label relative to
  `map`, tutorial `window`, game-over unchanged.
- `dragTo` (424-433): `overHud = layout.isOverHud(local)`; build point = finger lifted by
  `skin.ghostLiftPt` when the pointer is touch; release over any HUD rect still cancels.
- In-game settings dialog (346-371): `maxWidth: 420` instead of fixed width.

### Mid-game rotation
- Trigger: `_buildGame` reading `MediaQuery.sizeOf` makes any rotation rebuild `_GameView`;
  Flame's `GameWidget` rebuilds overlays on every build; `_reframe` makes call order harmless.
- `_onLayoutChanged` when kind/turns differ: a tray drag in progress → `cancelPlacement()`
  and `_dragIgnored = true` so the recognizer's end/cancel (fired when the cell's gesture
  axis switches) cannot `commitPlacement` (today `dragEnd` commits whenever `placement.at !=
  null`, `game_screen.dart:436-441`, which would build a turret on rotation); an armed
  tap-to-build stays armed; selection lives in the view model and survives; the sheet edge is
  recomputed post-frame from `rig.worldToScreen(turret.position)`; `HudKeys` are GlobalKeys
  so "Show me" arrows follow.

---

## 4. HUD widgets

- **`StatsBar`** (rename `hud/top_bar.dart` → `hud/stats_bar.dart`, `axis` param):
  *wide* (≥ 560) = today's row, byte-identical; *compact* (portrait phones) drops the map
  name and kills readout, short cash format (move `_short` from `turret_sheet.dart:283-288`
  to `hud/format.dart`), wave as icon + number (same semantics label), readouts in one
  `FittedBox`; *vertical* (Enhanced rails) = a scrolling `Column`. Tap targets never shrink.
- **`TowerTray(axis)`** (`hud/tower_tray.dart`): `ListView(scrollDirection: axis)`; strip is
  88 tall with `SafeArea(top: false)`; strip cells 64×72 use `onVerticalDrag*` (vertical-first
  so the strip still scrolls horizontally; the rail keeps `onHorizontalDrag*`). Record
  `DragStartDetails.kind`; `PlacementInput.dragTo(id, pos, {bool touch})`. Rail unchanged →
  `tower_tray.png` identical.
- **`TurretSheet`** (`hud/turret_sheet.dart:83-231`, needs ≥ 560 wide today): extract
  `_InfoBlock`; `LayoutBuilder` → wide row (unchanged) or *compact column*: info + close /
  three upgrade buttons / target, lock, move, sell (2×2 under 300) / one row per special
  card. Intrinsic height. New `edge` (bottom/top/left/right) only flips corners/border;
  default bottom keeps goldens. Target-mode picker (`showModalBottomSheet`) works as is.
- **`TutorialPanel`**: takes `window: Rect` from the layout (portrait: full width at the top,
  ≤ 40 % of map height; the road starts at the bottom there). Arrow painter unchanged.
- **`GameOverPanel`**: `width = min(320/360, maxWidth − 32)`; existing scroll handles 667 tall.
- `MessageToasts`, `ObjectiveBadges`, `_PlacementHint`, `_CustomLabel`: positions only.

---

## 5. Non-game screens (must work at 375×667, 402×874, 834×1210)

| Screen | Change |
|---|---|
| `menu/home_screen.dart` | none; `attract_view.dart` picks `mapTurns` by comparing `fitZoomFor` upright vs turned so the demo fills a portrait home |
| `menu/mode_screen.dart:140-144` | fixed `mainAxisExtent: 72`, 1 col < 420, 2 < 560, else 3 (survives 1.3× text) |
| `menu/map_screen.dart:57-61`, `editor/map_library_screen.dart:213` | 2 cols < 480, 3 < 700, else 4 |
| `menu/challenge_screen.dart:112-176` | `LayoutBuilder`: < 640 stacks the 270-wide side panel's children above the pickers in one `ListView`; `_Picker` label `min(120, 0.35w)`; at 874 the Row stays → golden unchanged |
| `mods/mods_screen.dart:224-237` | < 600: single-pane drill-down (items → fields → value) reusing `_itemList/_fieldList/_valuePane`, back row + `PopScope`; tablet portrait keeps three panes |
| `app/dialogs.dart:22`, `editor_dialogs.dart:77,177`, `mod_dialogs.dart:79,194` | `ConstrainedBox(maxWidth: N)` instead of fixed `SizedBox(width)`; `CompactDialog.insetPadding` 16 below 480 |
| settings, records | nothing (verified by the accessibility matrix) |

### Map editor turns too (`editor/editor_canvas.dart`, `editor/map_editor_screen.dart`)
- Portrait when `fitZoomFor(portrait insets, turns 1) > fitZoomFor(landscape, 0)` (same rule
  as the game, in `_EditorState.build`, lines 258-284); `EditorCanvas(mapTurns)` calls
  `rig.setMapTurns` beside `rig.setInsets` (163-164).
- `_rail()` (397-470) → `_palette(Axis)`: same children in a horizontal scroll row 76 tall at
  the bottom. Top bar (335-395) overflows at 375: below 600 wide fit/help/share go into a
  `PopupMenuButton` (new key `ui.editor.more` + `l10n/de.json`), Play becomes an IconButton.
  Help opens as a `showModalBottomSheet` in portrait (the 300-wide panel stays in landscape).
  Status pill above the strip.
- Drawing: `EditorPainter.paint` (313-316) uses `rig.applyTo(canvas)`; `EditorHandlesPainter`
  already draws in screen space via `worldToScreen` → handles/flags/"+" stay upright;
  `_ground()`/`_baseSprite()` (220-258) move into one `Positioned.fill(Transform(rig matrix))`
  so they share the turn. Pointers already go through the rig. Arrow-key nudges (241-248)
  use `rig.turnToWorld` so "up" nudges toward the top of the screen in both orientations.
- Thumbnails (`app/map_thumbnail.dart`) stay upright everywhere.

---

## 6. Orientation unlock

- `lib/main.dart:12-16`: `[portraitUp, landscapeLeft, landscapeRight]` + `portraitDown` when
  the shortest side ≥ 600 (tablets); drop the "Landscape only" comment.
- `ios/Runner/Info.plist:61-70`: iPhone = Portrait + both landscapes; iPad = all four.
  **Recommend `UIRequiresFullScreen = true`** for v1 (otherwise all-four-orientations makes
  the iPad app Split View/Stage Manager resizable down to ~320 wide, untested); owner's call.
- `android/app/src/main/AndroidManifest.xml:7`: `screenOrientation="fullUser"` (respects the
  player's rotation lock); `configChanges` already covers orientation → resize, not restart.
- `web/manifest.json:9`: `"orientation": "any"`.
- `SystemUiMode.immersiveSticky` stays; cutout/notch and home indicator still report in
  `MediaQuery.padding`, so the stats bar clears the notch and the strip's `SafeArea` keeps
  cells above the home indicator; the map draws under both (decoration).
- Desktop: no minimum window size exists anywhere; nothing to change (tiny → `unsupported`).

---

## 7. Enhanced-only work (after portrait ships)

- **Rails** (§4.2 of the screen-fit plan): vertical `StatsBar`, `rails` candidate under
  `skin.layoutKinds`.
- **Far-side turret panel in landscape** (§4.4): `sheetEdgeFor/panelFor` for bars
  (top/bottom by turret position) and rails (240-pt side panel = compact sheet form);
  `rig.ensureVisible(worldPoint, keepOut)` nudge when zoomed in.
- **`GroundComponent`** (§7.1–7.2): `GroundSource` seam (`AssetPack.ground(id)` →
  `ImageGround`; ~15 test fakes gain the method in one commit), mirror-tiled ground over
  `rig.visible`, `offMap` tint 45 %, play-area border, `FilterQuality.medium`. Classic keeps
  the plain sprite (`onslaught_flame_game.dart:85-97`).
- **Sharp ground** (§7.3): `shaders/ground.frag` (+ `pubspec flutter: shaders:`),
  `ProceduralGroundPack` returning `ShaderGround`, `Settings` v4 `sharpGround` (+ migration,
  `settings.v3.json` fixture, `ui.settings.ground*` + de), settings row shown only under the
  Enhanced skin (so invisible until E0 or the dart-define), pack chain `[procedural?,
  classic]` applied from the next game like mods. Measure frame time on the Pixel AVD and a
  real Android; fall back to an image cache per zoom step if needed.

---

## 8. Build order (each step compiles, tests pass, Classic unchanged, shippable)

| # | Step | Size | Main files |
|---|---|---|---|
| 1 | **Foundations**: `UiSkin`, `FeatureFlags.enhancedSkin`, `HudLayout` with `bars` only (`mapTurns` 0), `HudMetrics`; `GameScreen` overlays/insets/`dragTo` from it; classic guard test; `hud_layout.png` composed-HUD golden baseline | S–M | `ui_skin.dart`, `hud_layout.dart`, `feature_flags.dart`, `providers.dart`, `game_screen.dart`, `onslaught_flame_game.dart` |
| 2 | **Camera turn**: rig `mapTurns`/`fitZoomFor`/`_reframe`/`applyTo`/`turnToWorld`; viewfinder angle; `Upright`/`WorldLabel`; badge, HP bar, warning; audio pan axis; rig/Flame/sim-equivalence tests. App still landscape-locked | M | `camera_rig.dart`, `onslaught_flame_game.dart`, `camera_controls.dart`, `entity_layer.dart`, `world_label.dart`, `audio_service.dart`, `game_audio.dart` |
| 3 | **HUD portrait forms**: `StatsBar` compact, `TowerTray(axis)`, `TurretSheet` compact + `edge`, `hud/format.dart`; goldens at portrait widths | M | `stats_bar.dart`, `tower_tray.dart`, `turret_sheet.dart` |
| 4 | **Portrait in the game**: `portrait` candidate + chooser/hysteresis; every overlay per layout; sheet top/bottom; rotation handling; attract turn; dialog widths; `GoldenDevices` portrait sizes; portrait + rotation widget tests | L | `hud_layout.dart`, `game_screen.dart`, `tutorial_panel.dart`, `game_over_panel.dart`, `attract_view.dart`, `test/goldens/devices.dart` |
| 5 | **Non-game screens** responsive + portrait goldens | M | mode/map/challenge/map-library/mods screens, dialogs |
| 6 | **Editor portrait**: canvas turn, palette strip, overflow menu (+`ui.editor.more`, de), help sheet, nudges | M | `editor_canvas.dart`, `map_editor_screen.dart`, `ui_strings.dart` + regen |
| 7 | **Unlock + standards**: platform files; P3 wording; docs/skills (§10 below); accessibility matrix with portrait sizes. **Ships portrait for Classic and Enhanced** | S–M | `main.dart`, `Info.plist`, `AndroidManifest.xml`, `web/manifest.json`, docs |
| 8 | **Touch targets** (Enhanced): `turretAt(minRadius)` plumbing (classic passes 0), ghost lift; tap-target guideline tests on the game screen at every size (both skins) | S | `game_view_model.dart`, `onslaught_flame_game.dart`, `game_screen.dart`, fakes |
| 9 | **Unsupported shapes** (both): `unsupported` kind, "Make the window bigger" overlay (`ui.game.windowTooSmall` + de), auto-pause/resume respecting a player's own pause | S | `hud_layout.dart`, `hud/unsupported_shape.dart`, `game_screen.dart` |
| 10 | **Enhanced rails** | M | `hud_layout.dart`, `stats_bar.dart`, `game_screen.dart` |
| 11 | **Enhanced far-side panel** + camera nudge | M | `hud_layout.dart`, `game_screen.dart`, `turret_sheet.dart`, `camera_rig.dart` |
| 12 | **Enhanced `GroundComponent`** + `GroundSource` seam | M | `asset_pack.dart`, `classic_asset_pack.dart`, `ground_source.dart`, `ground_component.dart` |
| 13 | **Enhanced sharp ground** + Ground setting (Settings v4) | L | `settings.dart`, `settings_form.dart`, `providers.dart`, shader, new pack |
| 14 | *(optional, after device QA)* turn animation; `UIRequiresFullScreen` revisit | S | |

Reuse: `CameraRig` (already the single conversion point for game and editor),
`_UpgradeButton/_SmallButton/_TargetChip/_SpecialCardView`, `PackSprite`, `CompactDialog`,
`FakeGameViewModel`, the `flame_game_test` pump harness, `canonicalJson` from core testing,
alchemist `GoldenTestGroup` patterns, `SystemBack`.

---

## 9. Verification

**Unit**
- `test/features/game/layout/hud_layout_test.dart`: matrix {874×402, 402×874, 923×411,
  411×923, 667×375, 375×667, 1210×834, 834×1210, 1280×720, 600×900, 800×800, 300×200} ×
  typical safe insets × both skins → kind, turns, rects disjoint, `mapInsets` ⇔ `map`,
  `isOverHud`, `fitZoom` equals a `CameraRig` with the same insets/turn, hysteresis on a
  760×740 window, `unsupported` at 300×200, turret ≥ 24 pt on every phone.
- `classic_layout_guard_test.dart`: every landscape golden size under `UiSkin.classic`
  resolves to bars, turns 0, `mapInsets == EdgeInsets.only(top: 48, right: 76)`.
- `test/app/camera_rig_test.dart`: with `mapTurns = 1`: fit maps world (0,240) to the free
  bottom and (720,240) to the free top; round trip identity; `panBy` sign; `zoomAbout` keeps
  the focal world point; swapped clamps; `setMapTurns` keeps the seen centre and relative
  zoom; the six orderings of `resize/setInsets/setMapTurns` end in the same state.
- `flame_game_test.dart`: `viewfinder.angle == π/2` after a turned layout and
  `viewfinder.localToGlobal` agrees with `rig.worldToScreen` (sign proof); a tap at
  `worldToScreen(turret)` selects it in a turned view; badge/HP-bar upright golden.
- `view_turn_sim_test.dart`: the same scripted game (build, send wave, select, upgrade,
  sell via screen taps) with turns 0, turns 1 and switching mid-script produces an identical
  `canonicalJson` event log → the turn never reaches the simulation.
- Audio pan from the across-screen axis; Settings v3→v4 migration fixture (step 13).

**Widget**
- `game_screen_test.dart` at 402×874 and 375×667: stats at top, strip at bottom with
  `Axis.horizontal`, no overlaps, no exceptions; drag a strip cell up → placement; release
  over the strip → cancelled; **rotation**: select at 923×411, resize to 411×923 → selection
  kept, sheet present, `mapTurns == 1`; drag then rotate → no turret built. Under
  `enhancedSkin`: rails at 923×411, panel on the far side.
- Editor: canvas turned in portrait, nudge direction; mods drill-down; challenge stacked.
- `test/accessibility/accessibility_test.dart`: add sizes {923×411, 411×923, 375×667} so
  tap-target/label/contrast/1.3× text cover every portrait screen.

**Golden** (`test/goldens/devices.dart`): add `phonePortrait 402×874`, `phoneSmallPortrait
375×667`, `tabletPortrait 834×1210` and D5's `phoneSE 667×375`, `ipad10 1180×820`, `laptop
1440×900`; keep `all` as today's four so no existing golden re-lays out. New images:
`stats_bar*` (rename of `top_bar`, identical pixels, named in the `test:` commit),
`tower_tray_strip`, `turret_sheet_compact`, `hud_layout` (both skins, every size), portrait
menu/mods/editor/library scenarios, `ground_component` and `turret_panel_far_side` (Enhanced).

**Classic stays byte-identical, proven by**: (a) every existing `test/goldens/**/ci/*.png`
passes with tolerance 0 and no `--update-goldens`; propose a CI step that
`git diff --diff-filter=M --name-only origin/main -- 'test/goldens/**/ci/*.png'` is empty;
(b) the classic layout guard test; (c) the `hud_layout.png` classic landscape rows recorded
in step 1; (d) the sim-equivalence test; (e) core fixtures untouched by construction.

**Legitimate test churn** (no PNG re-recorded): fakes implementing `PlacementInput.dragTo`
and `GameViewModel.turretAt` gain parameters; `AssetPack` fakes gain `ground()` in step 12;
`top_bar_*` tests renamed.

**Manual QA** (skills `ios-simulator-qa`, `android-emulator-qa`,
`flutter-run-and-hot-reload`, report with `qa-report`): rotate iPhone + iPad simulators and
the Pixel AVD mid-wave both ways, during a tray drag and with a turret selected; Chrome
device emulation both orientations; macOS window dragged through every shape including tiny;
tutorial "Show me" arrows in portrait; editor round-trip (draw in portrait, play in
landscape). Frame time for the shader ground on the AVD and a real mid-range Android.

**Gates every step**: `fvm dart format --set-exit-if-changed .`, `fvm flutter analyze`,
`fvm flutter test`, `(cd packages/onslaught_core && fvm dart test)`.

---

## 10. Docs and standards (R20/R24)

- Pre-approved P3 wording (step 7): `.agents/tenets.md:37`, `AGENTS.md:33,44`,
  `.agents/project-overview.md:53`.
- `docs/SCREEN_FIT_PLAN.md`: status line; mark §4.2, §4.4 (landscape), §6.1, §6.2, §7 as
  Enhanced only (owner, 2026-10-19); record "editor turns too", "no orientation setting",
  "no turn animation in v1"; fix §12 path to `lib/app/camera_rig.dart`; §10 reordered as §8.
- `docs/REMASTER_PLAN.md`: §0 line 20, §3.1 (view turn; bands Enhanced only), §3.3 line 262
  ("Landscape only" → regions per screen shape and skin), §5.2 ground sources, §5.3 (`UiSkin`
  exists), §9 item 5 (portrait done), Phase 8 status.
- `docs/ENHANCED_PLAN.md` §2.1/E0: `UiSkin.forProfile` is the hook E0 uses.
- `.agents/architecture.md`: presentation contract (per-shape `HudLayout`, view turn is
  presentation only, `Upright`/`WorldLabel`, `UiSkin`, `GroundSource`); key-types rows; no
  new packages (shader via `flutter: shaders:`).
- `.agents/workflow.md`: `ENHANCED_SKIN` dart-define.
- Skills: `golden-tests` device set; `ios-simulator-qa` and `android-emulator-qa` (rotate
  mid-game instead of "landscape-only"); `add-language` (length checks at 375 wide);
  `release-build` ("orientation switching" instead of "orientation lock").
- `l10n/README.md` coverage + `l10n/de.json` for `ui.editor.more`, `ui.game.windowTooSmall`,
  `ui.settings.ground*`. `CHANGELOG.md` Unreleased: "Play in portrait or landscape; the HUD
  moves to where the screen has room."
- Code comments that say landscape: `menu_scaffold.dart:31`, `dialogs.dart:65,100`,
  `top_bar.dart:8`, `tower_tray.dart:22`, `main.dart:12`.
- No `docs/DEVIATIONS.md` rows: no game-rule changes.

## Risks
1. Rotation during a drag building a turret → cancel-before-rebuild + `_dragIgnored` + test.
2. `setLayout` vs `onGameResize` order → `_reframe` + the order-independence test.
3. Compact thresholds must stay < 591 so the iPhone SE in landscape keeps Classic's forms.
4. `AssetPack.ground()` touches ~15 test fakes → one commit.
5. iPad multitasking sizes if `UIRequiresFullScreen` is left off.
6. Accessibility matrix triples (≈66 pump-the-app cases) → watch CI time.
7. Shader support on web/low-end Android → measure in step 13, image-cache fallback.
