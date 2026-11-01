# Onslaught 3 Remastered — Enhanced Mode Plan

Companion to [REMASTER_PLAN.md](REMASTER_PLAN.md). The remaster plan builds **Classic**: a
faithful copy of the original game, departing from it only where
[DEVIATIONS.md](DEVIATIONS.md) says so. This document plans **Enhanced**: a second way to
play that keeps the game's identity (four colours, proximity combos, single-road maps) and
deliberately improves on it with new creeps, upgrade paths, turrets and UI.

The phases are numbered **E0, E1, …** so they never get confused with the remaster's
Phase 0–8. The plan is meant to grow: new phases are added at the end using the template in
§6, and ideas wait in the backlog (§5) until they are planned.

---

## 0. Goals and non-goals

**Goals**
- Make the game deeper without making it a different game. Combos stay the signature
  mechanic; every Enhanced feature should give players more reasons to mix colours and
  build combos, not fewer.
- Fix the original's design gaps (§1) in order of value per effort.
- Use the extension points the remaster already has (`RulesProfile`, `RulesRegistry`,
  data overlays, `AssetPack`, `UiSkin`); never fork or special-case Classic (tenet 4).
- Every phase is small, shippable and balance-checked by the bots.

**Non-goals**
- Changing Classic. Every Enhanced phase must leave Classic's regression fixtures,
  goldens and balance-bot results **byte-for-byte unchanged**. This is an acceptance
  criterion of every phase, not a hope.
- Copying Bloons TD 6 wholesale. It is the reference for touch UI and upgrade paths, not
  for content.
- Online features, monetisation, telemetry (rule R22 still applies).

---

## 1. What the original lacks (the design brief)

Read from [ONSLAUGHT2_GAME_REFERENCE.md](ONSLAUGHT2_GAME_REFERENCE.md):

1. **Creeps are mechanically identical.** The 9 types differ only in sprite (§3); each
   wave just has more HP. Nothing makes you build a particular colour except raw damage
   and combos.
2. **Upgrades only change numbers.** Damage, range and rate are linear tracks of absolute
   values (§4–§5). New behaviour comes only from specials unlocked at fixed levels:
   freakout at damage ≥4 and rate ≥4, holding pattern at range ≥3 and rate ≥3, combos at
   damage maxed.
3. **No economy decisions.** The only income is kill bounty (§2).
4. **Numbers run into the tens of millions**, which hides what an upgrade does.
5. **No goal** beyond surviving and kill-count unlocks (§9).
6. **The deepest mechanic is invisible.** Nothing shows which combo a group of turrets
   will fire, or why one did not fire.

---

## 2. How Enhanced plugs in

### 2.1 Mode = rules profile + content overlay
- **`RulesProfile.enhanced`** starts as a copy of `classicFixed`'s switches. New on/off
  switches are added only for rule changes that cannot be expressed as data.
- **An Enhanced content overlay** (`assets/data/packs/enhanced/`) is applied on top of the
  base data when an Enhanced game loads, the same way a mod delta is applied. It holds
  everything Enhanced adds or changes: creep traits, path definitions, new turrets, wave
  rosters, strings.
- **New mechanics are data-driven.** A behaviour (a creep trait, a path effect, a new
  turret special) is registered in `RulesRegistry` for every game, but only Enhanced data
  refers to it. Classic data never names it, so Classic cannot run it. This keeps the
  "Classic is unchanged" guarantee structural rather than relying on `if` checks.
- **Enhanced rules have their own spec**: `docs/ENHANCED_REFERENCE.md`, created in E0 and
  extended by every phase. It is to Enhanced what the game reference is to Classic.
- **The Enhanced UI already exists** behind `UiSkin` (`lib/app/ui_skin.dart`,
  `docs/history/PORTRAIT_PLAN.md`): side rails on wide landscape phones, the turret panel on the
  far side, ground beyond the play area, the Ground: Sharp setting, the lifted ghost and
  the 22 pt turret hit zone. A game picks it with `UiSkin.forProfile(config.profile)`, which
  reads `RulesProfile.enhancedSkin` (false for `classic` and `classicFixed`), so
  `RulesProfile.enhanced` sets `enhancedSkin: true` and selects it with no further change; until then
  `--dart-define=ENHANCED_SKIN=true` forces it for QA.

### 2.2 What does not exist yet
- `ContentPack` and `WaveComposer` are named in REMASTER_PLAN §5.4 and listed as planned seams
  under the Key types table in `.agents/architecture.md`, but there is no code for them yet. E0 builds `ContentPack`;
  E2 builds `WaveComposer`. Each needs a classic implementation that reproduces today's
  behaviour exactly, proven by the existing fixtures passing unchanged.
- `RulesProfile` is a fixed set of booleans. That is fine for a few Enhanced switches; if
  it grows past roughly ten, split Enhanced settings into a data file read through
  `GameData` instead.

### 2.3 Persistence
- Enhanced has its own progression (decision D1, §4): its own unlocks, kill counts and
  best games, in its own section of the `profile` document (schema bump + migration +
  fixture, rule R9). Nothing earned in one mode unlocks anything in the other.
- Enhanced games, replays and best games record the profile id and the content overlay
  version, so a later balance change never misreads an old save.

### 2.4 Testing
- **Classic guard**: every Enhanced PR runs the Classic fixtures, goldens and bots, and
  they must not change.
- **Enhanced fixtures**: a separate fixture set
  (`packages/onslaught_core/test/fixtures/regression/enhanced/`) freezes Enhanced behaviour
  once a phase lands. Unlike Classic, Enhanced fixtures may change in later phases, but
  only deliberately, with the reason in the PR (rule R15).
- **Enhanced balance bots**: their own strategies and tolerance bands (balance-bot skill).
  New bots check the design goals directly, for example "a mixed-colour strategy beats a
  single-colour one".
- **Shared UI** (E1) gets widget tests and goldens in both modes.

---

## 3. Phases

Each phase lists what it builds, its tests, and when it is done. Every phase also meets
the remaster's definition of done (REMASTER_PLAN §8.4) and leaves Classic unchanged.

Phase numbers are stable ids: new phases are appended (§6), so the numbers are not the
order of work. **Suggested order**: E0 → E1 → E8 → E2 → E3 → E4 → E5 → E9 → E10 → E6.
E7 can run any time after E0. Reorder this line, not the phase numbers.

### Phase E0 — Foundations
- `RulesProfile.enhanced`, the `ContentPack` overlay mechanism, and an empty Enhanced
  overlay in `assets/data/packs/enhanced/`.
- A `FeatureFlags.enhanced` flag (off in release builds until E2 lands), an Enhanced entry
  on the mode screen, and its own progression section in `profile`.
- Enhanced games draw from `enhancedAssetPackProvider` (`[enhanced, classic]`) instead of
  `assetPackProvider` (the game screen still adds the sharp ground in front when picked).
  `RulesProfile.enhanced` must use the id `enhanced`: `UiSkin.forProfile` keys on it. The Enhanced asset pack already exists: vector redraws of the nine
  creeps (`tool/art/creeps/`, `assets/images/enhanced/`); Classic keeps the original creeps.
- `docs/ENHANCED_REFERENCE.md` with its first rule.
- One trivial rule change through the whole stack to prove it works end to end (for
  example different starting cash), plus the first Enhanced fixture and a bot baseline.
- Tests: overlay apply/merge rules, profile migration fixture, data validation of the
  overlay, Classic fixtures unchanged.
- **Done when**: an Enhanced game starts from the menu, uses the overlay's value, records
  an Enhanced fixture, and Classic's fixtures, goldens and bots are unchanged.

### Phase E1 — UI and targeting
Mostly presentation; the one rule change is the new target modes. Everything here is
Enhanced only except the recipe book (decision D2: Classic keeps the original game's
interface).
- **Combo preview** (Enhanced): while dragging a new turret or moving one, show which
  recipe the group within 70 px would fire, and which turret is missing for the next one.
- **Recipe book** (both modes): every combo recipe with its leader, helpers and effect,
  read from the data.
  - Reachable from the **main menu** (all recipes) and **in game** (filtered to the
    current game's mode).
  - Each recipe is tagged **Classic**, **Enhanced** or **Both**. The tag is derived from
    the data, never written by hand: a recipe in the base data that the Enhanced overlay
    leaves alone is Both, one only in the overlay is Enhanced, and one the overlay
    removes is Classic. If the overlay changes a recipe, the book shows the Classic and
    Enhanced versions as separate entries.
- **Target modes** (Enhanced): Classic already has the original's eight modes (near, far,
  weak, strong, slow, fast, old, young in `targeting.json`), cycled by tapping the sheet's
  target button or chosen from a list with a long press. Enhanced adds the Bloons-style
  **First** and **Last**: the creep furthest along the road and the one least far. The
  original's "old" only approximates First, and is wrong once creeps are slowed or
  differ in speed. Enhanced's overlay lists the new modes and may make First the
  default; Classic's list is unchanged. The picker shows a one-line description of each
  mode.
- **Turret stats** (Enhanced) on the selected-turret sheet: kills, damage dealt, combos fired.
- **Upgrade preview** (Enhanced): before/after numbers on every upgrade button, and the sell
  value.
- **Next-wave preview** (Enhanced) in the HUD (more useful once E2 adds traits).
- **Combo feedback** (Enhanced): when a combo fires, brief lines from the leader to each
  helper; a recharge ring on combo-capable turrets; helpers that a combo has taken are
  dimmed until they recover. Built from the existing `ComboFired` event, which already
  lists the helpers.
- **Post-game report** (both modes): shown from the game-over and win dialogs; kills and
  combos fired per turret, combos by type, cash spent and earned over time, and the wave
  where lives were lost. In Classic it uses only what the existing events already carry
  (`CreepKilled`, `ComboFired`, `TurretBuilt`/`TurretUpgraded`/`TurretSold`, `BaseHit`,
  `WaveStarted`), so Classic's fixtures stay unchanged. Damage dealt per turret needs a
  new event and is Enhanced only.
- Stats are derived in the app from existing `GameEvent`s where possible. If the sim must
  emit a new event, that is a fixture-format change and is called out in the PR (R15).
- Tests: widget tests against `FakeGameViewModel`, goldens at phone/tablet/desktop sizes,
  a rule test that the combo preview matches the recipe the sim actually fires, a test
  that every recipe's tag matches the data layers, rule tests and an Enhanced fixture
  for First and Last, report tests fed from recorded fixtures in both modes.
- **Done when**: in Enhanced a player can see which combo a group will fire before
  building it, see each combo that fires, and target First or Last; the recipe book
  opens from the main menu and in game with correct tags and filtering; the post-game
  report shows in both modes; every new panel has widget and golden coverage.

### Phase E2 — Creep traits
- **Relative values**: trait effects are percentages and multipliers ("blocks 50% of
  bullet damage", "heals 2% of max HP per second"), so they hold at any number scale
  (decision D3).
- **Damage types**: every projectile and blast gets a data-defined type (bullet, explosive,
  laser, electric) so traits can react to them. Classic data has no traits, so the types
  have no effect there.
- **`WaveComposer`**: the classic composer reproduces the original 9-type rotation and HP
  curve exactly; the Enhanced composer adds traits to waves from data.
- **Win condition** (decision D5): Enhanced normal games are won at a wave set in data
  (proposed: 100), then continue in freeplay through the existing `continueAfterWin` flow.
- **Traits** (each a `RulesRegistry` behaviour plus data), picked to push towards
  different colours:
  - Armoured — resists bullets; Red or Green needed.
  - Shielded — a shield that lasers strip quickly.
  - Swarm — groups of small, low-HP creeps; chain lightning and cluster bombs shine.
  - Stealth — targetable only inside a Targeter's range.
  - Splitting — splits into two smaller creeps on death.
  - Regenerating — heals over time unless slowed.
  - Boss — every 10th wave, with a health bar and a large bounty.
- **Visuals**: trait overlays and tints through an Enhanced asset pack in the `AssetPack`
  chain (procedural tints are fine for a first version), plus trait icons in the
  next-wave preview.
- **Tips on first sight**: the first time a trait (and later a flyer or boss) appears, a
  one-line hint, such as "Armoured: resists bullets. Try Red or Green." Each tip shows
  once per profile, and a setting turns all tips off.
- **Bonus for calling a wave early**: sending the next wave before its timer runs out pays
  a bonus that grows with the time left (formula and numbers in data). The original can
  send waves early but pays nothing for it.
- Tests: a rule test per trait, a scenario per trait, an Enhanced fixture per trait, a
  classic `WaveComposer` test that Classic fixtures are unchanged, early-call bonus rule
  tests and a fixture, tip widget tests including the off setting, bot runs.
- **Done when**: every trait is playable in Enhanced, an Enhanced game can be won and
  continued in freeplay, calling a wave early pays its bonus, and the bots show a mixed-colour
  strategy clearly beating a single-colour one in Enhanced while Classic's results are
  unchanged.

### Phase E3 — Flyers
Split out from E2 because it touches movement, targeting, ordnance and maps.
- A creep behaviour that flies straight from the spawn point to the base, ignoring the
  road. On Onslaught's free-form maps this is a real threat: turrets lined up along the
  road can be out of range.
- Rules for which weapons can hit flyers: landmines and black holes cannot, rockets and
  lasers can, others decided in this phase and written into the Enhanced reference.
- The map library and editor show each map's flight line.
- Tests: movement and targeting rule tests, a scenario per affected ordnance, fixtures,
  and a bot run on every built-in map.
- **Done when**: flyer waves appear in Enhanced, every built-in map stays winnable by the
  bots, and the editor shows the flight line.

### Phase E4 — Upgrade paths
The largest design phase, so it starts with a short design spike written into the
Enhanced reference before any code.
- **Paths sit on top of the stat tracks** (decision D4). The original damage, range and
  rate tracks stay as they are; paths are a second upgrade layer.
- **Schema**: per turret, three paths of five tiers; each tier has a cost, its own stat
  boosts (multipliers, per D3, so each path strengthens different stats) and optional
  abilities. The crosspath limit (Bloons uses 5/2/0) lives in data.
- **The original specials become path capstones**, for example:

  | | Path A | Path B | Path C |
  |---|---|---|---|
  | Blue | Heavy Shells (armour-piercing, explosive rounds) | Berserker (freakout more often, tap to trigger) | Gatling (fire rate, more barrels) |
  | Red | Warheads (splash damage, mini-nuke) | Swarm (more holding-pattern rockets, salvos) | Seeker (range; can hit flyers) |
  | Green | Link Network (stronger, longer links) | Focus (damage ramps on one target, strips shields) | Prism (beam splits to several targets) |
  | Yellow | Capacitor (bigger, faster charge) | Chain (more lightning arcs) | Stasis (slows become stuns) |

- **Combo eligibility moves into data**: Classic keeps "damage track maxed". Because the
  tracks stay, Enhanced can keep that rule too; the design spike decides whether paths
  also unlock combos (for example any path at tier 3). Later, path choice may change the
  combo a turret leads (backlog).
- **Sell value** includes everything spent on stat tracks and paths.
- **UI**: the selected-turret sheet keeps the three stat tracks and adds a path layout
  (three rows of five pips, locked tiers greyed out), built against `FakeGameViewModel`
  first. Fitting both on a phone sheet is part of the design spike.
- **Modifier turret paths**: after the four colours, the seven aura turrets (one range
  upgrade each in the original) get a smaller path choice, for example a bigger radius
  versus a stronger effect. Same schema, fewer tiers.
- Lands **one colour at a time, Blue first**, then the modifiers; each is its own PR with
  its fixtures and a bot run.
- Tests: crosspath-limit rule tests, a rule test per tier effect, a scenario per capstone,
  fixtures, sheet widget tests and goldens, bot runs per colour.
- **Done when**: all four colours have three paths on top of their stat tracks and the
  modifiers have their path choice in Enhanced, combos still fire under the chosen eligibility rule, and the bots stay within the Enhanced tolerance bands.

### Phase E5 — New turrets
Each turret is data, a behaviour if it needs one, art, a fixture and a bot run (the
remaster's "Add a turret" recipe in `.agents/workflow.md`).
- **Bank**: pays income each wave; the first real economy decision.
- **Radar**: reveals stealth creeps in its range; an alternative to the Targeter.
- **Mortar**: fires at points on the road; strong against swarms, cannot hit flyers.
- **Anti-air**: hits only flyers (only if E3 shipped).
- No fifth colour: combo recipes are keyed by colour counts, so a new colour would
  multiply the 20-recipe table. Colourless turrets, like the modifiers and supers, are far
  cheaper to add.
- **Done when**: each turret has a clear job that the bots confirm (for example a
  Bank-first strategy ends with more total cash by wave 50), with fixtures and art.

### Phase E6 — Balance pass
- Tune the whole Enhanced data set together with the bots once E2–E5, E9 and E10 have
  landed.
- Enhanced keeps the original number scale (decision D3). If a later revisit picks a
  flatter scale, it lands here as a data change.
- **Done when**: every Enhanced bot strategy is within its tolerance band at difficulties
  easy to extreme, and the before/after tables are in the PR.

### Phase E7 — Achievements
Local achievements, no online service (rule R22). Can start any time after E0; the
achievements that need Enhanced content (traits, paths, new turrets) land with or after
the phase that adds that content.
- **Data**: `achievements.json` lists each achievement: id, mode tag (Classic, Enhanced or
  Both, decision D6), a condition type with parameters, an optional progress target,
  whether it is hidden until earned, an icon asset id and its strings. Adding an
  achievement is a data change, not code.
- **Conditions are pure functions of `GameEvent`s** and live in the core, so they can be
  tested headless and checked against recorded fixtures and replays. Condition types are
  registered by id, like other behaviours. A first set:
  - reach wave N (per difficulty); survive N waves without losing a life;
  - fire a given combo, or every combo;
  - build a given turret, or every super turret;
  - win a given challenge preset, or all of them;
  - finish a game without selling;
  - Enhanced: defeat a boss, max a path tier, earn N from Banks.
- **Custom games** (a mod on, or a player's map) never earn standard achievements. Their
  achievements are tagged Custom and read the custom records (`profile.custom`, built
  2026-10-19: best wave per player-map version, mod signature, mode and difficulty), never
  the standard progress (owner decision, 2026-10-19).
- **Tracking**: the app subscribes the evaluator to the session's events and saves
  progress in each mode's section of `profile` (schema bump + migration + fixture, R9).
  Achievements never feed back into the simulation, so fixtures are unaffected.
- **UI**: a toast when one is earned (the existing message toasts), an Achievements screen
  on the main menu with progress bars and the mode tag on each, filtered by mode like the
  recipe book.
- Tests: a rule test per condition type, an evaluator run over existing regression
  fixtures (for example the fixture that fires a Nuke earns "fire a Nuke"), a profile
  migration fixture, widget tests and goldens for the toast and the screen.
- **Done when**: the first set is earnable in its modes, progress survives a restart, and
  the Achievements screen shows each achievement's mode and progress.

### Phase E8 — Controls
Small rule changes that make the game easier to play on a phone. Best done early, right
after E1.
- **Build while paused**: building, upgrading, selling, moving, joining and changing
  target mode all work while the game is paused. The original refuses every turret
  command while paused (reference, "Corrections"). An Enhanced `RulesProfile` switch,
  since it is a rule rather than a value.
- **Upgrade queue**: a turret's sheet can queue its next upgrades on any track (and
  paths, once E4 lands). The sim buys them in order as soon as cash covers the next one,
  so queued buys are deterministic and appear in replays. A queued step shows as a pip;
  tapping it cancels. Selling or moving the turret clears its queue.
- **Buy what I can afford**: one button that buys as many steps of a track as the
  current cash allows.
- Tests: a rule test per turret command while paused, queue order and cash-timing rule
  tests, a scenario where queued buys happen mid-wave, an Enhanced fixture, sheet widget
  tests and goldens.
- **Done when**: in Enhanced a player can pause, build and upgrade, then resume; queued
  upgrades buy themselves as cash arrives; Classic still refuses commands while paused.

### Phase E9 — Turret veterancy
- Turrets earn ranks at kill thresholds (data), each giving a small damage, range or rate
  multiplier (relative values, D3), shown as a chevron on the turret and a rank line on
  its sheet.
- Builds on the kill credit turrets already get (`turretKill`). A turret keeps its rank
  when moved; selling does not refund it. Kills that give no credit in the original
  (black-hole kills) give no rank progress.
- To decide in this phase: whether combo kills also credit the helpers, and a cap so one
  turret cannot snowball (the bots check it).
- Tests: rank threshold and multiplier rule tests, move-keeps-rank test, a scenario, an
  Enhanced fixture, sheet goldens, bot runs.
- **Done when**: turrets rank up visibly in Enhanced and the bots stay within the
  Enhanced tolerance bands.

### Phase E10 — Mutators
- **Mutators** are optional handicaps chosen before an Enhanced game, each adding to a
  score multiplier: for example no Blue, half starting cash, faster creeps, no selling.
  They combine freely.
- `mutators.json` defines each mutator as a data override where possible (half cash,
  faster creeps) or a rule switch where not (no selling), plus its score multiplier and
  strings.
- **Presets** are saved sets of mutators. The first is a **hardcore preset** in the style
  of Bloons' CHIMPS: no selling, one life, and no powers if global powers are ever added.
- Best games are kept per mutator set, like challenge best games are kept per challenge.
- E7 can add achievements for mutators (for example "win with the hardcore preset").
- Tests: a rule test per mutator, combination and multiplier tests, a scenario for the
  hardcore preset, an Enhanced fixture per rule-switch mutator, picker widget tests and
  goldens, bot runs with the hardcore preset.
- **Done when**: a player can pick mutators or the hardcore preset for an Enhanced game,
  the score multiplier applies, and best games are kept per mutator set.

---

## 4. Open decisions

Each has a recommended default that the phases assume unless the owner decides otherwise.

| # | Decision | Recommended default | Needed by |
|---|---|---|---|
| D1 | Does Enhanced have its own unlocks and kill counts, or share them with Classic? | **Decided (2026-10-18): its own progression, separate from Classic.** Assumed: the Enhanced mode itself is available from the start | E0 |
| D2 | Which of E1's features also ship in Classic? | **Decided (2026-10-18): only the recipe book and the post-game report.** Classic should feel like the original game, so the combo preview, combo feedback, First/Last, turret stats, upgrade preview, next-wave preview, tips and every E8–E10 feature are Enhanced only | E1 |
| D3 | Keep the original number scale, or rebalance Enhanced onto a flatter curve? | **Decided (2026-10-18): keep the original scale for now; revisit later.** To keep a later rescale cheap, new effects (traits, path tiers, new turrets) are written as percentages and multipliers wherever possible, not fixed amounts | E2 |
| D4 | Do paths replace the three stat tracks in Enhanced, or sit on top of them? | **Decided (2026-10-18): on top.** The stat tracks stay; each path adds its own stat boosts and possibly abilities | E4 |
| D5 | Does Enhanced get a win condition (for example wave 100, then freeplay)? | **Decided (2026-10-18): yes, then freeplay after a win**, using the existing `continueAfterWin` flow. The winning wave is data (proposed: 100) | E2 |
| D6 | Which modes have achievements? | **Decided (2026-10-18): both modes**, since achievements never change gameplay. Each is tagged Classic, Enhanced or Both like the recipe book; progress is kept per mode, since progression is separate (D1) | E7 |

### Relation to the remaster's remaining phases
- E0, E1 and E8 can start at any time; they do not depend on Phases 6–8. E7 can start
  any time after E0.
- **Phase 7 (mod editor)** builds its editor automatically from the data schema. If the
  trait and path schema (E2, E4) exists before Phase 7, the mod editor supports it for
  free; otherwise Phase 7 must later learn the new field types. Settling the E2/E4 schema
  shape early is cheaper.
- Phase 6 map sharing should carry enough information for flyers (E3); a straight spawn-to-base
  line needs nothing new beyond the start and base positions already stored.

---

## 5. Backlog (not yet planned)

Ideas that need a decision before they become a phase:
- Path choice changes the combo a turret leads (a Warheads Red fires a bigger Nuke).
- New combo recipes for path capstones.
- Seeded daily challenge with a shared seed.
- Platform achievements (Game Center, Google Play Games). These are online services, so
  they need an explicit request first (rule R22); E7's achievements are local only.
- The recipe book marks recipes the player has already fired (uses E7's tracking).
- Generated maps through `MapGenerator` (generated maps must pass the map contract test
  and be winnable by the bots).
- More of the HD or restyled art pack for Enhanced (REMASTER_PLAN §5.2); it starts with the
  creep redraws (E0 bullet above).
- A hero or commander unit.
- Ideas considered on 2026-10-18 but not chosen yet:
  - Full refund for anything built or upgraded since the current wave started (the
    original refunds 70%).
  - Free turret moves between waves (the original charges $500).
  - Retry from a checkpoint every 10 waves, built on the replay plan's seeking
    ([REPLAY_PLAN.md](REPLAY_PLAN.md)).
  - Global powers: one-off abilities bought with cash, on a cooldown.
  - Terrain on maps: no-build zones and raised pads with bonus range.
  - Multiple roads or spawn points.

---

## 6. Adding a phase

Copy this template to the end of §3, numbered after the last phase:

```markdown
### Phase EN — <name>
- What it builds, as bullets: data, behaviours, UI, art.
- Which seams it uses (RulesRegistry, ContentPack, AssetPack, GameViewModel …).
- Tests: rule tests, scenarios, Enhanced fixtures, goldens, bot runs.
- **Done when**: one or two observable outcomes, plus Classic unchanged.
```

Then, in the same PR: move the idea out of the backlog if it came from there, add any new
open decision to §4, and add its rules to `docs/ENHANCED_REFERENCE.md` when the phase lands.
