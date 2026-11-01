---
name: legacy-lookup
description: Answer "what did the original Onslaught 2 do for X?" by reading the deobfuscated ActionScript 2 source, citing it, and recording the answer in the game reference. Use whenever a rule, number, timing, recipe or UI behaviour is unclear or disputed, before implementing or changing it.
---

# Legacy lookup

The reference doc is the first stop; the source is the court of appeal. Never answer a
faithfulness question from memory.

## Procedure

1. **Check the reference first**: `grep -n -i "<term>" docs/ONSLAUGHT2_GAME_REFERENCE.md`.
   If it answers the question, cite the section and stop.
2. **Locate the class** with the table in `.agents/legacy-source.md` ("Where each rule
   lives"), or search: `grep -rn -i "<identifier>" .legacy/deobfuscated/__Packages | head`.
3. **Read the whole function**, not the matching line. Trace the value to where it is set:
   class defaults (`var x = 5` on the prototype) → `attachMovie` init object (overrides
   defaults, applied *before* the constructor) → mod overrides (`ModDefaults` only apply
   when a mod is active). When data and class disagree, the class value is what players
   saw unless a mod was active.
4. **Resolve units**: rates are per minute (`msec = 1000 / (rate / 60)`); angles are
   degrees, 0 = +x, y down; speeds are px/s; "poison" is a speed reduction; times are
   game-clock ms (scaled by time factor, frozen on pause) unless `timeNow(true)`.
5. **Write the answer** as: *behaviour in one or two sentences* + *the numbers* + *source*
   `path:function` + any quirk/bug noticed.
6. **Record it**: add or correct the row/sentence in `docs/ONSLAUGHT2_GAME_REFERENCE.md`
   in the same change. If the answer reveals an original bug you intend not to copy, add a
   row to `docs/DEVIATIONS.md` and a `RulesProfile` toggle (rule R10).

## Searching tips

```bash
grep -rn "function comboFire" .legacy/deobfuscated/__Packages/turrets/Turret.as          # all 20 recipes
grep -rn "Combos.combo_data\.\w* =" .legacy/deobfuscated/__Packages/Combos.as             # recipe keys
grep -rln "SoundPlayer.play(\"<Event>\"" .legacy/deobfuscated                            # who plays a sound
grep -n "layouts\.\(map[0-9]*\|tutorial\)" .legacy/deobfuscated/__Packages/RoadManager.as # map data
cut -d';' -f2 .legacy/dissassembled/symbolClass/symbols.csv | tr -d '"' | grep -i <name>  # asset symbol ids
```
Timeline/frame scripts (screen flow) are `.legacy/deobfuscated/frame_*/DoAction*.as`;
rendered screens are `.legacy/dissassembled/frames/*.png` (37 = HUD, 42 = editor, 25 = asset sheet).

## Standards

- Cite file and function for every faithfulness claim in code comments, tests and reports.
- Do not paste or port the AS2 code; describe the behaviour and re-implement it (rule R13).
- Never edit anything under `.legacy/` (rule R11). If a re-export is needed, use the
  `ffdec-asset-export` skill and write to a new folder.
- A lookup that changes the reference doc is a `docs:` commit; one that changes behaviour
  is a `fix:`/`feat:` with the reference update in the same commit.
