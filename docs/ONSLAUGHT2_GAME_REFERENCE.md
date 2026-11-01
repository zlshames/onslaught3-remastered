# Onslaught 2 — Original Game Reference

This document captures how the original Flash game actually works, as read from the
deobfuscated ActionScript 2 source in `.legacy/deobfuscated/` (exported from
`.legacy/Onslaught2.swf` with FFDec's deobfuscator; `.legacy/dissassembled/` holds FFDec's
full export of the same SWF: art, sounds, fonts, texts, frames and raw scripts).

The SWF is build **2350-gaby**, the one inside Slipcor's "Onslaught 2.2" Windows projector on
itch.io (slipcor.itch.io/onslaught-2, Nov 2020, "exported with a test version of flash and the
original files from Gaby"). It replaced build 2221-nyehi on 2026-10-20; the differences are
listed under "Changes in 2350-gaby" below and everything else in this document holds for both.

It is the behavioural spec for the remaster. Numbers here become the seed values for the
remaster's data files; they are the original defaults, not necessarily what we ship.

Original authorship: the game's modding UI, Kongregate hooks and "playr.co.uk" map-share
service belong to the original author. The remaster re-implements the rules; it does not
reuse the obfuscated code.

## Changes in 2350-gaby (from 2221-nyehi)

Compared class by class, function by function, and asset by asset (2026-10-20). Every number the
remaster's data is built from (turrets, combos, projectiles, blasts, waves, creeps, maps,
challenge presets and pickers, tutorial pages, mod defaults) is the same; the legacy extraction
gives the same table from both builds. What changed:

- **Challenges unlock when the tutorial starts** (`GameManagerTutorial.setupFinal`): if Challenge
  is not yet available it says "Once you've played through the tutorial, have a go at the
  challenges, which you've now unlocked!." and unlocks it. The tutorial's win (`gameWin`) still
  unlocks it too, but stays unreachable (its 50-wave limit is still wiped by `resetGame`). The
  Mode screen's locked hint is now "Play the tutorial to unlock the challenges"
  (`GameSelectMode.toolTipSetup`).
- **Exit and Restart act at once**: the Game tab's Back and Restart buttons no longer open the
  "Are you sure?" panel (`TurretInfoExit`, removed); Back goes to the main menu and resets the
  game type to normal, Restart restarts (`turretinfo/TurretInfoGame.as`).
- **The settings window no longer saves the game speed** (`GameSettings.prefsSaveAndApply` drops
  `PrefTimeScale`), so the speed slider does nothing: games run at the speed already saved
  (`GameStatus.game_speed` = 100 % for a new player).
  Slipcor's devlog: the speed slider "was not working" in his export, so he disabled it.
- **The mod text box is read-only** (`ModImportExport`'s `TextArea` `editable = false`), so a
  mod can no longer be pasted in to load; loading text that does not parse now shows "# There
  were errors in the mod you pasted in." instead of failing silently
  (`mods/ModImportExport.as:onButtonLoad`). Mod import also traces each rejected value (debug
  output only; the checks themselves are unchanged).
- **Defaults**: sound pan spread `sound_pan_max` 1.6 → 1.7 (the `PrefSoundPan` default) and
  rocket smoke cap `rocket_smoke_max` 100 → 200 (the `PrefSmokeMax` default) (`GameStatus.as`).
- **The game screen has no mute button and no mod watermark**: main-timeline frame 37 no longer
  places `MuteButton` or `WatermarkMod` (the menu and the map editor keep the mute button).
- **Credits**: one at a time ("Code and Engine by Gaby Vanhegan" with the slipcor.net link, then
  "Sound by Anthony Galante"), 6 s instead of 3.8 s (`OpeningCredits.as`).
- **Hosting**: the domain lock is gone (frame 6), the map-share, map-rating and score services
  point at onslaught.slipcor.net instead of playr.co.uk, the MochiAd pre-game ad is removed, and
  a map passed in by the page (`_root.map_load`) starts straight into the game (frame 30).
- **Fonts**: the interface's Franklin Gothic Medium became Futura / Futura Condensed Extra, so
  labels re-wrap; the sounds are re-encoded (same clips and lengths) and three shapes draw their
  paths in another order (the red turret, its launcher, the sniper's weapon); no art changed.
- Debug-only additions: timestamped `GameManager.debug`, a road-point dump
  (`RoadManager.roadBuild`, `dump_points`), turret stat dumps (`Turret.modifyDumpStats`), XRay
  traces.

## Corrections from the legacy extraction (2026-10-18)

The original's values were extracted once into [`docs/legacy/`](legacy/README.md)
(`legacy_values.json`, tables in `LEGACY_VALUES.md`, behaviour in `ENGINE_NOTES.md`). Where this
document and that table disagree, **the table wins**; it is what `assets/data` is generated from.
The full list of discrepancies is `ENGINE_NOTES.md` §R. The ones that change numbers or rules:

- The game runs on the turret **class constructors**, not `mods/ModDefaults.as` (whose values the
  mod editor showed and applied only as deltas). Blue damage step 8 is **18 400** (fixed below);
  Fusion damage 1 000 000 (quirk 10).
- `combo_rate` (7/min) is computed but **never used**; the only combo cooldown is each recipe's
  recharge.
- Automatic freakouts are **never scheduled** in the original (an uninitialised `freak_next`
  guard), and the buy-now cost ($250 × seconds remaining) is then NaN, so no freakout ever happens in the
  original (corrected in Phase 2; this line used to say they start once bought). Key F is attacker focus.
  v1 fixes this (`freakoutAutoStart`: first freakout 60 s after it becomes available).
- The spawn-ward **shockwave walker removes itself** during construction, so only the base-ward
  walker runs. v1 fixes this (`shockwaveBothWalkers`).
- Yellow charge raises **poison only**; the damage boost is display-only.
- Yellow recipes test **exact** helper counts (Black Hole G == 1; Shockwave B == 1, G == 1; Tazer
  BFG B == 1). Sparky Landmine also takes a red if one is ready; Rocket BFG takes one red, not two.
- Landmines tween to their mine point in a fixed 1000 ms; BFGs fly straight; napalm drops are
  silent and use 1 000 000 damage.
- Mine points are `floor(segment / 4)` per segment, rounded to whole pixels.
- Sounds: `ONS2_scream_03` is BaseHit, `ONS2_basehit_02` is BaseDead; AttackerHit is silent; 42
  MP3s, three referenced clips are missing from the SWF.
- Ground art is bitmap 1021.jpg (1022.jpg in 2221-nyehi) stretched to 720×480.

Found while implementing Phase 1 (2026-10-18; citations in the code and tests):

- **Upgrades are refused while paused**, like every other turret command (`Turret.upgradeDamage`
  / `upgradeRange` / `upgradeRate` return early on `game_paused`). §14 used to say otherwise.
- **Wave timing**: `AttackerManager` and each `WaveManager` check their timers on a 200 ms
  interval, and both comparisons are strict. So wave 1 leaves at 20.2 s and every later wave
  20.2 s after the previous one (the exact 20 s check fails `> 20 000`), the first creep leaves
  200 ms after its wave, and creeps follow every **800 ms**, not 700.
- **Creep legs**: each leg tweens to the waypoint plus a fresh ±9 px jitter, but its duration is
  the distance to the *un-jittered* waypoint over the speed (`AttackerEngine.updateMove`), so
  jitter slightly changes the effective speed. Creeps spawn at the first road point ± 9 px.
- **Selling** refunds `ceil(cash_value × 0.7)` and also takes the refund off `total_spent`
  (`cashUnspend`), so it lowers the score's multiplier. **Moving** costs $500, which counts as
  spent but not as turret value.
- **Shots** leave from the weapon's `FirePoint` (Blue: 26 px along the barrel) and the weapon
  starts pointing up (−90°, Yellow 0°), both read from the SWF placements.
- **Target ties** go to the oldest creep, *assuming* AS2's `for…in` walks arrays newest-first:
  `targetAcquire` walks the attacker list twice (slice, then rank), which cancels out. Not
  observed in Flash; it only matters for exact ties (e.g. weak/strong on undamaged creeps).

Found while implementing Phase 2 (2026-10-18; citations in the code and tests):

- **Freakouts never happen in the original**: nothing schedules the first one, and the info
  panel's buy-now cost is then NaN, which `cashAvailable` never accepts. v1 schedules it
  (`freakoutAutoStart`); the classic profile keeps none.
- **Link pooling**: each green's neighbours are the link turrets within *its own* effective range.
  A helper that has no neighbour of its own pools **0** (it still fires at the leader, with sound,
  and spends its reload); a helper that does pools its own damage plus its own helpers'. A
  helper's beam is drawn into the leader and carries its own damage, which hits nothing. Offers
  are refreshed at the start of each green's update, so a green later in update order offers
  from the previous tick. Helpers are taken in build order (AS2 `for…in` order unobserved; it only
  matters when two helpers share a neighbour).
- **Holding**: the dispatch after a shot uses the turret's target *after* the shot, so with lock
  off the held rockets are sent at nothing (they then pick the nearest creep within 1000 px).
  Held rockets keep acquiring a target every tick but ignore it until dispatched.
- **Rockets** are removed off the 720×535 *stage* (not the 480 px play area) plus their width.
- **Yellow poison** on upgrade is `max(1, 10 × floor(level / 7 × 100) / 100)`: 1, 1.4, 2.8, 4.2,
  5.7, 7.1, 8.5, 10. A spark slows (subtract, floor 5, leg re-planned with a new jitter) before it
  hits.
- **Weapon unlocks** are per game (`total_kills` of the current game, reset by `resetGame`), with
  the message "New weapon available: " + the turret's class key; v1 shows its display name.
- **Modifier auras** are added and removed incrementally in the original; v1 recomputes them on
  every build, sale, move and upgrade, which gives the same sums.

Found while implementing Phase 3 (2026-10-18; citations in the code and tests, `ENGINE_NOTES.md` §1–§3):

- **Combos come first**: each colour's `turretTryFiring` tries `comboFire` before link pooling,
  charged shots or the plain shot; with no matching recipe the turret shoots its own way. A combo
  is not a shot (no fire sound, not counted, lock-off keeps the target); the leader's weapon
  reloads. `combo` is therefore the first special in every colour's data.
- **Helpers must be ready**: a helper counts only if it is combo-capable, has reloaded
  (`≥ 60000 / rate` ms since its last shot) and is past its own recharge. Each turret updates on
  its own timer (`setInterval(update, frame_space)`: 70 ms, Fusion 64, started when it is built or
  moved, real time), so a reloaded helper waits up to 70 ms for its next tick before firing, and a
  leader whose tick falls in that gap takes it. **Decided 2026-10-18: v1 models the timer**
  (`turrets.json` `tickMs`; it applied to Phases 1–2 too, whose fixtures were re-recorded). Effects:
  a turret fires on the first tick after it reloads, so real intervals are a little longer than
  `60000 / rate` (Blue's 600 ms reload gives 600–683 ms gaps); the first tick after a build does
  nothing (`time_last` starts undefined, so `now − time_last` is NaN), so a new turret first acts
  ~140 ms after it is built; charge, freakout scheduling and link offers move in 70 ms steps
  (freakout stages still run every frame, `FreakoutEngine.onEnterFrame`). Ticks land on the
  1/60 s simulation steps (every 66.7 or 83.3 ms, 70 on average); paused ticks do nothing but keep
  the timer's phase.
- **Which values a recipe uses** is per function, now in the data (`combos.json`): the green link
  pool goes only to `linkAddsTo` fields (cluster lasers for the laser cluster bombs; hit and lasers
  for the laser rocket; hit and blast for the shockwave; everything for the BFGs); values a
  function does not set fall back to the `Projectile` defaults *without* `modifyDamage` (Sparky
  Landmine's sparks: 1 000 000); the napalm rocket hits with the leader's own damage; the laser
  rocket's `laserblast_damage` is copied raw. BFGs are holding-capable (no visible effect: they
  fly straight).
- **Placed ordnance**: landmines and black holes start from the leader's centre. With no mine point
  within reach (landmines: the range track's maximum; black holes: 90 px) the original makes a
  clip at an undefined point that can never act; v1 removes it at once (assumption: not observed).
- **Black holes** catch creeps by radius but projectiles and blasts by the square box; caught creeps
  stay targetable and keep absorbing shots. The open/close tweens, the 200 ms scans and the pull
  run on the real-time clock (on while paused), the 3 s duration on game time.
- **Timers on intervals**: blasts deal their damage at `growMs` (the original's tween ticks every
  32 ms, so up to 31 ms later); shockwave zaps (every 32 ms) and napalm drops (every 75 ms) run on
  game time (the original uses real-time intervals skipped while paused).
- **Neighbourhood edge**: a turret built exactly 70 px from an older one is added to the older
  turret's list only when strictly inside 70 px (`comboNotifyNew`); v1 treats the range as
  inclusive both ways.
- **Taken helpers turn toward their leader** while they have no target (not Yellow, whose update
  has no such branch); v1 stops when they get a target, where Red keeps turning back once it loses
  it again.

Found while implementing Phase 4 (2026-10-18; citations in the code and tests, `ENGINE_NOTES.md` §4.6–§4.10):

- **Targeter**: joined turrets are sent at the painted creep through their *own*
  `turretTryFiring` (so a Fusion cannon discharges without its 6 s wait, a joined Targeter passes
  the trigger on, a Combonly plate fires its combo), ignoring their own range but still turning to
  face it and needing their reload; each then turns toward that creep while it has no target (the
  same `target_bear_to` slot a combo helper uses, the later one wins). With nothing joined it keeps
  its target even with lock off. Joins have no distance limit and are refused while paused;
  moving a joined turret lets it go (`notifyMove` = gone + new). The joiner is a tap mode in v1:
  "Join" on the sheet, then tap turrets to join or let them go, empty ground to finish.
- **Fusion**: only the **first reloaded feeder per 64 ms update** fires into it, and it keeps the
  same feeder list until a pass finds none ready, so a feeder built meanwhile joins only after such
  a pass. While it turns toward a target without facing it, its update returns before
  `time_last = now`, so the next turn step is longer: it turns faster the longer it turns (180° in
  ~0.5 s rather than 2 s). It fires even with an empty store; its discharge sound is set by its
  glow tier (`sound_fire`), and a store under one glow unit changes neither.
- **Railgun**: the damage pass runs on a 32 ms *real-time* interval (also while paused); every creep
  whose centre lies within 20 px of the 900 px beam (round ends included) is hit once. With no
  target at the moment it fires, the beam is not drawn and hits nothing.
- **Sniper**: a plain instant shot; the tracer and the brass casing (thrown from the weapon's
  BrassPoint (−2, 3) to BrassPointTo (−2, 30) ± 10 px, read from sprite 917) are cosmetic.
- **Combonly**: until it is locked in it updates every 1000 ms of real time (also while paused).
  Upgrades do not notify it; it rescans on its next update. The first colour shown after a scan is
  the *second* option (the count is reset to 0 and advanced before showing). Consumed turrets stop
  at once, their value goes into the plate's with no refund (the plate's sale refunds 70 % of the
  total), and they are removed 2 s later (real time) without their `onSell`. Its weapon is in place
  1.5 s after the click; meanwhile the plate is inactive. It fires its recipe silently: a helper's
  link pool adds 0, a helper's poison is 20, a BFG pools its own link turrets (greens within its
  300 px range) or fires an empty, counted shot, and its own damage is 0 (a napalm rocket hits for 0).
  **Its landmines never act**: the mine-point search uses the maximum of the range track, which a
  plate does not have (`upgradeGetMax` returns undefined), so — as for any landmine with no mine
  point (Phase 3) — v1 removes them at once. Five of the ten Blue options are landmines.
- **Order assumptions** (AS2 `for…in` over arrays and objects assumed to walk newest first, as
  elsewhere; not observed): Targeters trigger their joins newest first, Fusion feeders are taken
  newest first (`ENGINE_NOTES.md` §4.7 says creation order), Combonly options cycle in reverse order
  of each colour's first match. Only same-tick order and RNG draws depend on these.
- **Assumptions where the original breaks** (not copied): a click on a Combonly colour that is no
  longer an option is refused (the original would lock in nothing and never fire); selling a plate
  while its turrets are being consumed removes them at once; a consumed turret stops at once (the
  original lets it finish one more update); a joined turret that has not updated yet turns by 0
  (the original's `now − undefined` is NaN).
- **Sparks** are drawn with the original's `beam_size` widths and its full colour table up to 130M
  (the views had a 2 px line and stopped at 4M); presentation only.


Found while implementing Phase 5 (2026-10-18; citations in the code and tests):

- **Challenge set-up** (`GameManager.resetGame`): a challenge plays at its own difficulty with its
  own cash; its wave sizes and attacker speeds are cycled one entry per wave
  (`AttackerManager.waveSend`), each wave carrying a standard wave's HP and bounty shared among its
  creeps. The lists are strings in AS2 (`"60,40".split(",")`), but every use coerces them to
  numbers, so there is no string quirk. The turret limit counts every turret on the map.
- **Objectives**: the wave limit is reached at the first attempt to send the wave after it (the
  clock or "send now"); the kill target as soon as the kills reach it. Either ends the waves for
  good (`noMoreWaves`; waves already sending carry on) and starts the win check: **once a second of
  real time** (`setInterval(gameWinCheck, 1000)`, so also while paused), counted from when it
  starts; the game is won when the kill target (if any) is met and **the field is clear** (no creep
  on the road, no wave still sending). The time limit is checked on the wave manager's 200 ms
  check: time is up once `Math.round((limit − now) / 1000) <= 0`, i.e. half a second early (Warmup
  ends at 59.6 s). Then no more waves; passed (once the field is clear) if every objective was
  reached, otherwise **failed at once** (`gameOver`). After the waves end the manager stops, so the
  time limit is no longer checked. Lives running out fail a challenge. Assumption: the time limit
  runs from the start of the game (the original starts it in `setupFinal`, 50 ms of real time
  after the reset).
- **Best games** (`challengeSaveBest`) are saved on a pass *and* on a fail, under the challenge's
  encoded string (`challengeEncode`: difficulty; objective; cash; time; turrets; sizes; speeds,
  `undefined` for none; the MD5 is dropped), so a custom challenge that matches a preset shares its
  record. With a kill target the best game is the one with strictly more kills, otherwise strictly
  more score. A pass ticks the challenge (`ModesComplete`) separately.
- **Unlock milestones** fire on the kill that makes the total *exactly* 2000 or 4000
  (`modeUpdate`, `==`), only in normal games (extreme is a normal game); each message only when
  the mode was not already unlocked or complete. The messages say "200 waves" / "400 waves" for
  2000 / 4000 kills, verbatim.
- **Tutorial**: six pages show their arrow as they open (`show_now`: pages 1, 2, 3, 10, 17, 20);
  the arrow blinks for 7 × 400 ms. Page 15's "Show me" sets the cash to 14 500 once (not added,
  not counted as spent). The tutorial starts paused. v1 maps the original's pointer targets to the
  touch HUD (wave clock, cash, pause, tray, the selected-turret sheet for the upgrade panel, the
  message toasts for the info point, the back button for the Game tab).
- **Attract demo** (`GameManagerIntro`, main-timeline frame 35): a 12-point road over the whole
  720 × 535 stage (its last point lies just below it), on a ground stretched to cover that stage with four decorations of its own, 19 preset level-1 turrets (Blue 4, Green 5,
  Red 5, Yellow 5), one creep a wave every 6 s from the first three types, base energy 1050 grown
  by easy's schedule and ×10 for the one-creep wave, no size bump, no lives lost, kills reset to 0
  on every kill. Its creeps are far too tough for level-1 turrets, so it is a parade. v1 plays it
  silently behind the menu.
- **Sandbox**: the original has one Sandbox button, which plays the super sandbox once it is
  unlocked; v1 offers both from that button.
- **Original breakages not copied in v1** (presentation or app flow only; the "(app)" rows of
  `docs/DEVIATIONS.md`): after a game whose win check started,
  Restart can never win again (`resetGame` clears `interval_gamewin` but leaves it set, so
  `gameWinCheckSetup` never restarts it), whereas each v1 game starts fresh; the challenge-over
  panel's Time is never set (`total_time`), v1 shows the time played; a won game keeps running with
  no waves in the original, v1 stops its clock and its win dialog (challenges and the tutorial)
  offers Continue Playing, Restart, Main Menu and Watch Replay (disabled until replays exist);
  Continue Playing is freeplay (`continueAfterWin`, owner request): the waves resume with the same
  growth, no time limit, no further win, and the win, pass and best game recorded at the win
  stand; the game ends when the lives run out. Closing the settings
  window always unpauses (`pauseOff`), v1 restores the pause state it found.

---

## 1. Stage, time and coordinate system

| Item | Value | Source |
|---|---|---|
| Play area | 720 × 480 px (`game_area_x/y`) | `GameStatus` |
| Screen | 720 × 535 px (55 px bottom bar: build panel / weapon rack) | `GameStatus` |
| Game clock | `GameClock.time_now` advances by real ms × `game_speed/100`; frozen while paused or game over | `GameClock` |
| Speed pref | `PrefTimeScale`, default 100 (%) | `GameManager.settingsInit` |
| Update cadence | Each object has its own `setInterval` (turrets 70 ms, attackers 64 ms, attacker manager 200 ms, wave manager 200 ms, turret manager 66 ms) | per class |
| Angles | degrees, 0° = +x, clockwise (Flash); `atan2(dy,dx)*57.296` | `OnslaughtObject.trigDegreesTo` |

Important: the original is **not** 1:1, it is 3:2 (720×480). All ranges/speeds below are in
these "world pixels". The remaster keeps this world unit so the tuning tables stay valid, and
puts a camera in front of it.

## 2. Economy and lives

| Item | Value |
|---|---|
| Starting cash | easy/medium/hard/extreme: **$30**; sandbox: 100 000; sandbox2 ("super sandbox"): 1 000 000; debug: 10 000 000 |
| Lives | **10** (`player_lives`), base hit = −1 life, 0 ⇒ game over |
| Kill bounty | `attacker_value` = current wave number (scaled by `10 / wave_size`) |
| Sell refund | `ceil(cash_value × 0.7)` where `cash_value` = purchase price + all upgrade costs |
| Score | `total_kills × total_spent` |

## 3. Waves and attackers (creeps)

Defaults (`AttackerManager`, `WaveManager`, `AttackerEngine`):

| Item | Value |
|---|---|
| Wave size | 10 creeps |
| Wave spacing | 20 000 ms (pref `PrefWaveSpace`, 5–40 s); "wave follow" pref sends next wave as soon as the field is empty |
| Creep spacing within wave | 700 ms |
| Attacker types | 9 visual types (`Attacker0`…`Attacker8`), chosen by `(wave_num − 1) % 9`; some types rotate to face travel direction (`repoint`: types 1,3,4,5,7,8) |
| Base HP | 10 at wave 1 |
| HP growth | each wave: `hp *= attacker_upgrade_rate`; the rate itself steps down at wave thresholds (table below) |
| Speed | easy/medium 60 px/s, hard/extreme 80 px/s |
| Waypoint jitter | ±9.5 px random offset per waypoint so creeps don't stack |
| Spawn fade-in | 225 ms |
| Size bump | creep scale = `100 + (10/wave_size − 1)×6` % (challenge waves with fewer creeps are bigger and have proportionally more HP and bounty) |

HP multiplier schedule (`attacker_hp_rate_*`: at wave W the per-wave multiplier becomes R):

| Difficulty | wave → multiplier |
|---|---|
| easy | 1→1.30, 10→1.20, 30→1.15, 40→1.10, 60→1.09, 80→1.05, 100→1.04, 120→1.03, 200→1.02 |
| medium | 1→1.30, 10→1.20, 20→1.25, 30→1.15, 40→1.10, 60→1.09, 80→1.05, 100→1.04, 120→1.03, 200→1.02 |
| hard | 1→1.40, 10→1.30, 30→1.20, 40→1.10, 60→1.05, 100→1.04, 120→1.03, 200→1.02 |
| extreme | 1→1.125 (flat) |

Creep behaviour (`AttackerEngine`):
- Moves waypoint-to-waypoint using a tween of duration `distance / move_speed` seconds.
- `attackerHit(damage, by)`: `energy -= damage`; at ≤0 the killing turret gets `turretKill()` credit, bounty is paid, kill counter increments.
- `attackerPoison(p, minus)`: slow. `minus==true` ⇒ `move_speed -= p`; else `move_speed /= p`; floor 5 px/s. Replenishes +2 px/s every 1000 ms until back to base speed. ("Poison" in this game means **slow**, not damage-over-time.)
- Black hole: creep becomes untargetable, bounty 0, sucked in and removed (no kill credit, "dirty kill").
- Endless mode: there is no final wave in normal play; the game is survival. Mode unlocks happen at kill counts (see §9).

## 4. Turrets — common model (`turrets.Turret`)

Every turret has three upgrade tracks (damage, range, rate), each an ordered list of
`{cost, amount}` steps. Upgrading sets the stat to the step's `amount` (absolute, not additive).

Effective stats (`modifyUpdate`):
```
effective = max(0, (base + added) * max(mult, 0.2))
rate_msec = 1000 / (rate_effective / 60)        // rate is "shots per minute"
```
`added`/`mult` accumulate from modifier turrets, freakouts and the yellow turret's charge.

Targeting (`OnslaughtObject.targetAcquire`): candidates are creeps inside the square bbox
and then inside the circle of `range_effective`; optional directional cone
(`target_angle_mode` engaged, spread 50/30/15°). Modes: `near, far, weak, strong, slow,
fast, old, young` (cycled per turret). `target_reacquire` ("lock off") drops the target after
each shot.

Rotation: `weapon_rotate` deg/s; `weapon_must_face` turrets only fire once bearing is within
1° (or within one tick of rotation).

Combo capability: a turret becomes `combo_capable` when its **damage track is 100 %
upgraded**. Combos consider other combo-capable, ready turrets within `combo_range = 70 px`.
Firing a combo "takes" the helper turrets (they get `combo_next = now + recharge − 1` and
visually turn toward the leader). `combo_rate = 7/min` ⇒ 8571 ms between a turret's combo
shots in addition to each combo's own `recharge`.

Freakout: Blue and Yellow (`freak_capable`) turrets at damage level ≥4 and rate level ≥4
periodically go berserk: 3 s warning, then 5 s of ×(1+3) damage mult and ×(1+4) rate mult,
jittering sprite. Next freakout is scheduled `freak_space/2 + rand(freak_space/2) −
rate_level×4000 ms` later (`freak_space` 80 000 ms). Keyboard `f` forces one at a cost
(`freak_now_cost_sec = 250` — see UI notes).

Moving a turret: allowed (`MoveShape`), keeps upgrades, re-evaluates all neighbour
relationships (modifiers, combos, links, fusion).

Random display names per type, e.g. Blue: BangBang, Cannon, Shooter…; Red: Rocket,
SAMTower, ScudMan…; Green: Laser, MeanGreen…; Yellow: Shocker, Tazer, Zap… (`TurretManager.type_names`).

## 5. The four basic turrets

| | Blue "Cannon" | Green "Laser" | Red "Rocket" | Yellow "Tazer" |
|---|---|---|---|---|
| Cost | 10 | 15 | 20 | 50 |
| Damage | 15 | 25 | 50 | 50 |
| Range | 130 | 100 | 200 | 70 |
| Rate (/min) | 100 | 60 | 50 | 60 |
| Rotate °/s | 270 | 270 | 270 | 720 |
| Must face | yes | yes | no | no |
| Projectile | `Bullet`…`Bullet9` (sprite changes with damage level) | `LaserBeam` (instant) | `Rocket`…`Rocket9` (homing) | `Spark` (chain lightning) |
| Default target mode | near | near | near | **fast**, lock off |
| Freakout | yes | no | no | yes |
| Special | — | **Link**: green turrets within range of each other pool damage (`link_mult` 1.25 per helper) into one beam; also feeds **Fusion** | **Holding pattern**: at range lvl ≥3 and rate lvl ≥3 keeps up to 4 rockets circling, dispatched at the next target | **Charge**: accumulates `charge_rate` (10 + 2×rate_lvl)/s up to `charge_max` (100 + 10×dmg_lvl); a charged shot adds `+charge/100` damage mult and `+3×charge/100` poison, costs 50 charge. `weapon_poison` scales 1→10 with damage %. Feeds Fusion |

Upgrade tracks (cost → new value):

- **Blue** damage: 20→30, 50→60, 100→150, 250→400, 600→1200, 1000→3100, 1100→8500, 1200→18400, 1500→46000. range: 30→140, 100→150, 200→165, 500→180, 950→220. rate: 50→110, 150→125, 300→140, 450→160, 950→180, 1000→200, 1450→240.
- **Green** damage: 20→50, 50→120, 125→400, 300→1500, 700→3900, 850→9300, 950→19500, 1000→35000. range: 15→110, 25→125, 40→140, 65→160, 105→180, 170→205, 275→230, 445→255, 720→285, 1100→320. rate: 30→65, 75→70, 180→80, 300→90, 450→105, 600→120, 800→135, 900→160, 1000→190.
- **Red** damage: 50→120, 100→350, 200→800, 350→1950, 650→6050, 1200→11500, 1300→27000, 1500→48900, 1500→65000. range: 35→210, 80→220, 160→230, 400→250, 900→275, 1100→300, 1300→325, 1500→350. rate: 30→60, 60→70, 115→85, 200→100, 340→115, 600→135, 900→155, 1050→180, 1150→210.
- **Yellow** damage: 40→75, 80→125, 190→200, 300→800, 600→3500, 1000→11000, 1100→30000. range: 50→75, 100→85, 300→105, 600→130, 1000→155. rate: 50→70, 100→80, 225→90, 390→100, 650→120, 1100→150, 1450→180.

## 6. Modifier turrets (`TurretModify`)

Passive aura, radius `weapon_range` 80 (one range upgrade: 1500 → 130). Affects every
`modify_possible` turret in radius by adding to its `added`/`mult` terms. Cannot be
modified, combo'd or joined. Unlock = total kills.

| Type | Unlock kills | Cost | Effect |
|---|---|---|---|
| RangeUp "Range Enhancer" | 300 | 2000 | range +100 |
| DamageUp "Damage Enhancer" | 450 | 5000 | damage ×+0.4 |
| RateUpExchange | 550 | 1200 | rate ×+0.6, damage ×−0.4, range ×−0.1 |
| RangeUpExchange | 700 | 1000 | range +100, rate ×−0.25 |
| RateUp | 850 | 3000 | rate ×+1.2 |
| DamageUpBig | 1000 | 8500 | damage ×+1.0 |
| DamageUpBigExchange | 1100 | 3500 | damage ×+1.0, range ×−0.3, rate ×−0.3 |

## 7. Super / utility turrets

| Type | Unlock | Cost | Stats | Behaviour |
|---|---|---|---|---|
| Targeter | 1200 | 1400 | range 120 (upgrades 250→140, 350→170, 500→200, 700→230), "rate" 240 | No weapon. Paints the fastest creep with a beam and **joins** up to 3 turrets (`join_max`), forcing them to fire at its target. Join is a drag-line UI from the targeter to another turret (`TurretJoiner`, 17 px snap). |
| Sniper | 1300 | 12000 | dmg 3 000 000, range 300, rate 30, rotate 90 | Instant hit (`BulletSniper`), ejects brass. Damage upgrades 5000→7M, 7500→15M, 10000→55M; range 4000→400, 4000→500; rate 5000→45, 8000→60. Never combos, can't be modified. |
| Fusion Cannon | 1400 | 12000 | dmg 1 000 000 (data says 4M), range 300, rate 30 | Green/Yellow turrets in range **fire into it** (the first reloaded one per 64 ms update; they also shoot creeps on their own updates); it stores `damage×1.15` and `poison×1.15`, then every >6 s (and reloaded, facing) discharges `min(stored, dmg_eff) + dmg_eff` as a Spark with up to 100 stored poison. Glow rings show stored energy. |
| Railgun | 1500 | 12000 | dmg 4 000 000, range 300, rate 30 | Piercing `RailLaser` line. Damage 5000→9M, 7500→15M, 10000→25M. |
| Combonly plate | 1600 | 5000 | range 300 (scan 70) | A plate that scans combo-capable turrets within 70 px, cycles through the combos they could form (colour glow, 1 s per option; table in `LEGACY_VALUES.md`, "Combonly scan"); tapping it while a colour is shown **consumes** those turrets (they fade into it; their value goes into its own, no refund) and the plate becomes a permanent dedicated combo weapon of that type (`combo_silent`: no helpers). Its landmines never act (no range track for the mine-point search). |

## 8. Combos (`Combos.init`, `Turret.comboFire*`, each colour's `comboFire`)

A combo-capable turret with a target checks helpers in 70 px and fires the **first matching
recipe** (ordered by priority in each class). Leader colour decides the family:

**Blue leader** (`TurretBlue.comboFire`, highest priority first):

| Recipe | Needs (besides leader) | Weapon | Blast |
|---|---|---|---|
| Big Laser Cluster Landmine | R2 G1 B1 | `LandmineBigClusterLaser` | Large; 10 laser clusters |
| Big Cluster Landmine | R2 B1 | `LandmineBigCluster` | Large; 10 clusters |
| Big Laser Cluster Bomb | R2 G1 | `ClusterBomb` | Large; 5 laser clusters |
| Big Cluster Bomb | R2 | `ClusterBomb` | Large; 10 clusters |
| Sparky Landmine | B1 Y1 | `LandmineSparky` | Small; 8 spark clusters |
| Sparky Cluster Bomb | R1 Y1 | `ClusterBomb` | Small; 8 spark clusters |
| Laser Cluster Bomb | R1 G1 | `ClusterBomb` | Medium; 5 laser clusters |
| Big Landmine | R1 B1 | `LandmineBig` | Large |
| Cluster Bomb | R1 | `ClusterBomb` | Small; 6 clusters |
| Landmine | B1 | `Landmine` | Small |

Landmines fly (220 px/s) to a random road "mine point" within the leader's max range and
wait for a creep.

**Red leader**: Nuke (B2; `RocketNuke`, Huge blast, 60M), Napalm (R1 Y1 B1; 16 sub-blasts
75 ms apart, jitter 30), Poison Gas (B1 G1; `RocketPoison`, poison blast /2 speed), Tazer
Rocket (Y1; laser_type Spark, poison from helper), Laser Rocket (G1; rocket that fires lasers
in flight + laser-blast of 6 beams on impact).

**Green leader**: Rocket BFG (R2 B1), BFG (R1 B1). BFG: slow (60 px/s) orb, reacquires
targets, fires lasers at 180/min while flying, BFG blast on impact; damage adds the green
link pool.

**Yellow leader**: Black Hole (Y2 G1; radius 120, 3 s, at a road point within 90 px),
Shockwave (Y1 B1 G1; poison 100 bullet / 75 blast), Tazer BFG (R1 B1).

Combo data table (damage values are absolute, `modifyDamage` of the leader is applied):

| key | recharge ms | bullet | cluster dmg×qty | blast dmg | extra |
|---|---|---|---|---|---|
| clusterbomb | 5000 | 5.0M | 3.3M×6 | 7.0M | holding |
| sparky_clusterbomb | 5000 | 5.5M | 0.8M×8 | 4.7M | ClusterSpark |
| big_clusterbomb | 6200 | 8.0M | 4.5M×10 | 8.0M | |
| big_sparky_clusterbomb | 6200 | 6.0M | 15k×12 | 5.0M | |
| laser_clusterbomb | 10000 | 2.0M | 2.0M×5 (+0.7M laser) | 4.0M | |
| big_laser_clusterbomb | 11400 | 4.0M | 2.0M×5 (+0.9M laser) | 6.0M | |
| landmine | 7000 | 10M | – | 9.0M | |
| big_landmine | 7000 | 9.0M | – | 15M | |
| sparky_landmine | 7000 | 9.0M | ×8 | 15M | |
| big_cluster_landmine | 8000 | 9.0M | 4.5M×10 | 15M | |
| big_laser_cluster_landmine | 10800 | 7.0M | 2.0M×10 (+1.0M laser) | 9.0M | |
| bfg / tazer_bfg | 9000 | 5.8M | – | 7.5M | laser 4.2M r250 @180/min, speed 60 |
| rocket_bfg | 9000 | 6.5M | – | 7.5M | +rocket 2.0M |
| laser_rocket | 3000 | 2.0M | – | – | laser 2.0M r200; laserblast 1.0M×6 r300; speed 100 |
| tazer_rocket | 3000 | 2.0M | – | – | laser 2.0M r200, Spark; speed 100 |
| poison_rocket | 5000 | 1000 | – | 100 | speed 150, blast poison 2 |
| nuke | 7400 | 9.0M | – | 60M | speed 150 |
| blackhole | 20000 | – | – | – | radius 120, 3000 ms |
| shockwave | 9000 | 1.0M (poison 100) | – | 1.0M (poison 75) | |
| napalm | 6500 | 2.0M | – | 2.5M | qty 16, timing 75, jitter 30 |

## 9. Game modes, unlocks, persistence (`GameManager`)

| Mode | Rules |
|---|---|
| normal (classic) | difficulty easy/medium/hard/(extreme, unlock); endless; score = kills × spent |
| tutorial | scripted; starting it unlocks **challenge** (completing it would too, but cannot happen: §14) |
| challenge | preset or custom: difficulty, objective (`w,N` survive N waves or `k,N` reach N kills), cash, time limit (s), turret limit, wave-size list, wave-speed list. Win when objective met (and field clear); best game saved per challenge hash |
| sandbox | unlocked by 4000 kills on medium; $100 000, all modifier turrets + targeter |
| sandbox2 | unlocked by 4000 kills on hard; $1 000 000, everything |
| modding | unlocked by 4000 kills on easy+medium+hard; edit every value in §3–§8 |
| mapping | map editor (see map doc) |

Kill milestones in normal mode: 2000 kills ⇒ extreme unlocked; 4000 kills ⇒ difficulty
"complete" + sandbox unlocks above. Turret unlocks by kills: 300 RangeUp, 450 DamageUp,
550 RateUpEx, 700 RangeUpEx, 850 RateUp, 1000 DamageUpBig, 1100 DamageUpBigEx, 1200
Targeter, 1300 Sniper, 1400 Fusion, 1500 Railgun, 1600 Combonly.

SharedObject "onslaught" keys: PrefPlayerName, PrefWaveSpace (s), PrefWaveFollow,
PrefWaveRemember, PrefSound, PrefSoundVolume (80), PrefSoundPan (1.7), PrefSoundNextWave,
PrefSmoke, PrefSmokeMax (200), PrefQuality, PrefTimeScale (100; the settings window never
saves it), ModesAvailable{mode:
md5}, ModesComplete{mode: md5}, ChallengeBestGame{md5: {score,kills,spend,date,…}},
ModActive, MapsSaved{name: mapJson}, plus league/account fields for the old online service.

## 10. Sounds (`symbols.csv`)

Event names → assets: Cannon (`ONS2_cannon_*`), Rocket (`ONS2_rocket_03/05/09`), Laser
(`ONS2_laser_09_var`), Tazer (`ONS2_taser_30`), Sniper (`sniper_03`), Fusion low/med/hi/max,
BlastSmall/Med, BFG, BlackHole, Combo (`combo_16`), FreakoutWarn/Start/End
(`FreakWarning_01`, `freakout_up_20`, `freakout_dn_20_shrt`), NextWave, Build
(`ONS2_turretmade_inv_4`), Sell (`weapon_sale_01`), Weapon unlock (`ONS2_newWeapon_1`),
AttackerHit/Dead (`ONS2_explode_05shrt_02`, `ONS2_scream_03`, `cartfall_14`), BaseHit
(`ONS2_basehit_02`), lives-remaining voice 1/2/3, Pause/UnPause, click/open/close/chime.
43 clips exported as MP3 in `.legacy/dissassembled/sounds/`.

## 11. Maps and roads (`RoadManager`, `BuildShape`)

There is **no tile grid**. A map is a single polyline of free-floating pixel points plus a
base position; the first point is the spawn, the last point is where the road meets the
base. One path per map, no branching; the road may cross or retrace itself. The 20 px grid
in the editor is only a snapping aid.

Map record (also the custom-map JSON format): `{ name, base: {x,y}, road: [{x,y}, …] }`.

Road rendering: 31 px round-capped polyline in `#666666` with a 28 px `#B2885B` core.
"Mine points" are generated every 4 px along the road and are what landmines / black holes
snap to.

Turret placement rules (`BuildShape.buildCheck`):
- not paused / game over; can afford cost; inside the play area; under `turret_limit`;
- centre-to-centre distance to every other turret ≥ 36 px (BuildArea footprint, so turrets are ~36 px circles);
- 8 sample points on a radius-19 circle around the cursor must not hit the road stroke or the base;
- moving an existing turret costs $500 and uses the same rules.

Built-in maps (spawn first, base last; base position separately):

| key | name | base | road |
|---|---|---|---|
| map1 | Classic | 574.9,75.7 | (0,446.2) (84,382) (300.45,382) (465.85,223.6) (636.9,223.6) (636.9,382) (465.85,382) (300.4,223.6) (192.2,223.6) (192.2,35.8) (84,35.8) (84,129.1) (574.4,129.1) |
| map2 | Incoming | 254.6,156.6 | (655,0) (655,410) (65,410) (65,65) (580,65) (580,335) (140,335) (140,140) (505,140) (505,260) (310,260) (310,240) |
| map3 | Ells | 48.2,323.2 | (715,65) (583.05,65) (583.05,390.55) (333.65,390.55) (332.85,254.85) (456.6,254.85) (456.6,65) (110.1,65) (110.1,254.85) (233.35,254.85) (233.35,353) (147.2,353) |
| map4 | Looping | 581.2,332.6 | (0,209.1) (48.5,144.55) (100.35,88.95) (161.2,50.5) (225.5,41.55) (287.55,89.6) (308.5,176.3) (316,273.8) (300.5,367.4) (212,407.45) (125.85,386.45) (75.5,337.4) (86.85,258.8) (136,201.8) (213.5,171.8) (333.55,177.35) (394.1,198.8) (456.05,230.2) (512.8,266.95) (580.05,261) (629.25,224.9) (653.4,169.3) (659.5,110.7) (614.5,55.9) (535.25,54.6) (459.8,99.25) (422.2,171.6) (406.05,305.3) (446.35,354.9) (524.5,376) (580.9,376) |
| map5 | Sinus | 587.2,249.8 | (0,302.25) (133.8,302.25) (156.55,283.45) (186.8,274.45) (217.05,302.25) (263.85,302.25) (294.1,366.15) (334.8,52.2) (363.6,415.75) (398.3,302.25) (470.65,302.25) (491.85,274.45) (537.15,262.45) (567.35,302.25) (585.65,302.25) |
| map6 | Puzzle | 564.6,356.8 | (0,43.7) (215,43.7) (215,277.8) (515,277.8) (515,43.7) (215,43.7) (515,277.8) (440,351.95) (365,426.1) (290,351.95) (215,277.8) (515,43.7) (639.85,43.7) (639.85,368.8) |
| map7 | Squarely | 24.6,356.8 | (639.85,0) (639.85,211.85) (462.75,211.85) (462.75,70.55) (559.8,70.55) (559.8,381.5) (255.95,381.5) (258.3,123.15) (404.3,123.15) (404.3,296.8) (164.3,296.8) (164.3,40.55) (347.55,40.55) (345.85,205.85) (97.25,205.85) (97.25,368.15) |
| map8 | Inspired | 324,191.8 | (0,233.95) (200.5,233.95) (200.5,54.05) (84.25,54.05) (84.25,162.3) (636.65,162.3) (636.65,54.05) (520.4,54.05) (520.4,415.5) (636.65,415.5) (636.65,308.8) (84.25,308.8) (84.25,415.5) (200.5,415.5) (200.5,233.95) (321.8,233.95) |
| map9 | Lyne | 585,380 | (0,0) (590,410) |
| map10 | Penta | 602,10 | (360,20) (220,60) (129,170) (129,310) (200,420) (360,460) (522,420) (590,310) (590,170) (500,60) (360,20) (200,420) (589,169) (130,170) (523,418) (360,20) (580,20) (607,37) |
| map11 | Bad Pipe | 580,360 | (20,460) (260,460) (260,300) (240,300) (240,240) (300,240) (280,180) (320,200) (320,140) (300,140) (280,120) (260,100) (260,80) (260,20) (280,40) (300,60) (320,80) (340,60) (360,40) (380,20) (380,80) (380,100) (360,120) (340,140) (320,140) (320,200) (360,180) (340,240) (320,240) (400,240) (400,300) (380,300) (260,300) (380,300) (380,460) (640,460) (645,437) |
| map12 | Miss Direction | 160,320 | (0,420) (580,420) (540,460) (700,460) (700,300) (660,340) (440,120) (480,80) (320,80) (320,220) (360,180) (560,380) (460,380) (660,200) (700,240) (700,100) (560,100) (600,140) (340,380) (220,260) (220,120) (280,120) (200,40) (120,120) (180,120) (180,240) (120,240) (120,160) (20,260) (120,360) (120,300) (180,300) (180,340) (184.9,337) |
| tutorial | Quick Tutorial | 570,350 | (720,100) (100,100) (100,410) (580,410) |

Map editor features (`GameManagerMapping`): draggable start marker and base (base has 31
entry markers; the road's last point is the entry marker nearest the last waypoint),
tap-to-add / drag-to-move / drag-off-screen-to-delete waypoints, midpoint "insert"
handles on every segment, 20 px grid snap + "align all", keyboard nudge (1 / 10 px),
save/overwrite/load/delete to local storage, clear, play, and the old online share/list/
load/rate service (plain JSON, no checksum). Validation is only "has start, has base".

Editor geometry and release rules (`GameManagerMapping.as`, Mapping frame placements via FFDec
swf2xml; data: `world.json` `editor`, from `engine.mapEditor` in `docs/legacy/`):
- Areas (bounding-box `hitTest`, edges included): **StartArea** x 0–720, y 0–465 (the start, and
  every new waypoint, must be in it); **BaseArea** x 0–720, y 0–445 (holds the base's `BasePoint`,
  its centre at (50, 47) from the top-left corner); **PlayArea** x 18–702, y 18–462 (a waypoint
  released outside it is deleted). A start or base released outside its area goes back to the
  palette.
- The road is start → waypoints → the base entry point nearest the last waypoint (or the start
  when there are none): `BP1`..`BP31` at (8.5, 20.5), (14.95, 17) … (91.05, 20.5) across the top,
  (95, 25.55) … (95, 68.3) down the right, (91.5, 73.35), (85, 77) … (15, 77) along the bottom,
  (8.5, 73.5) and (5, 67) … (5, 27) up the left, from the base's top-left corner; tried in that
  order, the first strictly nearest wins. Loading a map drops its last road point and recomputes it.
- New waypoints are appended at the end of the road (a click on the same position as an existing
  waypoint adds nothing); midpoint "+" handles insert at their segment. A click that moves a
  waypoint ≤ 2 px (|dx| + |dy|) selects it (toggles); Backspace deletes the selected one; arrows
  nudge it 1 px (Shift 10 px), clamped to 0–720 × 0–480. Keys 1/2/3 put the start, a new waypoint
  or the base (by its centre) at the cursor; Shift+2 inserts at the road's start.
- Grid snap (off by default, 20 px, every 6th line drawn heavier): a release snaps to the nearest
  of the four surrounding corners (tried top-left, top-right, bottom-left, bottom-right; ties keep
  the earlier), new waypoints snap down to the corner above-left; "align all" snaps everything.
- Saving asks for a name; a name in use is overwritten. Play with unsaved changes opens the save
  window first. Custom maps play at the current difficulty and mode.
- The remaster keeps these rules and adds a minimum road length (`docs/DEVIATIONS.md`).

## 12. Mod system (`mods.*`)

A mod is a **sparse delta over the defaults**: `mods.default[item][asset] = value`,
undefined means "use default". A single `ModActive` switch applies it. The editor exposes
most values in §3–§8 with a descriptor (title, description, min, max, step, unit) and
widgets per type (`number`, `integer`, `string`, `boolean`, `arrayIndexed` = parallel
key/value arrays such as `{cost:[…], amount:[…]}`). Export/import is the JSON of the deltas
(import replaces the whole mod and validates each value against min/max). The watermark
shows an MD5 of the mod JSON as a signature.

Details (all in `mods/`):

- **What can be edited** (`ModDefaults.initItemLibrary`, `initModAssets`): Game Settings,
  the four colours, seven modifiers, Sniper, Railgun, Fusion and 21 combos, each with a
  fixed asset list (`docs/legacy/legacy_values.json` `modEditor.assets`). A combo offers
  every field of its data, typed by `typeof` (recharge included). Combonly and Targeter
  have assets but no `item_library` entry, so they cannot be reached; `starting_cash_debug`
  has a descriptor but no asset entry. `Combo_big_sparky_clusterbomb` is listed but has no
  recipe. `integer` and `array` are declared but never shown (no widget case).
- **Descriptors** are keyed by asset only (shared by every item); class defaults are
  step 1 and key/value fields `keys`/`values`. For `arrayIndexed` values `min`/`max` bound
  the number of entries; for strings, the length.
- **Storage**: SharedObject `onslaught` → `mods["default"][item][asset]`, flushed on every
  change; editing always writes a delta, even one equal to the default. Indexed values are
  also stored flattened (`upgrade_damage_cost`, `upgrade_damage_amount`).
- **Reset**: "Reset to Defaults" on each panel, shown only when that level has changes:
  all (`modClear`), item (`itemDeltaClear`), asset (`assetDeltaClear`).
- **Applying** (`GameManager.resetGame` when active): turret availability, cost, unlock
  and starting cash; attacker-manager settings (`modManagers`; an indexed HP rate becomes
  `arr[wave] = rate`); each new turret (`Turret.modLoad` → `modTurret`). Quirks:
  `resetGame` then resets `turrets_available` to the four colours, so "Initial
  Availability" has no effect; `Combos.data` applies combo deltas **whether or not the
  mod is active** and writes them into the shared combo data.
- **Signature** (`modSignature`): `MD5(JSON.stringify(modAsObject()))`, lowercase hex, in
  `item_library` then asset order; shown only while active as
  `"Mod: " + name + ", signature: " + md5` (`GameManager.watermarkUpdate`). With a mod
  active the game-over panel hides score submission and map rating.
- **Import/export** (`ModImportExport`): the plain JSON of the deltas, no header or
  version. Load (`modFromObject`) clears every item and asset the text does not set;
  numbers (`Number(v)`) outside min/max are skipped and keep their old delta (NaN
  passes); booleans are `v == true`; indexed values take the shorter of the two arrays
  and only their entry count is checked. A parse error shows nothing; success shows
  "# Your mod was successfully loaded!".
- **Editor UI** (`ModInterface`): three sliding panels "Moddable Stuff" → item → asset;
  number values in a `NumericStepper` (clamps to min/max, snaps to step, silently),
  indexed values as rows with add above/below (midpoint of the neighbours), move and
  remove; under each value its description and "Min:", "Max:", "Units:" lines.
- **Unlock**: complete easy, medium and hard (§10).

The remaster keeps this model on its own data: `assets/data/mod_editor.json` (generated
from the table above) maps each item/asset to the value it edits in the data files, a mod
is a `ModDelta` patch of those files, and the editor reads defaults from the data, so it
shows what a game really uses (`docs/legacy/LEGACY_VALUES.md` lists where the original
editor's own defaults differed).

This is the strongest argument for the remaster's data-driven design: the original author
already treated every balance value as data with a schema. The remaster makes that schema
the primary source of truth instead of a bolt-on.

## 13. Projectiles, blasts and effects (`Projectile`, `*Engine`, `blasts.*`)

All movement is delta-time based (px/s) on the game clock; most objects tick every ~32 ms.
There is no object pooling in the original (every shot is a new MovieClip).

| Projectile | Behaviour |
|---|---|
| **Shell** (`Bullet`…`Bullet9`, Blue) | 900 px/s, perfect homing (snaps heading every tick), hit at <3 px, direct damage. Vanishes silently if the target dies. |
| **Sniper bullet** | Instant hit; draws a short tracer along the line; ejects a brass casing (cosmetic ring of 15). |
| **Rocket** (`Rocket`…`Rocket9`, Red, all combo rockets, BFG) | 250 px/s, turn 270 °/s shortest-way, impact radius 8 (BFG 10), re-acquires nearest target within 1000 px every tick. If `holding_capable` and no target it orbits (radius ≈53 px) forever; `holding_initially` rockets orbit the turret until dispatched. Optional on-board **laser** (`laser_capable`: fires `LaserBeam`/`Spark` at target within `laser_range` every `60000/laser_rate` ms) and **sub-rockets** (`rocket_capable`). On hit: blast → cluster → direct damage → remove. Leaves smoke trail (ring of 100). |
| **Laser beam** (Green) | Instant hit, direct damage, 350 ms fading line whose colour/width is a cosmetic damage tier. Immune to black holes. |
| **Rail laser** (Railgun) | Piercing 900 px beam, ~20 px half-width; every creep intersecting it takes full damage once; visual 125 ms. |
| **Spark** (Yellow, Fusion, shockwave carrier, cluster-spark children) | Instant: `attackerPoison(bullet_poison, subtract)` then direct damage; jagged lightning visual (segments ≈ dist/11, ±5.5 px jitter), 400 ms fade. |
| **Cluster bomb** | 750 px/s homing bomb; on impact (or target loss) spawns blast + cluster. |
| **Cluster blast** | Fans `cluster_qty` `Rocket9`s at `(i+1)/qty·360°`, 30 px out; each auto-targets nearest creep ≤1000 px, may hold/orbit, may carry lasers. |
| **Cluster spark** | Fans `qty` Sparks 40 px out, round-robin over creeps in a ±220 px box; each does `cluster_damage` and −20 speed. |
| **Landmine** (5 art variants) | Thrown 1000 ms to a road mine point (±5 px); when armed, checks every 150 ms for any creep in a ±20 px box, then blast + optional cluster. No lifetime. |

Blasts (`BlastEngine`): grow from 10 px to `size` over `grow` ms, then apply **full damage
to every creep within `size/2`, no falloff**, plus `attackerPoison(weapon_poison, divide)`;
then fade.

| Blast | grow ms | diameter | damage radius | fade ms | note |
|---|---|---|---|---|---|
| tiny (napalm drop) | 60 | 70 | 35 | 1500 | |
| BlastSmall | 70 | 100 | 50 | 1500 | |
| BlastMedium | 80 | 160 | 80 | 1750 | |
| BlastLarge | 80 | 190 | 95 | 2000 | |
| BlastHuge (nuke) | 90 | 250 | 125 | 2500 | |
| BlastPoison | 80 | 190 | 95 | 2500 | poison 2 ⇒ speed halved |
| BlastBFG | 80 | 190 | 95 | 2500 | |
| BlastShockwave | 105 | 200 | 100 | 2500 | poison 75 (divide ⇒ min speed) + spawns 2 shockwave walkers |
| BlastNapalm | – | – | – | – | spawner: 16 "tiny" drops 75 ms apart, 15 px along heading, ±15 px jitter |

**Black hole**: radius 120, 3000 ms, suction 500 px/s; creeps inside become immune/untargetable, are pulled to the centre and destroyed as "dirty kills" (no cash, no score, no credit); most projectiles inside are also pulled in (lasers/sparks immune).

**Shockwave walkers**: two creep-like objects spawned at the blast, one walking the road toward the base and one toward the spawn at 150 px/s for 3000 ms; every 32 ms they hit every creep within ±10 px for `damage × (1 − t/3000)` and slow by `poison × (1 − t/3000)` (subtract). No turret credit.

Slow ("poison") semantics: subtract (sparks, shockwave) or divide (blasts); floor 5 px/s; recovers +2 px/s every second.

Original quirks worth a deliberate decision in the remaster (fix unless noted):
1. Napalm drops ignore the combo's blast damage and use the 1 000 000 default.
2. Poison-rocket blast damage is not run through the leader's modifiers.
3. `laser_rocket`'s "laser-blast" fields were never implemented.
4. Landmines never use `bullet_damage` (only blast damage).
5. Black-hole kills give no cash/score (keep: it is a balance choice).
6. Shockwave walker kills give no turret credit.
7. "AttackerHit" has no sound asset (silent).
8. Holding rockets with no target orbit forever (add a lifetime or keep as a feature).
9. Black-hole suction runs on real time (ignores pause/game speed).
10. Fusion class default damage is 1 000 000 but the data table says 4 000 000 (the class wins unless a mod is active).

Sound: `SoundPlayer.play(event, source)` picks a random variant (`Event01..99`), pans by
x position (`(1.7·x/720 − 0.85)·100`, `sound_pan_max` = 1.7), volume 80. Event → file mapping is in §10.

## 14. Screens, HUD and input (original, PC-oriented)

Screen flow: preloader → credits → **main menu** (attract-mode demo game runs behind
it) → mode select → map select → game → game over / challenge over. Sub-pages: Mode,
Map ("Choose a Map", 12 thumbnails), Challenge (pickers + 14 presets + best-game stats),
Load-a-map (local library / shared list / minimap preview / rating), Mods (editor +
import/export), Mapping (editor), Tutorial (game + 24-page guided window).

Mode buttons: Easy / Medium / Hard / Extreme (locked: "Make 2000 kills on any difficulty")
/ Sandbox (locked: "Score 4000 kills on medium") / Quick Tutorial / Map Tools / Challenge
Games (locked: "Play the tutorial") / Mods (locked: "Complete easy, medium and hard").

In-game HUD (720×55 bottom bar, left→right): message/info envelope (flashes on new
message / new weapon), pause; **Build** carousel (48 px items, icon + `$cost`, 5-pip
damage/range/rate review or modifier text, hover tooltips); **Upgrade** panel (three rows
Damage/Range/Rate: bar graph + `$cost`/`Max!` button, Shift-click = max); **Game** readout
(Cash, Kills, Wave); **Next Wave** clock (sweep hand, click = send now). Top-left: challenge
target badges. A draggable floating info window (tabs: Build, Messages, Game, Settings,
Next Wave, Pause, and per-selected-turret General / Upgrades / Combos / type-specific tab
such as Link, Freakout, Holding, Charge, Fusion, Modify) duplicates most of this.

Interactions that are mouse/keyboard only in the original and need a touch design:

| Action | Original | Notes |
|---|---|---|
| Build | click rack item, ghost follows cursor, click to place; Shift keeps ghost | ghost shows range circle + CanBuild / CannotAfford / CannotBuild |
| Select | click turret; click again deselects; no deselect on empty ground | |
| Upgrade | Q/W/E or buttons; Shift = max | |
| Sell | S or button | 70 % refund |
| Move | M, $500 | same placement rules |
| Target mode | T cycles 8 modes; L toggles lock | **keyboard only** |
| Directional arc | D cycles off/50°/30°/15°, aimed at cursor; Shift+D re-aim | **keyboard + cursor only** |
| Join (Targeter) | J then rubber-band line, click target turret | **keyboard only** |
| Attacker focus | F then click creep: all turrets target it | **keyboard only** |
| Combo range display | C | |
| Range display | R | |
| Freakout now | "Buy" in Freakout tab, $250 × seconds remaining | |
| Combonly | click plate while a colour is shown | |
| Next wave | Space / clock / tab | |
| Pause | P / button / tab | build, upgrade, sell, move, target mode and wave send are all refused while paused (`Turret.upgradeDamage` checks `game_paused` too) |
| Speed | none: the settings slider (50–200 %) is never saved | no in-game fast-forward |
| Build hotkeys | 1–4 basic, 5–0/−, Shift+1–8 | |

Tooltips (rack items, locked modes), tab glows and the drag-to-place cursor are hover
dependent. Floating windows (info, settings, tutorial) are draggable.

Settings window ("Game Settings", pauses the game): player name, league fields, wave
spacing 10–20 s, send-next-wave-immediately, remember-wave-settings, announce wave, sound
on/volume 1–99/pan 0–2, rocket smoke on/max 1–500, quality low/med/high, time factor
50–200 % (shown but never saved).

Game over panel: Kills, Shots, Spend, Score, Restart, Main Menu, optional online score
submit and map rating (defunct service). Challenge over: Passed/Failed, Kills, Time
(never set: bug), Spend, Score.

Tutorial: 24 real pages (then joke pages) with a "Show Me" blinking arrow; page 15 grants
$14 500 once. Tutorial wave limit of 50 is wiped by a bug in `resetGame`, so the tutorial
win is unreachable in the original; Challenge unlocks when the tutorial starts instead.

Challenge presets (diff / objective / cash / time s / turret limit / wave size / speed):
Warmup easy/–/30/60/–/10/60 · Threetown easy/w300/30/–/–/10/60 · Spiffles hard/w100/30/1200/–/10/60 ·
Limitations medium/w300/30/–/15/10/60 · Problem3 easy/k3000/3000/1200/–/3/90 · Bounce
medium/k4000/3000/1200/–/"10,9,…,1"/60 · Bludgeon hard/–/30/900/15/1/90 · Longshine
medium/k1000/500/–/10/"1,2,3"/60 · Speedshine same at 120 · Hardshine hard/k1000/500/–/10/"1,2,3"/120 ·
Duration hard/w500/30/1800/–/10/60 · Clockers hard/–/30/1200/8/"10,10,10,1"/90 · Ripples
medium/w500/30/1800/–/10/"60,40" · Smollocks hard/w500/30/1800/15/10/"60,40".
Picker values: cash $30/$500/$3000/($50 000)/($1 000 000); time ∞, 30…2 min, 60 s; turret limit
∞/50/40/30/20/15/10/9/8/7/5; wave size 10/5/3/2/1 and cycles; speed 60/90/40/120 and cycles.

Credits: code and engine by Gaby Vanhegan (linking to slipcor.net; vanhegan.net in 2221-nyehi),
sound by Anthony Galante. Version string "2350-gaby" (`OnslaughtVersion.version`; "2221-nyehi"
before), "Onslaught 2.2" on itch.io.
