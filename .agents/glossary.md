# Glossary

| Term | Meaning in this project |
|---|---|
| Attacker / creep | An enemy walking the road from spawn to base. 9 visual types; HP grows per wave. |
| Base | The player's "Area 51" at the road's end; each creep that reaches it costs 1 of 10 lives. |
| Road / path / waypoints | A single polyline in 720×480 world px; first point = spawn, last = base entry. No grid. |
| Mine point | Points every 4 px along the road; landmines and black holes snap to them. |
| World px | The original pixel unit. All ranges, speeds and radii in data use it. |
| Turret / tower | A placed defence. Colours: Blue (cannon), Green (laser), Red (rocket), Yellow (tazer). |
| Modifier | A non-firing turret whose aura adds/multiplies damage, range or rate of turrets within 80 px. |
| Super turret | Sniper, Railgun, Fusion, Targeter, Combonly. Unlocked by kill count. |
| Upgrade track | Ordered `{cost, value}` steps for damage, range, rate; upgrading sets the stat to the step's value. |
| Effective stat | `max(0, (base + added) × max(mult, 0.2))`; `rateMs = 60000 / rate`. |
| Combo-capable | A turret whose damage track is 100 % upgraded. |
| Combo | A special weapon fired by a combo-capable leader using helper turrets within 70 px; 20 recipes keyed by colour counts. |
| Take / recharge | Helpers used by a combo are "taken" (cannot combo again until `recharge` ms pass). |
| Link | Green turrets within range pool damage into one beam (×1.25 per helper). |
| Fusion | Super turret that absorbs green/yellow fire into a store and discharges it. |
| Holding pattern | Red turret feature: up to 4 rockets orbit the turret until a target appears. |
| Charge | Yellow turret feature: accumulated energy that boosts damage and slow on the next shot. |
| Freakout | Timed berserk mode (×damage, ×rate) for Blue/Yellow once damage ≥ lvl 4 and rate ≥ lvl 4. |
| Targeter | Paints the fastest creep and forces up to 3 joined turrets to fire at it. |
| Join | The Targeter's link to another turret. |
| Combonly plate | Plate that consumes nearby combo-capable turrets to become a permanent combo weapon. |
| Poison / slow | A movement-speed reduction (subtract or divide; floor 5 px/s; recovers +2 px/s per second). Never damage over time. |
| Blast | Area damage: grows, then hits every creep within radius at full damage, no falloff. |
| Dirty kill | A creep destroyed by a black hole: no cash, no score, no turret credit. |
| Wave | 10 creeps (default) every 20 s; type rotates `(wave − 1) % 9`. |
| Difficulty | easy / medium / hard / extreme: changes HP growth schedule and creep speed only. |
| Challenge | A rule set: difficulty, objective (`w,N` waves or `k,N` kills), cash, time limit, turret limit, wave-size list, speed list. 14 presets. |
| Sandbox / sandbox2 | Unlockable modes with $100k / $1M and every turret available. |
| Mod / ModDelta | A sparse JSON override of the data layer, applied at session start. |
| Content pack | A shipped data overlay (maps, turrets, recipes, strings) selectable per profile. |
| Asset pack | Implementation of `AssetPack` resolving logical asset ids; classic, HD or procedural. |
| Rules profile | `classic` (bit-faithful), `classicFixed` (v1 default with listed fixes), future profiles. |
| Regression fixture | Recorded event log + state hashes for a canonical scenario; freezes v1 behaviour. |
| GameCommand / GameEvent | The only inputs to and outputs from the simulation core. |
| GameViewModel | The facade the HUD reads from and dispatches commands to; the UI's only dependency. |
