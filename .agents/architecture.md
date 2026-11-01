# Architecture (condensed — full detail in docs/REMASTER_PLAN.md §1–§5)

## Layers

```
assets/data/*.json  ──►  packages/onslaught_core        (pure Dart)
                              data/   typed GameData, loaders, validation, mod deltas
                              sim/    GameSession, systems, entities, fixed-step clock, seeded RNG
                              rules/  targeting, modifiers, combos, economy, progression, RulesRegistry
                                 │  GameCommand in  /  GameEvent + state snapshots out
                                 ▼
lib/features/game/      session facade: GameViewModel (ValueListenables) + dispatch(GameCommand)
   flame/               OnslaughtFlameGame, CameraComponent, world components (views of sim state)
   hud/                 Flutter widgets (top bar, tower tray, selected-tower sheet, dialogs)
lib/services/           AudioService, PersistenceService (hive_ce), ShareCodec, Haptics
lib/app/                MaterialApp, go_router, Riverpod providers, theme/UiSkin
```

Data provenance: `.legacy/` → `tool/legacy_extract.dart` (once) → `docs/legacy/legacy_values.json`
+ `l10n/*.json` → `tool/gen_data_from_legacy.dart` → `assets/data/*.json`; a snapshot test keeps the last two in sync.

Rules of the arrows: dependencies point downward only. Core knows nothing above it.
Flame components and widgets never mutate sim state directly; they dispatch commands (the
session's state is read-only from outside the core; its writers are `@internal`).

## Key types (names are contracts; keep them)

| Type | Lives in | Role |
|---|---|---|
| `GameData` | core/data | immutable, validated union of all data files + applied `ModDelta` |
| `GameSession` | core/sim | one running game: config, clock, read-only world state (getters, `UnmodifiableListView` lists), `step()`; its command handlers live in `session_commands.dart`, its `@internal` combat API (`WorldActions`: projectiles, blasts, hits, slows, kills) in `world_actions.dart` |
| `ObjectiveSystem`, `Objectives` | core/sim | wave, kill and time objectives and the win check; owned and run by the session after the real-time timers |
| `SessionDebug` | core/sim | the one `@visibleForTesting` way to set session state outside commands (`debugCash`, `debugMakeAvailable`, …), for tests and `SoakDriver` |
| `Ordnance` (`BlastLoad`, `ClusterLoad`, `OnboardWeapon`, `NapalmLoad`, `LaserBlastLoad`, `HoleLoad`), `RocketState` | core/sim, core/rules | what a combo projectile carries, one immutable record per block; a rocket's holding state (its `KindState`) |
| `GameCommand`, `GameEvent` | core/sim | the only way in and out of the sim |
| `SessionReplay`, `GameInProgress` | core/sim, services/persistence | `GameSession.commandLog` logs every command against its step; `SessionReplay` re-simulates a fresh session through that log (in slices), so config + data + log rebuild a game exactly; `GameInProgress` (`gameInProgress` document) is the one stored unfinished game, checked by its state hash on resume (`docs/REPLAY_PLAN.md`) |
| `RulesRegistry` | core/rules | id → behaviour for turret specials, projectile kinds, blast kinds, creep behaviours |
| `RulesProfile` | core/rules | `classic` (bit-faithful), `classicFixed` (v1 default), future profiles; `enhancedSkin` picks the presentation (`UiSkin.forProfile`), it is not a rule toggle |
| `ProjectileSpec`, `BlastSpec`, `TurretDef`, `ComboRecipe`, `MapDefinition` | core/data | data records |
| `GameViewModel` | features/game | UI facade; widgets depend only on this |
| `GameRuntime` | features/game | one game's lifetime: session, view model, Flame game, sound, haptics, progress |
| `AssetPack` | services | logical id → art and sound (`AssetPack.sound(id)`; there is no separate audio pack type); chain `[user?, hd?, classic]`; procedural packs implement the same interface; a `SpriteFrame` lists its densities and the game's `ArtResolver` draws the one that covers zoom × device pixel ratio, loading atlas pages on demand; Classic games use `[classic]` (`assetPackProvider`), Enhanced games `[enhanced, classic]` (`enhancedAssetPackProvider`) |
| `MapGenerator` | core/rules | seed → `MapDefinition` under the map contract (`BuiltInMapGenerator` returns the built-in maps; `test/editor/map_generator_contract_test.dart`); its intended caller is the editor's "generate a map", which does not exist yet |
| `FeatureFlags` | lib/app | gate unfinished work (`ENHANCED_SKIN` forces the Enhanced skin) |
| `UiSkin` | lib/app/ui_skin.dart | Classic or Enhanced presentation; `forProfile(RulesProfile)`; what each skin offers |
| `HudLayout`, `HudMetrics` | features/game/layout | the HUD per screen shape: regions, map insets, fill, panel edge, tutorial window |
| `GroundSource` (`ImageGround`, `ShaderGround`) | services/assets | how a pack draws the ground (`AssetPack.ground`); the sharp ground is `ProceduralGroundPack` + `shaders/ground.frag` (no new package: `flutter: shaders:`) |
| `ModEditorDefs`, `ModRules` | core/data, core/rules | what the mod editor offers (`mod_editor.json`) and the rules over a `ModDelta`: values, checks, reset, import, signature |
| `customGameReasons`, `recordsProgress` | core/rules | a game with a mod on or on a player's map is custom and records no progress (`RulesProfile.customGamesSeparate`) |
| `CustomRecordKey`, `mapVersionHash`, `improvesCustomBest` / `CustomRecords` | core/rules / services/persistence | custom games' own records in `profile.custom` (v2): per player-map version, mod, mode, difficulty and challenge; shown by `CustomRecordList` (lib/app) in Map Tools and on `/records` |
| `GameText.tr`, `uiLocale` | lib/app/strings.dart | the localisation hook: every UI string comes from `strings/<locale>.json` in the interface language (translations in `l10n/`) |
| `DataTextKeys`, `DataText` | core/data/data_text.dart | the data documents' own text (names, challenge pickers, tutorial, mod editor) in a locale: the generator copies its English into `strings/en.json` under these keys; lookups fall back to English, then the document |
| `Logger`, `LogService`, `AppLogging`, `PiiRedactor` | services/logging | the local log (`docs/LOGGING.md`): `Logger('area')` queues a record and returns; `LogService` formats, masks personal data (`PiiRedactor`, `Pii`) and writes in batches to its sinks, containing every failure; `AppLogging` is the rotating files plus level, export (zip to the share sheet) and clear for Settings → Diagnostics |
| `EffectSettings`, `HapticSink` | features/game, services/haptics | display settings the game reads live (rocket smoke, colour badges); vibration on build/upgrade/sell/unlock |
| `SoakDriver` | core/testing | plays a sandbox game hard (every turret, combos, sales, 3×) for the headless and device soaks |

Planned seams (Enhanced, see `docs/ENHANCED_PLAN.md` §2.2): `ContentPack` (core/data, a shipped data
overlay — maps, turrets, recipes, strings — built in E0) and `WaveComposer` (core/rules, wave N → creep
roster, built in E2). Neither exists in code yet; each needs a classic implementation proven by the
fixtures passing unchanged.

## Simulation contract
- Fixed timestep (60 Hz) driven by the caller's accumulator; game clock = steps × speed,
  frozen on pause. World unit = original pixel (720×480 play area).
- All randomness through the session's seeded `Random`.
- Cross-platform determinism (owner, 2026-10-20): the same data, seed and commands give the
  same events and state hashes on the VM (any OS), dart2js and dart2wasm; replays and
  fixtures are never per-platform. Enforced by: sin/cos/atan2 only through
  `math/det_math.dart` (fdlibm 5.3 in pure Dart; `math/`, `rules/` and `sim/` take only
  `sqrt`, `min`, `max` and `pi` from `dart:math`, architecture test); sort ties broken by
  uid; `canonicalJson` writing numbers by value, never by type; no shifts of negative ints
  (dart2js treats them as unsigned 32-bit); and CI replaying every fixture on macOS and
  Linux VMs and in Chrome (`tool/web_regression.dart`, dart2js and dart2wasm).
- Order per step: queued commands → game-time systems (`classicSystems`: waves → creeps →
  turrets → projectiles → blasts → black-hole captures; damage is dealt inside them) →
  real-time timers (`RealTimeSystem`) → objectives (`ObjectiveSystem`, the win check) →
  cleanup. Turret relations are recomputed on change only (build, sell, move, upgrade).

## Presentation contract
- `CameraComponent` zoom clamped `[fitWholeMap, max(3 × fit, 2 × home)]`, position clamped
  to world + margin; pinch = zoom, one-finger drag on empty ground = pan, tap =
  select/deselect at once, double tap on empty ground = home ↔ zoomed (whole map in portrait), drag from tray =
  build. `CameraRig` (lib/app) is the single screen ↔ world conversion for the game and the
  editor.
- One `HudLayout` per screen shape and skin (`bars`, `rails`, `portrait`, `unsupported`)
  places every overlay, sets the camera's insets and whether its home view fills the map
  area (portrait: the map upright, filling the space, panned along), and tells tray drags
  where the HUD is. Classic landscape is always `bars`, exactly v1 (guard test).
- The screen shape is presentation only: the world, commands, fixtures and replays are the
  same in any orientation (`view_shape_sim_test`).
- `UiSkin` gates the Enhanced-only presentation (rails, far-side panel, ground beyond the
  play area, sharp ground, ghost lift, turret hit zone); a game's skin comes from its rules
  profile.
- HUD = Flutter overlays on `GameWidget`, rebuilt from `ValueListenable`s, never per frame.

## Testing contract (see .agents/workflow.md and docs/REMASTER_PLAN.md §8)
`SimTestHarness`, `FixtureRecorder` (golden-state regression), `FakeGameViewModel`,
architecture test, data-contract tests, balance bots, accessibility checks
(`test/accessibility/`: tap targets, labels, contrast, 100 % / 130 % text on every screen) and
the soaks (`SoakDriver`: core tag `soak`, `integration_test/soak_test.dart` on devices).

## Dependency log
Append a row for every new package (rule R6).

| Package | Purpose | Alternatives considered |
|---|---|---|
| `flame` ^1.38 | game loop, camera, components, input | custom CustomPainter loop (rejected: re-implements camera/input/atlases); Flame 2.0-dev (rejected: prerelease) |
| `flame_audio` | SFX playback via audioplayers | `just_audio` (heavier), `soloud` (native build complexity) |
| `flutter_riverpod` | app-level state and DI | `bloc` (more ceremony for this app size), plain `InheritedWidget` |
| none (models + JSON) | the core's data records are hand-written `@immutable` classes with `fromJson(JsonReader)`, which checks each field and reports every problem with its path (unknown keys included); no code generation, so the pure core has no build step or generated files | `freezed` + `json_serializable` (never adopted: `build_runner` codegen and generated files in the pure core, for records that validate field by field anyway) |
| `go_router` | screen navigation | `Navigator 2.0` by hand |
| `hive_ce` | local persistence on all platforms incl. web | `shared_preferences` (too small), `isar`/`drift` (overkill, web friction) |
| `test`, `flame_test`, `alchemist`, `integration_test`, `coverage` (core) | testing; `coverage` formats the core's lcov in CI | `golden_toolkit` (unmaintained) |
| `hive_ce_flutter` | Flutter init for `hive_ce` (`Hive.initFlutter`, platform storage paths) | hand-rolled `path_provider` setup (more code, same result) |
| `meta`, `collection` (core) | `@immutable` annotations; deep equality for data records in the pure-Dart core | hand-written equality (error-prone), `equatable` (extra dependency for the same job) |
| `image` (dev, tool only) | pure-Dart PNG/JPEG decode/encode for `tool/pack_atlas.dart` | ImageMagick / Pillow (not installed, non-Dart toolchain), FFDec atlases (not supported) |
| `args` (dev, tool only) | command-line parsing for tools (`tool/pack_atlas.dart`) | hand-rolled `argv` parsing |
| `flutter_lints` (dev), `lints` (core dev) | analyzer rule sets for the app and the core | `very_good_analysis` (stricter; can be layered on later) |
| `flutter_localizations` (SDK) | Material/Cupertino widget translations for the locales the data's string tables offer (`MaterialApp.localizationsDelegates`) | none: the SDK's own package; without it Material widgets only speak English |
| `archive` | gzip for share strings (`ShareCodec`: `ons3:map:<base64url(gzip(json))>`) on every platform including web; already in the lock file through `image` | `dart:io` `GZipCodec` (not available on web), uncompressed base64 JSON (2–3× longer strings), a hand-written DEFLATE |
| `share_plus` | Settings → Diagnostics → Export logs: hands the zip to the system share sheet (a download on the web) | `file_selector` save dialog (no share sheet on phones), a mail link (cannot attach files) |
| `path_provider` | the log folder (application support) and the temporary file an export is shared from; already in the lock file through `hive_ce_flutter` | Hive for log text (rewrites the whole file on each append) |
| `package_info_plus` | the app's version and build in each run's first log record and in an export's `info.json` | a version constant kept by hand (goes stale) |
